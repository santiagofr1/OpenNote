import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/export.dart';
import '../../data/import_folder.dart';
import '../../data/media_import.dart';
import '../../data/vynote_file.dart';
import '../../data/storage.dart';
import '../../data/updates.dart';
import '../../domain/domain.dart';
import '../../domain/version.dart';
import '../../sync/background_sync.dart';
import '../../sync/google_auth.dart';
import '../../sync/google_config.dart';
import '../../sync/sync_backend.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_lock.dart';
import '../../sync/sync_crypto.dart';
import '../../widgets/auto_scroller.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pdf_progress.dart';
import '../../widgets/update_dialog.dart';
import '../notebook/menus.dart';
import '../notebook/notebook_screen.dart';
import '../notebook/sections_menu.dart';
import 'folder_card.dart';
import 'library_drag.dart';
import 'move_dialog.dart';
import 'notebook_card.dart';
import 'options_menu.dart';
import 'sync_indicator.dart';
import 'sync_sheet.dart';

/// Biblioteca: las carpetas y los cuadernos de la carpeta actual (con su miniatura),
/// o los resultados de la búsqueda en todas las carpetas.
class Library extends StatefulWidget {
  const Library({super.key, this.root, this.backend, this.syncPoll, this.syncDebounce});
  final Directory? root;

  /// Cómo se conecta la sincronización (los tests pasan uno falso; null = Google).
  final SyncBackend? backend;

