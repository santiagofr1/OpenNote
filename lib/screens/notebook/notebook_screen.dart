import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export.dart';
import '../../data/media_import.dart';
import '../../data/opennote_file.dart';
import '../../data/storage.dart';
import '../../domain/domain.dart';
import '../../editor/history.dart';
import '../../editor/page_editor.dart';
import '../../editor/voice_recorder.dart';
import '../../sync/sync_controller.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pdf_progress.dart';
import '../library/sync_indicator.dart';
import 'index_panel.dart';
import 'menus.dart';
import 'pages_panel.dart';
import 'search.dart';
import 'sections_menu.dart';
import 'thumb_cache.dart';
import 'style_dialog.dart';

/// Un cuaderno abierto: barra de arriba, panel de hojas y el editor con toda la tira de hojas.
/// Guarda un rato después de cada cambio (solo las hojas que cambiaron), al salir y cuando la app pasa a segundo plano.
class NotebookScreen extends StatefulWidget {
  final Storage store;
  final NotesIndex index;
  final Notebook nb;
  final ToolState tools;

  /// La sincronización (para el indicador y el aviso de cambios de otro dispositivo) y cómo abrir su hoja. Opcionales.
  final SyncController? sync;
  final VoidCallback? onOpenSync;
  const NotebookScreen(
      {super.key, required this.store, required this.index, required this.nb, required this.tools, this.sync, this.onOpenSync});
  @override
  State<NotebookScreen> createState() => NotebookScreenState();
}

class NotebookScreenState extends State<NotebookScreen> with WidgetsBindingObserver {
  Storage get store => widget.store;
  Notebook get nb => widget.nb;
  final editorKey = GlobalKey<PageEditorState>();
  NotebookDoc? doc; // null mientras se lee del disco
  Timer? _saveTimer, _prefsTimer;
  bool _dirty = false, _indexDirty = false, _deleted = false;

  /// La grabación de voz en curso: vive acá (no en un diálogo), así se puede seguir escribiendo mientras graba.
  late final recorder = VoiceRecorder(store);

  // vista
  bool panel = false; // panel de hojas
  bool indexOpen = false; // panel del índice (a la derecha)
  bool reading = false; // modo lectura
  bool fullscreen = false;
  bool onlyBookmarks = false;

  // búsqueda
  bool searching = false;
  final searchCtrl = TextEditingController();
  List<SearchHit> hits = [];
  Timer? _searchTimer;
  int _searchGen = 0; // la búsqueda más nueva gana (leer de disco puede tardar)
  late final thumbs = SheetThumbCache(store); // miniaturas de las hojas sin cargar (panel)

