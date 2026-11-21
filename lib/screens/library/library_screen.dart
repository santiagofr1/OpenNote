import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/storage.dart';
import '../../data/updates.dart';
import '../../domain/domain.dart';
import '../../domain/version.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pdf_progress.dart';
import '../../widgets/update_dialog.dart';
import '../notebook/notebook_screen.dart';
import 'folder_card.dart';
import 'move_dialog.dart';
import 'notebook_card.dart';

/// Biblioteca: las carpetas y los cuadernos de la carpeta actual (con su miniatura),
/// o los resultados de la búsqueda en todas las carpetas.
class Library extends StatefulWidget {
  const Library({super.key, this.root});
  final Directory? root;
  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  late final store = Storage(root: widget.root);
  final tools = ToolState();
  NotesIndex? index;
  UpdatePrefs updPrefs = UpdatePrefs();
  final thumbs = <String, NotebookDoc>{}; // primera hoja de cada cuaderno
  String? pressed; // cuaderno o carpeta mantenido (resaltado)
  String? current; // carpeta abierta (null = inicio)
  final searchCtl = TextEditingController();
  String query = '';

  bool get searching => query.trim().isNotEmpty;

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await store.init();
    final prefs = await store.loadPrefs();
    tools.load(prefs);
    updPrefs = UpdatePrefs.from(prefs);
    final idx = await store.loadIndex();
    setState(() => index = idx);
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

  Future<void> _settings() async {
    final check = await showSafeSheet<bool>(
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
              onTap: () => Navigator.pop(ctx, true),
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
    if (check == true && mounted) await _manualUpdateCheck();
  }

  /// favoritos primero; después los más recientes
  List<Notebook> _sorted(List<Notebook> list) => [...list]
    ..sort((a, b) => a.favorite != b.favorite ? (a.favorite ? -1 : 1) : b.updated.compareTo(a.updated));

  Future<void> _open(Notebook nb) async {
    if (nb.pin != null) {
      final p = await askPin(context, nb.name, subtitle: 'Este cuaderno está bloqueado');
      if (p == null || !mounted) return;
      if (hashPin(p) != nb.pin) {
        snack(context, 'PIN incorrecto');
        return;
      }
    }
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => NotebookScreen(store: store, index: index!, nb: nb, tools: tools),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutQuart);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child),
        );
      },
    ));
    // volvió: se guardó todo; refrescar miniatura y orden
    if (!mounted) return;
    if (!index!.notebooks.contains(nb)) {
      setState(() => thumbs.remove(nb.id)); // lo borraron desde adentro
      snack(context, 'Cuaderno borrado');
      return;
    }
    setState(() {});
    final t = await store.loadSheetDoc(nb, 0);
    if (mounted && t != null) setState(() => thumbs[nb.id] = t);
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
  }

  Future<void> _createFolder() async {
    final name = (await askText(context, 'Carpeta nueva', hint: 'Ej: Facultad', ok: 'Crear'))?.trim();
    if (name == null || name.isEmpty) return;
    setState(() => index!.folders.add(Folder.create(name, parent: current)));
    await store.saveIndex(index!);
  }

  Future<void> _createNotebook() async {
    final name = (await askText(context, 'Nuevo cuaderno', hint: 'Ej: Análisis II', ok: 'Crear'))?.trim();
    if (name == null || name.isEmpty) return;
    final nb = Notebook.create(name)
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
    final copy = Notebook(newId('n'), '${nb.name} (copia)', bg: nb.bg, paper: nb.paper, spacing: nb.spacing, folder: nb.folder)
      ..sheets.addAll(nb.sheets.map((s) => s.copy()))
      ..touch();
    await store.copyNotebookFiles(nb, copy);
    final t = await store.loadSheetDoc(copy, 0);
    if (t != null) thumbs[copy.id] = t;
    index!.notebooks.add(copy);
    await store.saveIndex(index!);
    setState(() {});
    if (mounted) snack(context, 'Cuaderno duplicado');
  }

  Future<void> _exportPdf(Notebook nb) async {
    // solo la primera hoja queda cargada; el PDF lee las demás de disco de a una
    final doc = await store.openNotebook(nb, radius: 0);
    if (mounted) await exportPdfFlow(context, store, doc);
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
  Future<void> _folderOptions(Folder f) async {
    HapticFeedback.mediumImpact();
    setState(() => pressed = f.id);
    final v = await _optionsSheet(f.name, [
      (Symbols.edit, 'Renombrar', 'rename', null),
      (Symbols.drive_file_move, 'Mover a…', 'move', 'moveTo'),
      (Symbols.delete, 'Borrar', 'delete', null),
    ]);
    if (!mounted) return;
    setState(() => pressed = null);
    switch (v) {
      case 'rename':
        _renameFolder(f);
      case 'move':
        _moveFolder(f);
      case 'delete':
        _deleteFolder(f);
    }
  }

  /// Hoja inferior de opciones: (ícono, texto, valor, key); "Borrar" va al final y en rojo.
  Future<String?> _optionsSheet(String title, List<(IconData, String, String, String?)> items) {
    final cs = Theme.of(context).colorScheme;
    return showSafeSheet<String>(
      context,
      (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            for (final (icon, label, value, key) in items) ...[
              if (value == 'delete') const Divider(indent: 16, endIndent: 16),
              ListTile(
                key: key == null ? null : Key(key),
                leading: Icon(icon, weight: 300, color: value == 'delete' ? cs.error : cs.onSurfaceVariant),
                title: Text(label, style: TextStyle(color: value == 'delete' ? cs.error : cs.onSurface)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => Navigator.pop(ctx, value),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// mantener apretado un cuaderno: opciones
  Future<void> _options(Notebook nb) async {
    HapticFeedback.mediumImpact();
    setState(() => pressed = nb.id);
    final v = await _optionsSheet(nb.name, [
      (Symbols.open_in_new, 'Abrir', 'open', null),
      (Symbols.edit, 'Renombrar', 'rename', null),
      (Symbols.drive_file_move, 'Mover a…', 'move', 'moveTo'),
      (Symbols.content_copy, 'Duplicar', 'dup', null),
      (Symbols.picture_as_pdf, 'Exportar a PDF', 'pdf', null),
      (Symbols.delete, 'Borrar', 'delete', null),
    ]);
    if (!mounted) return;
    setState(() => pressed = null);
    switch (v) {
      case 'open':
        _open(nb);
      case 'rename':
        _rename(nb);
      case 'move':
        _moveNotebook(nb);
      case 'dup':
        _duplicate(nb);
      case 'pdf':
        _exportPdf(nb);
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
      canPop: current == null && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
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
            : CustomScrollView(slivers: [
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
                          FolderCard(
                            key: Key('folder-${f.name}'),
                            folder: f,
                            count: idx.notebookCount(f.id),
                            location: searching ? idx.pathLabel(f.parent) : null,
                            pressed: pressed == f.id,
                            onTap: () => _goTo(f.id),
                            onLongPress: () => _folderOptions(f),
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
                          NotebookCard(
                            key: Key('nb-${nb.name}'),
                            nb: nb,
                            thumb: thumbs[nb.id],
                            pressed: pressed == nb.id,
                            location: searching ? idx.pathLabel(nb.folder) : null,
                            onTap: () => _open(nb),
                            onLongPress: () => _options(nb),
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
        : '${parts.join(' · ')} · mantené uno apretado para ver opciones';
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
    Widget crumb(String key, String name, String? id, {bool last = false}) => InkWell(
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