  /// Cada cuánto consulta la nube con la app en primer plano, y cuánto espera tras el último guardado (null = por defecto).
  final Duration? syncPoll, syncDebounce;
  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> with WidgetsBindingObserver {
  late final store = Storage(root: widget.root);
  final tools = ToolState();
  NotesIndex? index;
  UpdatePrefs updPrefs = UpdatePrefs();
  final thumbs = <String, NotebookDoc>{}; // primera hoja de cada cuaderno
  String? pressed; // cuaderno o carpeta mantenido (resaltado)
  String? current; // carpeta abierta (null = inicio)
  final searchCtl = TextEditingController();
  final scroll = ScrollController();
  final _scrollKey = GlobalKey();
  late final auto = AutoScroller(scroll, _scrollKey); // scroll automático al arrastrar cerca de los bordes
  String query = '';
  late final SyncController sync = SyncController(
      store: store,
      backend: widget.backend ?? GoogleBackend(),
      crypto: SyncCrypto(store: store),
      pollInterval: widget.syncPoll ?? const Duration(seconds: 45),
      debounce: widget.syncDebounce ?? const Duration(seconds: 5))
    ..busyNotebooks = (() => {?_openId})
    ..onSynced = ((_) => _reloadAfterSync());
  String? _openId; // cuaderno abierto en el editor: la sincronización solo le sube lo guardado, no le escribe
  bool _staleAfterSync = false; // bajó algo mientras había un cuaderno abierto: al cerrarlo se vuelve a leer todo

  bool get searching => query.trim().isNotEmpty;

  @override
  void dispose() {
    _menu.close();
    WidgetsBinding.instance.removeObserver(this);
    store.onSaved = null;
    sync.dispose();
    searchCtl.dispose();
    auto.stop();
    scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  // primer plano: sincroniza ya y consulta cada tanto; segundo plano: sin consultas (ver SyncController)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      sync.setForeground(SyncController.isForegroundState(state, desktop: !Platform.isAndroid && !Platform.isIOS));

  /// Segundo plano (solo Android): candado y marcas con la tarea de WorkManager, interruptor de las preferencias y
  /// registro/cancelación de la tarea (con un `backend` de prueba no se toca WorkManager).
  void _setupBackgroundSync(Map? prefs) {
    if (!BackgroundSync.supported) return;
    sync
      ..backgroundSupported = true
      ..backgroundEnabled = bgSyncEnabled(prefs)
      ..lock = SyncLock(store.dir)
      ..marks = SyncMarks(store.dir)
      ..onBackgroundChanged = (() => unawaited(_reloadAfterSync()))
      ..onBackgroundToggled = ((v) => store.savePrefs({kBgSyncPref: v}));
    if (widget.backend == null) {
      sync.applyBackground = (wanted) => wanted ? BackgroundSync.ensureRegistered() : BackgroundSync.cancel();
    }
  }

  Future<void> _load() async {
    await store.init();
    store.onSaved = (_) => sync.notifySaved();
    final prefs = await store.loadPrefs();
    _setupBackgroundSync(prefs);
    tools.load(prefs);
    updPrefs = UpdatePrefs.from(prefs);
    final idx = await store.loadIndex();
    setState(() => index = idx);
    unawaited(sync.init());
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoUpdateCheck());
    for (final nb in idx.notebooks) {
      final t = await store.loadSheetDoc(nb, 0);
      if (!mounted) return;
      if (t != null) setState(() => thumbs[nb.id] = t);
    }
  }

  /// Búsqueda automática al abrir: solo Android release, si está activada y pasaron 24 h. No bloquea nada.
  Future<void> _autoUpdateCheck() async {
    if (!Updates.autoSupported() || !updPrefs.due(DateTime.now())) return;
    final r = await Updates.check();
    if (r.failed) return; // sin info: en silencio, se reintenta en la próxima apertura
    updPrefs.lastCheck = DateTime.now().millisecondsSinceEpoch;
    await store.savePrefs(updPrefs.toJson());
    final u = r.update;
    if (u == null || u.version.toString() == updPrefs.skipped || !mounted) return;
    await _offer(u);
  }

  Future<void> _offer(UpdateInfo u) async {
    AppVersion? installed;
    try {
      installed = await Updates.installed();
    } catch (_) {}
    if (!mounted) return;
    await offerUpdate(context, u, installed: installed, onSkip: () async {
      updPrefs.skipped = u.version.toString();
      await store.savePrefs(updPrefs.toJson());
    });
  }

  /// "Buscar actualizaciones" a mano: ignora el plazo de 24 h y la versión omitida.
  Future<void> _manualUpdateCheck() async {
    snack(context, 'Buscando actualizaciones…', duration: const Duration(seconds: 2));
    final r = await Updates.check();
    if (!mounted) return;
    if (r.failed) {
      snack(context, 'No se pudo buscar actualizaciones ahora');
      return;
    }
    updPrefs.lastCheck = DateTime.now().millisecondsSinceEpoch;
    await store.savePrefs(updPrefs.toJson());
    if (!mounted) return;
    if (r.update == null) {
      snack(context, 'Ya tenés la última versión');
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await _offer(r.update!);
    }
  }

  /// La sincronización bajó cosas: se vuelve a leer el índice (si no hay un cuaderno abierto, que lo tiene en memoria).
  Future<void> _reloadAfterSync() async {
    if (!mounted) return;
    if (_openId != null) {
      _staleAfterSync = true;
      return;
    }
    _staleAfterSync = false;
    final idx = await store.loadIndex();
    if (!mounted || _openId != null) return;
    setState(() {
      index = idx;
      thumbs.removeWhere((id, _) => !idx.notebooks.any((n) => n.id == id));
    });
    for (final nb in idx.notebooks) {
      final t = await store.loadSheetDoc(nb, 0);
      if (!mounted) return;
      if (t != null) setState(() => thumbs[nb.id] = t);
    }
  }

  Future<void> _settings() async {
    final check = await showSafeSheet<String>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              key: const Key('checkUpdates'),
              leading: const Icon(Symbols.system_update, weight: 300),
              title: const Text('Buscar actualizaciones'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => Navigator.pop(ctx, 'check'),
            ),
            ListTile(
              key: const Key('syncMenu'),
              leading: const Icon(Symbols.cloud_sync, weight: 300),
              title: const Text('Sincronización con Google Drive'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => Navigator.pop(ctx, 'sync'),
            ),
            SwitchListTile(
              key: const Key('autoUpdates'),
              secondary: const Icon(Symbols.update, weight: 300),
              title: const Text('Buscar actualizaciones automáticamente'),
              value: updPrefs.auto,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onChanged: (v) {
                setS(() => updPrefs.auto = v);
                store.savePrefs(updPrefs.toJson());
              },
            ),
          ]),
        ),
      ),
    );
    if (check == 'check' && mounted) await _manualUpdateCheck();
    if (check == 'sync' && mounted) {
      await _openSyncSheet();
    }
  }

  /// favoritos primero; después los más recientes
  List<Notebook> _sorted(List<Notebook> list) => [...list]
    ..sort((a, b) => a.favorite != b.favorite ? (a.favorite ? -1 : 1) : b.updated.compareTo(a.updated));

  Future<void> _openSyncSheet() =>
      showSafeSheet<void>(context, (ctx) => SyncSheet(sync: sync, missing: widget.backend?.missingConfig ?? GoogleConfig.missing));

  Future<void> _open(Notebook nb, {bool askedPin = false}) async {
    if (nb.pin != null && !askedPin) {
      final p = await askPin(context, nb.name, subtitle: 'Este cuaderno está bloqueado');
      if (p == null || !mounted) return;
      if (hashPin(p) != nb.pin) {
        snack(context, 'PIN incorrecto');
        return;
      }
    }
    _openId = nb.id;
    final result = await Navigator.of(context).push<Object?>(PageRouteBuilder<Object?>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) =>
          NotebookScreen(store: store, index: index!, nb: nb, tools: tools, sync: sync, onOpenSync: _openSyncSheet),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutQuart);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child),
        );
      },
    ));
    // volvió: se guardó todo; refrescar miniatura y orden, y sincronizar el cuaderno que se cerró
    _openId = null;
    if (!mounted) return;
    if (result == 'refresh') {
      // "Actualizar" (aviso de cambios de otro dispositivo): ya está guardado y cerrado; se baja y se vuelve a abrir
      await sync.syncNow(manual: true);
      await sync.whenIdle();
      await _reloadAfterSync();
      final again = index?.notebooks.where((n) => n.id == nb.id).firstOrNull;
      if (mounted && again != null) return _open(again, askedPin: true);
      if (!mounted) return;
    }
    unawaited(sync.syncNow());
    if (_staleAfterSync) unawaited(_reloadAfterSync());
    if (!index!.notebooks.contains(nb)) {
      setState(() => thumbs.remove(nb.id)); // lo borraron desde adentro
      snack(context, 'Cuaderno borrado');
      return;
    }
    setState(() {});
    final t = await store.loadSheetDoc(nb, 0);
    if (mounted && t != null) setState(() => thumbs[nb.id] = t);
    // un link llevó a otro cuaderno: se abre como si se hubiera tocado su tarjeta (con su PIN si está bloqueado)
    if (result is String && result.startsWith('open:') && mounted) {
      final id = result.substring(5);
      final target = index!.notebooks.where((n) => n.id == id).firstOrNull;
      if (target == null) {
        snack(context, 'El cuaderno ya no existe');
      } else {
        return _open(target);
      }
    }
  }

  /// "+": cuaderno o carpeta nuevos, en la carpeta actual
  Future<void> _new() async {
    final v = await showSafeSheet<String>(
      context,
      (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (key, icon, label) in [
              ('newNotebook', Symbols.note_add, 'Cuaderno nuevo'),
              ('newFolder', Symbols.create_new_folder, 'Carpeta nueva'),
              ('importNotebook', Symbols.upload_file, 'Importar cuaderno .vynote'),
              ('importFolder', Symbols.folder_zip, 'Importar carpeta (.zip)'),
            ])
              ListTile(
                key: Key(key),
                leading: Icon(icon, weight: 300),
                title: Text(label),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => Navigator.pop(ctx, key),
              ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (v == 'newNotebook') await _createNotebook();
    if (v == 'newFolder') await _createFolder();
    if (v == 'importNotebook') await importVynote();
    if (v == 'importFolder') await importFolder();
  }

  /// Elige un `.vynote` y lo agrega como cuaderno nuevo (en la carpeta actual). También lo usan los tests.
  Future<void> importVynote() async {
    try {
      final bytes = await Pickers.vynote();
      if (bytes == null || !mounted) return;
      final nb = await importNotebookBytes(store, bytes, taken: {for (final n in index!.notebooks) n.name}, folder: current);
      index!.notebooks.add(nb);
      await store.saveIndex(index!);
      final t = await store.loadSheetDoc(nb, 0);
      if (!mounted) return;
      setState(() {
        if (t != null) thumbs[nb.id] = t;
      });
      snack(context, 'Importado como "${nb.name}"');
    } on VynoteException catch (e) {
      if (mounted) snack(context, 'No se pudo importar: ${e.message}');
    } catch (e) {
      if (mounted) snack(context, 'No se pudo importar: $e');
    }
  }

  /// Elige el `.zip` de una carpeta exportada como Vynote y la recrea (con sus subcarpetas) en la carpeta actual,
  /// con progreso cancelable. También lo usan los tests.
  Future<void> importFolder() async {
    final bytes = await Pickers.folderZip();
    if (bytes == null || !mounted) return;
    final progress = ValueNotifier<(int, int, String)>((0, 1, ''));
    final nav = Navigator.of(context);
    var cancel = false;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Importando carpeta'),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (ctx, v, _) {
            final style = TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 12),
              Text('Cuaderno ${v.$1 < v.$2 ? v.$1 + 1 : v.$2} de ${v.$2}', style: style),
              if (v.$3.isNotEmpty) Text(v.$3, style: style.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]);
          },
        ),
        actions: [TextButton(key: const Key('cancelFolderImport'), onPressed: () => cancel = true, child: const Text('Cancelar'))],
      ),
    ));
    try {
      final before = {for (final n in index!.notebooks) n.id};
      final r = await importFolderZip(store, index!, bytes,
          parent: current, onProgress: (a, b, n) => progress.value = (a, b, n), cancelled: () => cancel);
      if (nav.canPop()) nav.pop();
      if (!mounted) return;
      if (cancel) {
        snack(context, 'Importación cancelada');
        return;
      }
      await store.saveIndex(index!);
      final loaded = <String, NotebookDoc>{};
      for (final nb in index!.notebooks.where((n) => !before.contains(n.id))) {
        final t = await store.loadSheetDoc(nb, 0);
        if (t != null) loaded[nb.id] = t;
      }
      if (!mounted) return;
      setState(() => thumbs.addAll(loaded));
      final fail = r.failed.isEmpty ? '' : ' (${r.failed.length} no se pudieron leer)';
      snack(
          context,
          r.folder == null
              ? 'Importados ${r.imported} cuadernos$fail'
              : 'Carpeta "${r.folder!.name}" importada: ${r.imported} cuadernos$fail');
    } on VynoteException catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) snack(context, 'No se pudo importar: ${e.message}');
    } catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) snack(context, 'No se pudo importar: $e');
    }
  }

  /// Exporta el cuaderno entero como `.vynote` (copia los archivos de disco: no carga nada).
  Future<void> _exportVynote(Notebook nb) async {
    try {
      final bytes = await exportNotebookBytes(store, nb);
      final ok = await saveVynote(bytes, nb.name);
      if (ok && mounted) snack(context, 'Cuaderno "${nb.name}" guardado');
    } catch (e) {
      if (mounted) snack(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _createFolder() async {
    final name = (await askText(context, 'Carpeta nueva', hint: 'Ej: Facultad', ok: 'Crear'))?.trim();
    if (name == null || name.isEmpty) return;
    setState(() => index!.folders.add(Folder.create(name, parent: current)));
    await store.saveIndex(index!);
  }

  Future<void> _createNotebook() async {
    final pick = await askNewNotebook(context);
    final name = pick?.name.trim();
    if (pick == null || name == null || name.isEmpty) return;
    final nb = Notebook.create(name, canvas: pick.canvas)
      ..folder = current
      ..touch();
    final doc = NotebookDoc(nb);
    await store.saveNotebook(doc);
    index!.notebooks.add(nb);
    await store.saveIndex(index!);
    setState(() => thumbs[nb.id] = doc);
    await _open(nb);
  }

  Future<void> _rename(Notebook nb) async {
    final n = (await askText(context, 'Renombrar cuaderno', initial: nb.name))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => nb.name = n);
    await store.saveIndex(index!);
  }

  Future<void> _duplicate(Notebook nb) async {
    // se copian los archivos de las hojas: no se carga ni se decodifica nada del cuaderno
    final copy = Notebook(newId('n'), '${nb.name} (copia)', bg: nb.bg, image: nb.image, paper: nb.paper, spacing: nb.spacing, size: nb.size, folder: nb.folder, canvas: nb.canvas, canvasW: nb.canvasW)
      ..copySectionsFrom(nb) // las secciones y las hojas de TODAS (los archivos se copian todos)
      ..touch();
    await store.copyNotebookFiles(nb, copy);
    final t = await store.loadSheetDoc(copy, 0);
    if (t != null) thumbs[copy.id] = t;
    index!.notebooks.add(copy);
    await store.saveIndex(index!);
    setState(() {});
    if (mounted) snack(context, 'Cuaderno duplicado');
  }

  /// "Exportar" de la biblioteca: la misma hoja que el cuaderno, sin "PDF de esta hoja".
  Future<void> _export(Notebook nb) async {
    final v = await showExportSheet(context, store, tools);
    if (v == null || !mounted) return;
    switch (v) {
      case 'pdf':
        await _exportPdf(nb);
      case 'png':
        final secs = await askExportSections(context, nb); // con varias secciones, cuáles
        if (secs == null || !mounted) return;
        // solo una hoja queda cargada; las demás (y las de las otras secciones) se leen de disco de a una
        final doc = await store.openNotebook(nb, radius: 0);
        if (mounted) await exportPngFlow(context, store, doc, sections: secs);
      case 'vynote':
        await _exportVynote(nb);
    }
  }

  Future<void> _exportPdf(Notebook nb) async {
    final secs = await askExportSections(context, nb); // con varias secciones, cuáles
    if (secs == null || !mounted) return;
    // solo una hoja queda cargada; el PDF lee las demás (y las de las otras secciones) de disco de a una
    final doc = await store.openNotebook(nb, radius: 0);
    if (mounted) await exportPdfFlow(context, store, doc, sections: secs);
  }

  /// "Exportar" de una carpeta: todos sus cuadernos (y los de las subcarpetas) en un .zip.
  Future<void> _exportFolder(Folder f) async {
    final idx = index!;
    if (idx.notebookCount(f.id) == 0) {
      snack(context, 'La carpeta está vacía');
      return;
    }
    final fmt = await showFolderExportSheet(context);
    if (fmt == null || !mounted) return;
    await exportFolderFlow(context, store, idx, f, fmt);
  }

  Future<void> _delete(Notebook nb) async {
    if (!await confirmDeleteNotebook(context, nb)) return;
    await store.deleteNotebook(index!, nb);
    setState(() => thumbs.remove(nb.id));
  }

  void _goTo(String? folder) => setState(() {
        current = folder;
        searchCtl.clear();
        query = '';
      });

  Future<void> _moveNotebook(Notebook nb) async {
    final r = await askMoveTarget(context, index!, title: 'Mover "${nb.name}" a…', current: nb.folder);
    if (r == null || !mounted) return;
    setState(() => index!.moveNotebook(nb, r.id));
    await store.saveIndex(index!);
    if (mounted) snack(context, 'Movido a ${index!.pathLabel(r.id)}');
  }

  /// Soltó un cuaderno o carpeta sobre una carpeta o miga de pan ([target]; null = Inicio).
  /// Avisa "Movido a X" con "Deshacer".
  Future<void> _drop(LibraryDrag d, String? target) async {
    final idx = index!;
    if (!d.canDropOn(idx, target)) return;
    final before = d.parent;
    final nb = d.nb, f = d.folder;
    if (nb != null) {
      idx.moveNotebook(nb, target);
    } else if (!idx.moveFolder(f!, target)) {
      return;
    }
    setState(() {});
    await store.saveIndex(idx);
    if (!mounted) return;
    snack(context, '${nb != null ? 'Movido' : 'Movida'} a ${idx.pathLabel(target)}',
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            if (nb != null && idx.notebooks.contains(nb)) {
              idx.moveNotebook(nb, before);
            } else if (f != null && idx.folders.contains(f)) {
              f
                ..parent = before
                ..touch();
            } else {
              return; // lo borraron mientras tanto
            }
            if (mounted) setState(() {});
            await store.saveIndex(idx);
          },
        ));
  }

  Future<void> _renameFolder(Folder f) async {
    final n = (await askText(context, 'Renombrar carpeta', initial: f.name))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => f
      ..name = n
      ..touch());
    await store.saveIndex(index!);
  }

  Future<void> _moveFolder(Folder f) async {
    final r = await askMoveTarget(context, index!,
        title: 'Mover "${f.name}" a…', current: f.parent, exclude: {f.id, ...index!.descendantIds(f.id)});
    if (r == null || !mounted) return;
    if (!index!.moveFolder(f, r.id)) return;
    setState(() {});
    await store.saveIndex(index!);
    if (mounted) snack(context, 'Movida a ${index!.pathLabel(r.id)}');
  }

  Future<void> _deleteFolder(Folder f) async {
    final idx = index!;
    final empty = idx.notebooksIn(f.id).isEmpty && idx.childrenOf(f.id).isEmpty;
    FolderDelete? mode;
    if (empty) {
      if (!await confirmDelete(context, 'Borrar "${f.name}"', 'La carpeta está vacía.')) return;
      mode = FolderDelete.deleteContents;
    } else {
      mode = await _askFolderDelete(f);
      if (mode == null || !mounted) return;
      if (mode == FolderDelete.deleteContents) {
        final n = idx.notebookCount(f.id);
        final ok = await confirmDelete(context, 'Borrar todo',
            'Se borran la carpeta "${f.name}", sus subcarpetas y $n ${n == 1 ? 'cuaderno' : 'cuadernos'} con todas sus hojas. No se puede deshacer.');
        if (!ok || !mounted) return;
      }
    }
    final inside = current == f.id || idx.descendantIds(f.id).contains(current);
    final gone = idx.deleteFolder(f, mode); // cuadernos que se fueron del índice
    setState(() {
      for (final nb in gone) {
        thumbs.remove(nb.id);
      }
      if (inside) current = f.parent;
    });
    await store.saveIndex(idx);
    for (final nb in gone) {
      await store.removeNotebookFiles(nb.id);
    }
  }

  Future<FolderDelete?> _askFolderDelete(Folder f) {
    final parent = index!.pathOf(f.parent).isEmpty ? 'Inicio' : index!.folderById(f.parent)!.name;
    return showDialog<FolderDelete>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          scrollable: true,
          icon: Icon(Symbols.folder_delete, color: cs.error, weight: 300),
          title: Text('Borrar "${f.name}"'),
          content: Text('¿Qué hacemos con lo que tiene adentro?', style: TextStyle(color: cs.onSurfaceVariant)),
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton.tonal(
              key: const Key('folderKeep'),
              onPressed: () => Navigator.pop(ctx, FolderDelete.moveContentsToParent),
              child: Text('Sacar los cuadernos a $parent'),
            ),
            FilledButton(
              key: const Key('folderDeleteAll'),
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.pop(ctx, FolderDelete.deleteContents),
              child: const Text('Borrar todo'),
            ),
          ],
        );
      },
    );
  }

  /// mantener apretada una carpeta: opciones
  Future<void> _folderOptions(BuildContext card, Folder f) async {
    HapticFeedback.mediumImpact();
    setState(() => pressed = f.id);
    final v = await _optionsMenu(card, f.name, [
      (Symbols.edit, 'Renombrar', 'rename', null),
      (Symbols.drive_file_move, 'Mover a…', 'move', 'moveTo'),
      (Symbols.ios_share, 'Exportar', 'export', 'exportFolder'),
      (Symbols.delete, 'Borrar', 'delete', null),
    ]);
    if (!mounted) return;
    setState(() => pressed = null);
    switch (v) {
      case 'export':
        _exportFolder(f);
      case 'rename':
        _renameFolder(f);
      case 'move':
        _moveFolder(f);
      case 'delete':
        _deleteFolder(f);
    }
  }

  final _menu = OptionsMenu();

  void _closeMenu() => _menu.close();

  Future<String?> _optionsMenu(BuildContext card, String title, List<MenuItem> items) {
    final r = _menu.show(context, card, title, items);
    setState(() {}); // el PopScope se entera de que hay menú
    return r;
  }

  /// mantener apretado un cuaderno: opciones
  Future<void> _options(BuildContext card, Notebook nb) async {
    HapticFeedback.mediumImpact();
    setState(() => pressed = nb.id);
    final v = await _optionsMenu(card, nb.name, [
      (Symbols.open_in_new, 'Abrir', 'open', null),
      (Symbols.edit, 'Renombrar', 'rename', null),
      (Symbols.drive_file_move, 'Mover a…', 'move', 'moveTo'),
      (Symbols.content_copy, 'Duplicar', 'dup', null),
      (Symbols.ios_share, 'Exportar', 'export', 'exportNotebook'),
      (Symbols.delete, 'Borrar', 'delete', null),
    ]);
    if (!mounted) return;
    setState(() => pressed = null);
    switch (v) {
      case 'export':
        _export(nb);
      case 'open':
        _open(nb);
      case 'rename':
        _rename(nb);
      case 'move':
        _moveNotebook(nb);
      case 'dup':
        _duplicate(nb);
      case 'delete':
        _delete(nb);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = index;
    final hits = idx != null && searching ? idx.search(query) : null;
    final folders = idx == null ? <Folder>[] : (hits?.folders ?? idx.childrenOf(current));
    final nbs = idx == null ? <Notebook>[] : _sorted(hits?.notebooks ?? idx.notebooksIn(current));
    return PopScope(
      // atrás: primero cierra la búsqueda, después sube una carpeta, y recién al final sale
      canPop: current == null && !searching && !_menu.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menu.isOpen) {
          _closeMenu(); // atrás con el menú abierto: solo lo cierra
          setState(() {});
          return;
        }
        if (searching) {
          _goTo(current);
        } else {
          _goTo(idx?.folderById(current)?.parent);
        }
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        floatingActionButton: idx == null
            ? null
            : FloatingActionButton.extended(
                key: const Key('new'),
                onPressed: _new,
                icon: const Icon(Symbols.add, weight: 400),
                label: const Text('Nuevo'),
              ),
        body: idx == null
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(key: _scrollKey, controller: scroll, slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                    sliver: SliverToBoxAdapter(child: _header(idx, cs)),
                  ),
                ),
                if (folders.isEmpty && nbs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(searching ? Symbols.search_off : Symbols.menu_book,
                            size: 56, weight: 200, color: cs.onSurfaceVariant.withValues(alpha: .6)),
                        const SizedBox(height: 12),
                        Text(searching ? 'Sin resultados' : current == null ? 'Todavía no hay cuadernos' : 'Esta carpeta está vacía',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                      ]),
                    ),
                  ),
                if (folders.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 76,
                      ),
                      delegate: SliverChildListDelegate([
                        for (final f in folders)
                          DropZone(
                            key: Key('drop-${f.name}'),
                            accepts: (d) => d.canDropOn(idx, f.id),
                            onDrop: (d) => _drop(d, f.id),
                            builder: (_, hovering) => DragSource(
                              data: LibraryDrag.folder(f),
                              onHold: (c) => _folderOptions(c, f),
                              onHoldCancel: _closeMenu,
                              onMove: auto.moved,
                              onEnd: auto.stop,
                              child: FolderCard(
                                key: Key('folder-${f.name}'),
                                folder: f,
                                count: idx.notebookCount(f.id),
                                location: searching ? idx.pathLabel(f.parent) : null,
                                pressed: pressed == f.id,
                                dropping: hovering,
                                onTap: () => _goTo(f.id),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                if (nbs.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 210,
                        mainAxisSpacing: 22,
                        crossAxisSpacing: 18,
                        childAspectRatio: .58,
                      ),
                      delegate: SliverChildListDelegate([
                        for (final nb in nbs)
                          DragSource(
                            data: LibraryDrag.notebook(nb),
                            onHold: (c) => _options(c, nb),
                            onHoldCancel: _closeMenu,
                            onMove: auto.moved,
                            onEnd: auto.stop,
                            child: NotebookCard(
                              key: Key('nb-${nb.name}'),
                              nb: nb,
                              store: store,
                              thumb: thumbs[nb.id],
                              pressed: pressed == nb.id,
                              location: searching ? idx.pathLabel(nb.folder) : null,
                              onTap: () => _open(nb),
                            ),
                          ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _header(NotesIndex idx, ColorScheme cs) {
    final folder = idx.folderById(current);
    final n = idx.notebooksIn(current).length, nf = idx.childrenOf(current).length;
    final parts = [
      if (n > 0 || nf == 0) '$n ${n == 1 ? 'cuaderno' : 'cuadernos'}',
      if (nf > 0) '$nf ${nf == 1 ? 'carpeta' : 'carpetas'}',
    ];
    final sub = idx.notebooks.isEmpty && idx.folders.isEmpty
        ? 'Creá el primero para empezar'
        : '${parts.join(' · ')} · mantené uno apretado para opciones o arrastralo a una carpeta';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (folder != null)
          IconButton(
            key: const Key('up'),
            tooltip: 'Subir una carpeta',
            icon: const Icon(Symbols.arrow_back, weight: 400),
            onPressed: () => _goTo(folder.parent),
          ),
        Expanded(
          child: Text(folder?.name ?? 'Cuadernos',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
        ),
        SyncIndicator(sync: sync, onTap: _openSyncSheet),
        IconButton(
          key: const Key('libraryMenu'),
          tooltip: 'Más opciones',
          icon: const Icon(Symbols.more_vert, weight: 400),
          onPressed: _settings,
        ),
      ]),
      if (folder != null) _breadcrumb(idx, cs),
      const SizedBox(height: 4),
      Text(searching ? 'Resultados en todas las carpetas' : sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
      const SizedBox(height: 14),
      TextField(
        key: const Key('librarySearch'),
        controller: searchCtl,
        onChanged: (v) => setState(() => query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar cuadernos y carpetas',
          prefixIcon: const Icon(Symbols.search, weight: 300),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  key: const Key('librarySearchClear'),
                  tooltip: 'Borrar búsqueda',
                  icon: const Icon(Symbols.close, weight: 300),
                  onPressed: () => setState(() {
                    searchCtl.clear();
                    query = '';
                  }),
                ),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      ),
    ]);
  }

  /// Inicio › Facultad › Análisis (cada tramo lleva a esa carpeta, menos el último)
  Widget _breadcrumb(NotesIndex idx, ColorScheme cs) {
    final path = idx.pathOf(current);
    Widget crumb(String key, String name, String? id, {bool last = false}) => DropZone(
          accepts: (d) => d.canDropOn(idx, id),
          onDrop: (d) => _drop(d, id),
          builder: (_, hovering) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: hovering ? cs.primary.withValues(alpha: .18) : null,
              borderRadius: BorderRadius.circular(8),
              border: hovering ? Border.all(color: cs.primary, width: 1.5) : null,
            ),
            child: InkWell(
              key: Key(key),
              borderRadius: BorderRadius.circular(6),
              onTap: last ? null : () => _goTo(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                        color: last ? cs.onSurface : cs.primary)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        crumb('crumb-inicio', 'Inicio', null),
        for (final f in path) ...[
          Icon(Symbols.chevron_right, size: 16, color: cs.onSurfaceVariant),
          crumb('crumb-${f.name}', f.name, f.id, last: f == path.last),
        ],
      ]),
    );
  }
}