  /// Hoja que se está viendo (la actualiza el editor al scrollear).
  final sheetNotifier = ValueNotifier(0);
  final _liveVersion = ValueNotifier(0); // cambió algo en la hoja abierta
  final _structure = ValueNotifier(0); // cambió el orden, la cantidad o el estilo de las hojas
  final _headings = ValueNotifier(0); // cambiaron los títulos del índice

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sheetNotifier.addListener(() {
      nb.last = sheetNotifier.value;
      _indexDirty = true;
    });
    _load();
  }

  Future<void> _load() async {
    // solo se leen las hojas cercanas a donde se estaba; el editor pide las demás al scrollear
    final d = await store.openNotebook(nb, around: nb.last);
    if (!mounted) return;
    sheetNotifier.value = nb.last.clamp(0, d.sheetCount - 1);
    setState(() => doc = d);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchCtrl.dispose();
    _searchTimer?.cancel();
    if (fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (recorder.recording) {
      unawaited(_closeVoice()); // el cuaderno se cierra grabando: se para y se guarda lo grabado hasta ahí
    } else {
      recorder.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush(); // al salir de la app, guardar ya
    // en segundo plano (paused) se sigue grabando, como cualquier grabador; si la app se cierra, se para y se guarda
    if (state == AppLifecycleState.detached) unawaited(stopVoice());
  }

  // ================= guardado =================
  void _docChanged() {
    // se borró (o se deshizo) el elemento que está grabando: se para y se tira lo grabado
    final r = recorder, id = r.itemId;
    if (id != null && r.inserted && doc != null && !doc!.items.containsKey(id)) unawaited(r.discard());
    _dirty = true;
    _liveVersion.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _prefsChanged() {
    _prefsTimer?.cancel();
    _prefsTimer = Timer(const Duration(milliseconds: 500), () => store.savePrefs(widget.tools.toJson()));
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_deleted) return;
    final d = doc;
    if (d != null && _dirty) {
      _dirty = false;
      nb.touch();
      await store.saveNotebook(d); // en otro isolate; solo escribe lo que cambió
      await _saveIndex();
    } else if (_indexDirty) {
      await _saveIndex();
    }
  }

  /// Lo pendiente ya no se guarda (se está borrando el cuaderno).
  void _discardPending() {
    _saveTimer?.cancel();
    _dirty = false;
    _indexDirty = false;
  }

  Future<void> _saveIndex() {
    _indexDirty = false;
    return store.saveIndex(widget.index);
  }

  /// salir del cuaderno: guarda todo y vuelve a la biblioteca
  Future<void> leave([Object? result]) async {
    await stopVoice(); // si estaba grabando, se guarda lo grabado hasta ahora
    await _flush();
    _prefsTimer?.cancel();
    await store.savePrefs(widget.tools.toJson());
    await _saveIndex();
    if (fullscreen) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop(result);
  }

  // ================= hojas =================
  int get curSheet => doc == null ? 0 : sheetNotifier.value.clamp(0, doc!.sheetCount - 1);

  /// Lleva la vista a la hoja [k].
  void _goTo(int k) {
    sheetNotifier.value = k;
    editorKey.currentState?.scrollToSheet(k);
  }

  /// Aplica una operación que cambia las hojas de lugar (los elementos corren) y va a la hoja [goTo].
  /// [op] hace el cambio en el documento y devuelve lo que hay que poder deshacer (vacío = no cambió nada).
  void _sheetOp(List<SheetOp> Function(NotebookDoc d) op, {int? goTo}) {
    final d = doc!;
    final ops = op(d);
    if (ops.isEmpty) return;
    _structure.value++;
    editorKey.currentState?.sheetsChanged(EditAction(sheetOps: ops));
    _showSheet(goTo);
    setState(() {});
  }

  void _showSheet(int? goTo) {
    if (goTo == null) return;
    goTo = goTo.clamp(0, doc!.sheetCount - 1);
    sheetNotifier.value = goTo;
    // el scroll mide el nuevo largo recién después de este cuadro
    WidgetsBinding.instance.addPostFrameCallback((_) => editorKey.currentState?.scrollToSheet(goTo!));
  }

  /// El editor deshizo / rehizo una operación de hojas, o agregó una hoja al final.
  void _sheetsChangedByEditor(int? goTo) {
    _structure.value++;
    _showSheet(goTo);
    setState(() {});
  }

  /// Cambios que no mueven elementos (título, marcador): no tocan el deshacer.
  void _metaChanged() {
    _structure.value++;
    _docChanged();
    setState(() {});
  }

  void _addSheetAfter(int k) =>
      _sheetOp((d) => [SheetPresenceOp.added(d, d.insertSheet(k + 1))], goTo: k + 1);

  Future<void> _renameSheet(int k) async {
    final m = doc!.sheets[k];
    final n = await askText(context, 'Nombre de la hoja ${k + 1}', initial: m.title, hint: 'Opcional');
    if (n == null) return;
    m.title = n.trim();
    _metaChanged();
  }

  Future<void> _deleteSheet(int k) async {
    final d = doc!;
    if (d.sheetCount < 2) {
      snack(context, 'No se puede borrar la única hoja del cuaderno');
      return;
    }
    if (!await confirmDelete(context, 'Borrar la hoja ${k + 1}', 'Se borra la hoja con todo lo que tiene (se puede deshacer).')) return;
    // para poder restaurarla, la hoja tiene que estar en memoria: si no está cargada se lee de disco antes
    final id = d.sheets[k].id;
    try {
      await store.loadSheets(d, [id]);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo leer la hoja: $e');
      return;
    }
    final i = d.indexOfSheet(id);
    if (!mounted || i < 0 || !d.isLoadedAt(i)) return;
    _sheetOp((d) => [?SheetPresenceOp.delete(d, i)], goTo: i.clamp(0, d.sheetCount - 2));
  }

  /// Duplica la hoja [k]: si no está cargada se lee de disco antes (la copia se arma en memoria y se guarda).
  Future<void> _duplicateSheet(int k) async {
    final d = doc!, id = d.sheets[k].id;
    try {
      await store.loadSheets(d, [id]);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo leer la hoja: $e');
      return;
    }
    final i = d.indexOfSheet(id); // pudo moverse mientras se leía
    if (!mounted || i < 0 || !d.isLoadedAt(i)) return;
    _sheetOp((d) => [SheetPresenceOp.added(d, d.duplicateSheet(i))], goTo: i + 1);
  }

  /// Lleva la hoja [from] a la posición [to] (menú del panel o arrastrando la miniatura).
  void _moveSheet(int from, int to) => _sheetOp((d) => [?SheetMoveOp.run(d, from, to)], goTo: to);

  void _toggleBookmark(int k) {
    final m = doc!.sheets[k];
    m.bookmark = !m.bookmark;
    HapticFeedback.selectionClick();
    _metaChanged();
  }

  void _sheetAction(int k, SheetAction a) {
    switch (a) {
      case SheetAction.rename:
        _renameSheet(k);
      case SheetAction.addAfter:
        _addSheetAfter(k);
      case SheetAction.duplicate:
        _duplicateSheet(k);
      case SheetAction.moveUp:
        _moveSheet(k, k - 1);
      case SheetAction.moveDown:
        _moveSheet(k, k + 1);
      case SheetAction.delete:
        _deleteSheet(k);
    }
  }

  // ================= secciones =================
  /// Despliega la lista de secciones debajo del botón del panel ([anchor], global) y ejecuta lo que se elija.
  Future<void> _sectionsList(Rect anchor) async {
    if (doc == null || _switching) return;
    final r = await showSectionsList(context, anchor, nb);
    if (r == null || !mounted) return;
    final id = r.id;
    switch (r.action) {
      case SectionAction.open:
        if (id != null) await _switchSection(id);
      case SectionAction.create:
        await _newSection();
      case SectionAction.rename:
        if (id != null) await _renameSection(id);
      case SectionAction.moveUp:
        if (id != null) await _moveSection(id, -1);
      case SectionAction.moveDown:
        if (id != null) await _moveSection(id, 1);
      case SectionAction.delete:
        if (id != null) await _deleteSection(id);
    }
  }

  bool _switching = false; // se está cambiando de sección (el documento no existe un momento)

  /// Cambia a la sección [id]: guarda lo pendiente y espera el guardado, suelta el documento (es otro: el historial
  /// de deshacer se vacía), activa la sección y reabre en su última hoja vista.
  Future<void> _switchSection(String id) async {
    if (_switching || doc == null || id == nb.activeSection.id) return;
    _switching = true;
    try {
      await stopVoice(); // una grabación en curso es de la sección que se deja: se guarda antes
      await _flush();
      await store.settle(nb.id);
      if (!mounted) return;
      // el documento viejo ya no vale: las hojas de [nb] van a ser otras
      searching = false;
      hits = [];
      searchCtrl.clear();
      setState(() => doc = null);
      NotebookDoc d;
      try {
        d = await store.openSection(nb, id);
      } catch (e) {
        if (mounted) snack(context, 'No se pudo abrir la sección: $e');
        d = await store.openNotebook(nb, around: nb.last); // se vuelve a la que estaba
      }
      if (!mounted) return;
      _indexDirty = true;
      sheetNotifier.value = nb.last.clamp(0, d.sheetCount - 1);
      _structure.value++;
      _headings.value++;
      _liveVersion.value++;
      setState(() => doc = d);
      await _saveIndex();
    } finally {
      _switching = false;
    }
  }

  String _newSectionName() {
    var n = nb.sections.length + 1;
    while (nb.sections.any((s) => s.name == 'Sección $n')) {
      n++;
    }
    return 'Sección $n';
  }

  /// Nueva sección al final, con una hoja en blanco del estilo del cuaderno; se abre.
  Future<void> _newSection() async {
    final n = (await askText(context, 'Nueva sección', initial: _newSectionName(), hint: 'Ej: Práctica', ok: 'Crear'))?.trim();
    if (n == null || n.isEmpty || !mounted) return;
    final s = nb.addSection(n); // todavía solo en memoria: la hoja en blanco se escribe al abrirla
    await _switchSection(s.id);
  }

  Future<void> _renameSection(String id) async {
    final s = nb.sectionById(id);
    if (s == null) return;
    final n = (await askText(context, 'Renombrar sección', initial: s.name))?.trim();
    if (n == null || n.isEmpty || !mounted) return;
    nb.renameSection(id, n);
    await _saveSections();
  }

  Future<void> _moveSection(String id, int delta) async {
    if (!nb.moveSection(id, delta)) return;
    await _saveSections();
  }

  /// Guarda `notebook.json` con los cambios de las secciones (nombre, orden) y refresca lo que las muestra.
  Future<void> _saveSections() async {
    final d = doc;
    if (d == null) return;
    nb.touch();
    _indexDirty = true;
    _structure.value++;
    if (mounted) setState(() {});
    await store.saveNotebook(d);
    await _saveIndex();
  }

  /// Borra la sección [id] con todas sus hojas (pide confirmación y dice cuántas son). Si es la abierta, se pasa antes a otra.
  Future<void> _deleteSection(String id) async {
    final s = nb.sectionById(id);
    if (s == null) return;
    if (nb.sections.length < 2) {
      snack(context, 'No se puede borrar la única sección del cuaderno');
      return;
    }
    final n = nb.sheetCountOf(id);
    if (!await confirmDelete(context, 'Borrar la sección "${s.name}"',
        'Se ${n == 1 ? 'borra 1 hoja con todo lo que tiene' : 'borran $n hojas con todo lo que tienen'}. No se puede deshacer.')) {
      return;
    }
    if (!mounted) return;
    if (id == nb.activeSection.id) {
      // se pasa a la sección de al lado (la de abajo, o la de arriba si era la última)
      final i = nb.sections.indexWhere((x) => x.id == id);
      final next = nb.sections[i + 1 < nb.sections.length ? i + 1 : i - 1].id;
      await _switchSection(next);
      if (!mounted || doc == null) return;
    }
    // los archivos de sus hojas los borra el guardado: ya no figuran entre las hojas vivas del cuaderno
    if (nb.removeSection(id) == null) return;
    await _saveSections();
  }

  // ================= insertar (+) =================
  /// También lo usan los tests.
  Future<void> runInsert(String v) async {
    final ed = editorKey.currentState;
    try {
      switch (v) {
        case 'image' || 'camera':
          final it = await makeImageItem(store, camera: v == 'camera');
          if (it != null) ed?.insertItem(it);
        case 'sticky':
          ed?.insertItem(makeSticky());
        case 'audio':
          final it = await makeAudioFileItem(store, name: nextAudioName(doc!.items.values));
          if (it != null) ed?.insertItem(it);
        case 'voice':
          await _startVoice();
        case 'sheet':
          _addSheetAfter(curSheet);
        case 'pdf':
          await _importPdf();
      }
    } catch (e) {
      if (mounted) snack(context, 'No se pudo insertar: $e');
    }
  }

  /// "Grabación de voz": empieza a grabar y pone YA el audio en la hoja visible como etiqueta "Grabando" (un elemento común:
  /// se mueve, se elige, se deshace). Se sigue escribiendo mientras graba; para con el botón de la etiqueta (ver [stopVoice]).
  Future<void> _startVoice() async {
    if (recorder.busy) {
      if (mounted) snack(context, 'Ya hay una grabación en curso');
      return;
    }
    final it = makeAudioItem('${newId('m')}.m4a', 0, name: nextAudioName(doc!.items.values));
    try {
      await recorder.start(it.id, it.file!);
    } on VoiceException catch (e) {
      if (mounted) snack(context, e.message);
      return;
    }
    final ed = editorKey.currentState;
    if (!mounted || ed == null) {
      await recorder.discard();
      return;
    }
    ed.insertItem(it, onInserted: () => recorder.inserted = true);
  }

  /// Cancela la grabación (X del indicador): tira lo grabado y saca el audio de la hoja sin dejar rastro en el historial
  /// (ver [PageEditor.removeItemForgetting]).
  Future<void> cancelVoice() async {
    final id = recorder.itemId;
    if (id == null) return;
    await recorder.discard();
    editorKey.currentState?.removeItemForgetting(id);
  }

  /// Para la grabación: renombra el archivo, le pone la duración al elemento, marca la hoja sucia y guarda.
  /// No hace nada si no había una grabación.
  Future<void> stopVoice() async {
    final res = await recorder.stop();
    if (res == null) return;
    final ed = editorKey.currentState;
    if (ed != null && ed.setAudioDuration(res.itemId, res.ms)) return; // ya avisó que cambió (guarda en 600 ms)
    final it = doc?.items[res.itemId];
    if (it == null) {
      unawaited(deleteQuietly(store.media(res.file))); // el elemento ya no está: el audio tampoco
      return;
    }
    // sin editor (el cuaderno se está cerrando): se le pone la duración al elemento y se guarda ya
    doc!.markDirtyElement(it);
    it.dur = res.ms;
    doc!.markDirtyElement(it);
    _dirty = true;
    await _flush();
  }

  /// El cuaderno se cierra (dispose) con una grabación en curso.
  Future<void> _closeVoice() async {
    try {
      if (_deleted) {
        await recorder.discard();
      } else {
        await stopVoice();
      }
    } finally {
      recorder.dispose();
    }
  }

  Future<void> _importPdf() async {
    if (!mounted) return;
    final progress = ValueNotifier(0);
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Importando PDF'),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (_, n, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(n == 0 ? 'Elegí el archivo…' : 'Hoja $n'),
          ]),
        ),
      ),
    ));
    final sheets = await importPdf(store, onPage: (n) => progress.value = n);
    if (mounted) Navigator.of(context).pop();
    if (sheets.isEmpty || !mounted) return;
    // después de la hoja actual
    final at = curSheet + 1;
    _sheetOp((d) => [
          for (var i = 0; i < sheets.length; i++)
            SheetPresenceOp.added(d, d.insertSheet(at + i, meta: sheets[i].$1, content: sheets[i].$2)),
        ], goTo: at);
    if (mounted) snack(context, '${sheets.length} ${sheets.length == 1 ? 'hoja importada' : 'hojas importadas'}');
  }

  // ================= menú ⋮ =================
  /// También lo usan los tests.
  Future<void> runMore(String v) async {
    switch (v) {
      case 'search':
        setState(() {
          searching = true;
          hits = [];
        });
      case 'style':
        await _styleDialog();
      case 'export':
        await _export();
      case 'fav':
        setState(() => nb.favorite = !nb.favorite);
        await _saveIndex();
        if (mounted) snack(context, nb.favorite ? 'Agregado a favoritos' : 'Quitado de favoritos');
      case 'lock':
        await _toggleLock();
      case 'share':
        final d = doc;
        if (d == null) return;
        final bytes = await buildPdfWithProgress(context, store, d);
        if (bytes == null) return;
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${nb.name}.pdf')],
          fileNameOverrides: ['${nb.name}.pdf'],
          title: nb.name,
        ));
      case 'print':
        final d = doc;
        if (d == null) return;
        await Printing.layoutPdf(name: nb.name, onLayout: (_) => buildNotebookPdf(store, d));
      case 'delete':
        if (!await confirmDeleteNotebook(context, nb)) return;
        _deleted = true;
        _discardPending();
        await store.deleteNotebook(widget.index, nb);
        if (mounted) Navigator.of(context).pop('deleted');
    }
  }

  Future<void> _toggleLock() async {
    if (nb.pin != null) {
      final p = await askPin(context, 'Quitar bloqueo', subtitle: 'Ingresá el PIN actual');
      if (p == null) return;
      if (hashPin(p) != nb.pin) {
        if (mounted) snack(context, 'PIN incorrecto');
        return;
      }
      setState(() => nb.pin = null);
      await _saveIndex();
      if (mounted) snack(context, 'Cuaderno desbloqueado');
      return;
    }
    final a = await askPin(context, 'Bloquear cuaderno', subtitle: 'Elegí un PIN de 4 o más números');
    if (a == null || !mounted) return;
    if (a.length < 4) {
      snack(context, 'El PIN tiene que tener al menos 4 números');
      return;
    }
    final b = await askPin(context, 'Repetí el PIN');
    if (b == null || !mounted) return;
    if (a != b) {
      snack(context, 'Los PIN no coinciden');
      return;
    }
    setState(() => nb.pin = hashPin(a));
    await _saveIndex();
    if (mounted) snack(context, 'Cuaderno bloqueado: se pide el PIN al abrirlo');
  }

  /// Exporta el cuaderno entero como `.opennote`: guarda lo pendiente y copia los archivos de disco.
  Future<void> _exportOpennote() async {
    if (doc == null) return;
    try {
      await _flush();
      final bytes = await exportNotebookBytes(store, nb);
      final ok = await saveOpennote(bytes, nb.name);
      if (ok && mounted) snack(context, 'Cuaderno guardado');
    } catch (e) {
      if (mounted) snack(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _export() async {
    final d = doc;
    if (d == null) return;
    final k = curSheet, meta = d.sheets[k];
    final sheetName = 'Hoja ${k + 1}${meta.title.isEmpty ? '' : ' · ${meta.title}'}';
    final v = await showExportSheet(context, sheetName: sheetName);
    if (v == null || !mounted) return;
    switch (v) {
      case 'pdf':
        final secs = await askExportSections(context, nb); // con varias secciones, cuáles
        if (secs != null && mounted) await exportPdfFlow(context, store, d, sections: secs);
      case 'sheet':
        await exportPdfFlow(context, store, d, only: [k], name: '${nb.name} - hoja ${k + 1}');
      case 'png':
        final secs = await askExportSections(context, nb);
        if (secs != null && mounted) await exportPngFlow(context, store, d, sections: secs);
      case 'sheetpng':
        final ok = await saveSheetPng(store, d, k, '${nb.name} - hoja ${k + 1}');
        if (ok && mounted) snack(context, 'Imagen guardada');
      case 'opennote':
        await _exportOpennote();
    }
  }

  /// Estilo de hoja: fondo, papel y espaciado de la hoja que se ve o de todo el cuaderno
  /// (en ese caso también de las hojas que se agreguen).
  Future<void> _styleDialog() async {
    final d = doc;
    if (d == null) return;
    final k = curSheet;
    final r = await showStyleDialog(context, d, sheet: k);
    if (r == null || !mounted) return;
    void apply(SheetMeta m) {
      m.bg = r.bg;
      m.paper = r.paper;
      m.spacing = r.spacing;
    }
    if (r.all) {
      nb.bg = r.bg;
      nb.paper = r.paper;
      nb.spacing = r.spacing;
      _indexDirty = true;
      d.sheets.forEach(apply);
    } else {
      apply(d.sheets[k]);
    }
    _structure.value++;
    _docChanged();
    editorKey.currentState?.refresh();
    if (mounted) setState(() {});
  }

  // ================= búsqueda =================
  void _search(String q) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 220), () async {
      final d = doc, gen = ++_searchGen;
      if (d == null || !mounted) return;
      // en TODAS las hojas: las no cargadas se leen de disco, de a una
      final r = await searchNotebookAll(store, d, q);
      if (mounted && gen == _searchGen) setState(() => hits = r);
    });
  }

  Future<void> _goHit(SearchHit h) async {
    setState(() => searching = false);
    if (h.id == null) {
      _goTo(h.sheet);
      return;
    }
    final d = doc!;
    if (!d.isLoaded(h.meta.id)) {
      // el texto está en una hoja sin cargar: se carga y recién ahí se va a él
      try {
        await store.loadSheets(d, [h.meta.id]);
      } catch (e) {
        if (mounted) snack(context, 'No se pudo leer la hoja: $e');
        return;
      }
      if (!mounted) return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => editorKey.currentState?.reveal(h.id!));
  }

  void _closeSearch() => setState(() {
        _searchGen++;
        searching = false;
        searchCtrl.clear();
        hits = [];
      });

  // ================= vista =================
  Future<void> _toggleFullscreen() async {
    setState(() => fullscreen = !fullscreen);
    await SystemChrome.setEnabledSystemUIMode(fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      // atrás del sistema: primero cierra la búsqueda o la pantalla completa
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (searching) {
          setState(() => searching = false);
        } else if (fullscreen) {
          _toggleFullscreen();
        } else {
          leave();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        body: SafeArea(
          top: !fullscreen,
          bottom: !fullscreen,
          child: Stack(children: [
            Column(children: [
              if (!fullscreen) _topBar(cs),
              if (!fullscreen && widget.sync != null) _remoteBanner(cs),
              Expanded(
                child: Row(children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutQuart,
                    child: panel && !fullscreen ? _pagesPanel() : const SizedBox(width: 0),
                  ),
                  Expanded(
                    child: doc == null
                        ? const Center(child: CircularProgressIndicator())
                        : PageEditor(
                            key: editorKey,
                            doc: doc!,
                            initialSheet: sheetNotifier.value,
                            sheetNotifier: sheetNotifier,
                            tools: widget.tools,
                            store: store,
                            readOnly: reading,
                            onChanged: _docChanged,
                            onPrefsChanged: _prefsChanged,
                            onSheetsChanged: _sheetsChangedByEditor,
                            onHeadingsChanged: () => _headings.value++,
                            recorder: recorder,
                            onStopRecording: stopVoice,
                          ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutQuart,
                    child: indexOpen && !fullscreen ? _indexPanel() : const SizedBox(width: 0),
                  ),
                ]),
              ),
            ]),
            if (searching && !fullscreen)
              Positioned(
                top: 64,
                right: 12,
                width: 420,
                child: SearchResults(query: searchCtrl.text, hits: hits, onTap: _goHit),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(child: _recordingIndicator(cs)),
            ),
            if (fullscreen)
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: cs.inverseSurface.withValues(alpha: .7),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Salir de pantalla completa',
                    onPressed: _toggleFullscreen,
                    icon: Icon(Symbols.close_fullscreen, weight: 300, color: cs.onInverseSurface),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Indicador flotante mientras se graba: nombre, tiempo, parar y cancelar; tocar el cuerpo lleva a donde está el audio.
  Widget _recordingIndicator(ColorScheme cs) => ListenableBuilder(
        listenable: recorder,
        builder: (_, _) {
          final id = recorder.itemId;
          if (id == null) return const SizedBox.shrink();
          final name = doc?.items[id]?.text ?? '';
          final red = cs.error;
          return Material(
            key: const ValueKey('recIndicator'),
            color: cs.surfaceContainerHigh,
            elevation: 6,
            shape: StadiumBorder(side: BorderSide(color: red.withValues(alpha: .35), width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => editorKey.currentState?.scrollToItem(id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _PulsingDot(color: red),
                    const SizedBox(width: 10),
                    Text(
                      'Grabando${name.isEmpty ? '' : ' · $name'}  ${fmtDuration(recorder.elapsedMs)}',
                      style: TextStyle(fontSize: 15, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ]),
                ),
              ),
              IconButton(
                key: const ValueKey('recIndicatorStop'),
                tooltip: 'Parar y guardar',
                onPressed: stopVoice,
                style: IconButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
                icon: const Icon(Symbols.stop, size: 20, fill: 1),
              ),
              IconButton(
                key: const ValueKey('recIndicatorCancel'),
                tooltip: 'Cancelar y descartar',
                onPressed: cancelVoice,
                icon: Icon(Symbols.close, size: 20, weight: 300, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
            ]),
          );
        },
      );

  // (mientras se cambia de sección no hay documento: el panel deja su lugar vacío)
  Widget _pagesPanel() => doc == null ? const SizedBox(width: 300) : PagesPanel(
        doc: doc!,
        thumbs: thumbs,
        current: sheetNotifier,
        structure: _structure,
        liveVersion: _liveVersion,
        onlyBookmarks: onlyBookmarks,
        onToggleBookmarksFilter: () => setState(() => onlyBookmarks = !onlyBookmarks),
        onSearch: () => setState(() => searching = true),
        onAdd: () => _addSheetAfter(curSheet),
        onOpen: _goTo,
        onToggleBookmark: _toggleBookmark,
        onAction: _sheetAction,
        onMove: _moveSheet,
        onSections: _sectionsList,
      );

  // (mientras se cambia de sección no hay documento: el panel deja su lugar vacío)
  Widget _indexPanel() => doc == null
      ? const SizedBox(width: 300)
      : IndexPanel(
          nb: nb,
          refresh: Listenable.merge([_headings, _structure]),
          onOpen: _openEntry,
          onAction: _entryAction,
        );

  /// Lleva la vista al título [e] (cambiando de sección si es de otra).
  Future<void> _openEntry(OutlineEntry e) async {
    if (e.sectionId != nb.activeSection.id) {
      await _switchSection(e.sectionId);
      if (!mounted || doc == null || nb.activeSection.id != e.sectionId) return;
      await WidgetsBinding.instance.endOfFrame; // que el editor nuevo ya esté armado
      if (!mounted) return;
    }
    sheetNotifier.value = e.sheet;
    editorKey.currentState?.scrollToSheetY(e.sheet, e.y);
  }

  /// Renombrar, cambiar de nivel o quitar un título desde el panel (puede ser de cualquier sección).
  Future<void> _entryAction(OutlineEntry e, IndexAction a) async {
    final m = nb.sheetsOf(e.sectionId).where((x) => x.id == e.sheetId).firstOrNull;
    final h = m?.heads.where((x) => x.id == e.headingId).firstOrNull;
    if (m == null || h == null) return;
    switch (a) {
      case IndexAction.rename:
        final n = (await askText(context, 'Renombrar título', initial: h.title))?.trim();
        if (n == null || n.isEmpty || !mounted) return;
        h.title = n.length > 120 ? n.substring(0, 120) : n;
      case IndexAction.levelUp:
        h.level = (e.level - 1).clamp(1, 9); // sobre el nivel que se ve, no sobre el guardado
      case IndexAction.levelDown:
        h.level = (e.level + 1).clamp(1, 9);
      case IndexAction.remove:
        m.heads.remove(h);
    }
    m.updated = DateTime.now().millisecondsSinceEpoch;
    _headings.value++;
    _docChanged();
    editorKey.currentState?.headingsChanged();
    if (mounted) setState(() {});
  }

  Widget _topBar(ColorScheme cs) {
    Widget act(IconData i, String tip, VoidCallback? f, {bool on = false, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: IconButton(
            key: key,
            tooltip: tip,
            onPressed: f,
            isSelected: on,
            style: IconButton.styleFrom(
              backgroundColor: on ? cs.secondaryContainer : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(i, size: 22, weight: on ? 400 : 300, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
          ),
        );
    // los menús se anclan en la esquina inferior derecha del botón
    Widget menuBtn(IconData i, String tip, Key key, Future<void> Function(Offset at) open) => Builder(
          builder: (c) => act(i, tip, () {
            final b = c.findRenderObject() as RenderBox;
            open(b.localToGlobal(b.size.bottomRight(Offset.zero)));
          }, key: key),
        );
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: cs.surfaceContainerLow,
      child: Row(children: [
        IconButton(
          key: const Key('back'),
          tooltip: 'Volver a los cuadernos',
          onPressed: leave,
          icon: Icon(Symbols.arrow_back, weight: 300, color: cs.onSurface),
        ),
        const SizedBox(width: 4),
        Expanded(child: searching ? _searchField() : _title(cs)),
        if (searching)
          act(Symbols.close, 'Cerrar búsqueda', _closeSearch)
        else ...[
          if (widget.sync != null && widget.onOpenSync != null) SyncIndicator(sync: widget.sync!, onTap: widget.onOpenSync!),
          act(Symbols.menu_book, reading ? 'Salir del modo lectura' : 'Modo lectura', () => setState(() => reading = !reading),
              on: reading, key: const Key('reading')),
          menuBtn(Symbols.add, 'Insertar', const Key('insert'), (at) async {
            final v = await showInsertMenu(context, at);
            if (v != null && mounted) await runInsert(v);
          }),
          act(Symbols.toc, 'Índice', () => setState(() => indexOpen = !indexOpen), on: indexOpen, key: const Key('indexBtn')),
          act(Symbols.view_sidebar, 'Hojas', () => setState(() => panel = !panel), on: panel, key: const Key('pagesBtn')),
          act(Symbols.open_in_full, 'Pantalla completa', _toggleFullscreen),
          menuBtn(Symbols.more_vert, 'Más opciones', const Key('more'), (at) async {
            final v = await showMoreMenu(context, at, nb);
            if (v != null && mounted) await runMore(v);
          }),
        ],
      ]),
    );
  }

  /// Aviso discreto: otro dispositivo cambió este cuaderno y acá no se le escribe encima mientras está abierto.
  /// "Actualizar" guarda, lo cierra, baja los cambios y lo vuelve a abrir.
  Widget _remoteBanner(ColorScheme cs) => ListenableBuilder(
        listenable: widget.sync!,
        builder: (context, _) {
          if (!widget.sync!.remoteWaiting.contains(nb.id)) return const SizedBox.shrink();
          return Container(
            key: const Key('remoteBanner'),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: cs.secondaryContainer,
            child: Row(children: [
              Icon(Symbols.devices, size: 18, weight: 300, color: cs.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Hay cambios de otro dispositivo',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: cs.onSecondaryContainer)),
              ),
              TextButton(key: const Key('remoteRefresh'), onPressed: () => leave('refresh'), child: const Text('Actualizar')),
            ]),
          );
        },
      );

  Widget _searchField() => TextField(
        key: const Key('searchField'),
        controller: searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Buscar en "${nb.name}"',
          prefixIcon: const Icon(Symbols.search, weight: 300),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: _search,
      );

  /// Nombre del cuaderno (siempre arriba a la izquierda) y la hoja que se ve: "2 / 5".
  Widget _title(ColorScheme cs) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Text(nb.name,
                key: const Key('nbTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: cs.onSurface)),
          ),
          if (nb.favorite)
            Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Symbols.star, size: 18, fill: 1, color: cs.primary)),
          if (nb.pin != null)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Symbols.lock, size: 16, weight: 400, color: cs.onSurfaceVariant)),
        ]),
        if (doc != null)
          ListenableBuilder(
            listenable: Listenable.merge([sheetNotifier, _structure]),
            builder: (_, _) {
              final k = curSheet, t = doc!.sheets[k].title;
              return Text('${t.isEmpty ? '' : '$t · '}${k + 1} / ${doc!.sheetCount}',
                  key: const Key('sheetCounter'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant));
            },
          ),
      ]);
}

/// Punto que late (el de "grabando").
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .3, end: 1.0).animate(pulse),
        child: Container(width: 12, height: 12, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}
