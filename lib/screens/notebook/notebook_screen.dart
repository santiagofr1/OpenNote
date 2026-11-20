import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export.dart';
import '../../data/media_import.dart';
import '../../data/storage.dart';
import '../../domain/domain.dart';
import '../../editor/page_editor.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pdf_progress.dart';
import '../../widgets/record_voice_dialog.dart';
import 'menus.dart';
import 'pages_panel.dart';
import 'search.dart';
import 'style_dialog.dart';

/// Un cuaderno abierto: barra de arriba, panel de páginas y el editor.
/// Guarda la página un rato después de cada cambio, al salir y cuando la app pasa a segundo plano.
class NotebookScreen extends StatefulWidget {
  final Storage store;
  final NotesIndex index;
  final Notebook nb;
  final ToolState tools;
  const NotebookScreen({super.key, required this.store, required this.index, required this.nb, required this.tools});
  @override
  State<NotebookScreen> createState() => NotebookScreenState();
}

class NotebookScreenState extends State<NotebookScreen> with WidgetsBindingObserver {
  Storage get store => widget.store;
  Notebook get nb => widget.nb;
  final editorKey = GlobalKey<PageEditorState>();
  PageData? page;
  Timer? _saveTimer, _prefsTimer;
  bool _dirty = false;

  // vista
  bool panel = false; // panel de páginas
  bool reading = false; // modo lectura
  bool fullscreen = false;
  bool onlyBookmarks = false;

  // búsqueda
  bool searching = false;
  final searchCtrl = TextEditingController();
  List<SearchHit> hits = [];
  Timer? _searchTimer;

  // miniaturas: páginas ya cargadas (la abierta se toma de [page])
  final _thumbs = <String, PageData>{};
  final _liveVersion = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final first = nb.pages.any((p) => p.id == nb.last) ? nb.last : (nb.pages.isEmpty ? null : nb.pages.first.id);
    if (first != null) {
      _open(first);
    } else {
      _addPage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchCtrl.dispose();
    _searchTimer?.cancel();
    if (fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush(); // al salir de la app, guardar ya
  }

  // ================= guardado =================
  void _pageChanged() {
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
    final p = page;
    if (p != null && _dirty) {
      _dirty = false;
      nb.touch();
      await store.savePage(p);
      await store.saveIndex(widget.index);
    }
  }

  /// Lo pendiente de la página abierta ya no se guarda (se está borrando).
  void _discardPending() {
    _saveTimer?.cancel();
    _dirty = false;
  }

  Future<void> _saveIndex() => store.saveIndex(widget.index);

  /// salir del cuaderno: guarda todo y vuelve a la biblioteca
  Future<void> leave([Object? result]) async {
    await _flush();
    _prefsTimer?.cancel();
    await store.savePrefs(widget.tools.toJson());
    await _saveIndex();
    if (fullscreen) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _open(String id) async {
    if (page?.id == id) return;
    await _flush();
    if (page != null) _thumbs[page!.id] = page!;
    final p = await store.loadPage(id);
    nb.last = id;
    unawaited(_saveIndex());
    if (mounted) setState(() => page = p);
  }

  // ================= páginas =================
  int get curIndex => nb.pages.indexWhere((p) => p.id == page?.id);

  Future<void> _addPage({int? at}) async {
    final p = PageData(newId('p'), bg: page?.bg ?? 'lined', paper: page?.paper ?? '#fffefb');
    await store.savePage(p);
    setState(() => nb.pages.insert(at ?? nb.pages.length, PageRef(p.id, todayTitle())));
    _thumbs[p.id] = p;
    nb.touch();
    await _saveIndex();
    await _open(p.id);
  }

  Future<void> _renamePage(PageRef p) async {
    final n = (await askText(context, 'Título de la página', initial: p.title))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => p.title = n);
    await _saveIndex();
  }

  Future<void> _duplicatePage(PageRef ref) async {
    await _flush();
    final src = ref.id == page?.id ? page! : await store.loadPage(ref.id);
    final dup = src.duplicate();
    await store.savePage(dup);
    _thumbs[dup.id] = dup;
    setState(() => nb.pages.insert(nb.pages.indexOf(ref) + 1, PageRef(dup.id, '${ref.title} (copia)')));
    await _saveIndex();
  }

  Future<void> _movePage(PageRef ref, int delta) async {
    final i = nb.pages.indexOf(ref), j = i + delta;
    if (j < 0 || j >= nb.pages.length) return;
    setState(() {
      nb.pages.removeAt(i);
      nb.pages.insert(j, ref);
    });
    await _saveIndex();
  }

  Future<void> _deletePage(PageRef p) async {
    if (!await confirmDelete(context, 'Borrar "${p.title}"', 'Se borra la página con todo lo que tiene.')) return;
    await store.deletePage(p.id);
    final i = nb.pages.indexOf(p);
    setState(() => nb.pages.remove(p));
    _thumbs.remove(p.id);
    await _saveIndex();
    if (p.id == page?.id) {
      _discardPending();
      setState(() => page = null);
      if (nb.pages.isNotEmpty) {
        await _open(nb.pages[i.clamp(0, nb.pages.length - 1)].id);
      } else {
        await _addPage();
      }
    }
  }

  Future<void> _toggleBookmark(PageRef p) async {
    setState(() => p.bookmark = !p.bookmark);
    HapticFeedback.selectionClick();
    await _saveIndex();
  }

  void _pageAction(PageRef ref, PageAction a) {
    switch (a) {
      case PageAction.rename:
        _renamePage(ref);
      case PageAction.duplicate:
        _duplicatePage(ref);
      case PageAction.moveUp:
        _movePage(ref, -1);
      case PageAction.moveDown:
        _movePage(ref, 1);
      case PageAction.delete:
        _deletePage(ref);
    }
  }

  Future<PageData> _thumb(String id) async {
    if (id == page?.id) return page!;
    return _thumbs[id] ??= await store.loadPage(id);
  }

  /// Agrega páginas ya guardadas después de la actual y abre la primera.
  Future<void> _insertPages(List<(PageData, String)> pages) async {
    final at = curIndex + 1;
    setState(() {
      for (var i = 0; i < pages.length; i++) {
        nb.pages.insert(at + i, PageRef(pages[i].$1.id, pages[i].$2));
        _thumbs[pages[i].$1.id] = pages[i].$1;
      }
    });
    nb.touch();
    await _saveIndex();
    await _open(pages.first.$1.id);
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
          final it = await makeAudioFileItem(store);
          if (it != null) ed?.insertItem(it);
        case 'voice':
          final it = await recordVoice(context, store);
          if (it != null) ed?.insertItem(it);
        case 'page':
          await _addPage(at: curIndex + 1);
        case 'pdf':
          await _importPdf();
      }
    } catch (e) {
      if (mounted) snack(context, 'No se pudo insertar: $e');
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
    final pages = await importPdf(store, onPage: (n) => progress.value = n);
    if (mounted) Navigator.of(context).pop();
    if (pages.isEmpty) return;
    await _insertPages(pages);
    if (mounted) snack(context, '${pages.length} ${pages.length == 1 ? 'hoja importada' : 'hojas importadas'}');
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
        await _styleDialog(all: true);
      case 'page':
        await _styleDialog(all: false);
      case 'saveas':
        await _saveAs();
      case 'fav':
        setState(() => nb.favorite = !nb.favorite);
        await _saveIndex();
        if (mounted) snack(context, nb.favorite ? 'Agregado a favoritos' : 'Quitado de favoritos');
      case 'lock':
        await _toggleLock();
      case 'share':
        await _flush();
        if (!mounted) return;
        final bytes = await buildPdfWithProgress(context, store, nb);
        if (bytes == null) return;
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${nb.name}.pdf')],
          fileNameOverrides: ['${nb.name}.pdf'],
          title: nb.name,
        ));
      case 'print':
        await _flush();
        await Printing.layoutPdf(name: nb.name, onLayout: (_) => buildNotebookPdf(store, nb));
      case 'delete':
        if (!await confirmDeleteNotebook(context, nb)) return;
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

  Future<void> _saveAs() async {
    final p = page;
    final title = p == null ? '' : nb.pages[curIndex].title;
    final v = await showSaveAsSheet(context, pageTitle: title);
    if (v == null || !mounted) return;
    await _flush();
    if (!mounted || p == null) return;
    switch (v) {
      case 'nb':
        await exportPdfFlow(context, store, nb);
      case 'page':
        await exportPdfFlow(context, store, nb, only: [p.id], name: '${nb.name} - $title');
      case 'png':
        final sheet = editorKey.currentState?.visibleSheet ?? 0;
        final ok = await saveSheetPng(store, p, sheet, '${nb.name} - $title - hoja ${sheet + 1}');
        if (ok && mounted) snack(context, 'Imagen guardada');
    }
  }

  /// Estilo (todo el cuaderno) o configuración de página (solo esta)
  Future<void> _styleDialog({required bool all}) async {
    final p = page;
    if (p == null) return;
    final r = await showStyleDialog(context, p, all: all);
    if (r != null && mounted) {
      p.bg = r.bg;
      p.paper = r.paper;
    }
    // aunque se cancele: las hojas agregadas o quitadas ya quedaron en la página
    _pageChanged();
    editorKey.currentState?.refresh();
    if (r == null || !mounted || !all) return;
    await _flush();
    for (final ref in nb.pages) {
      if (ref.id == p.id) continue;
      final other = await store.loadPage(ref.id);
      other.bg = r.bg;
      other.paper = r.paper;
      await store.savePage(other);
      _thumbs[ref.id] = other;
    }
    if (mounted) setState(() {});
  }

  // ================= búsqueda =================
  void _search(String q) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 220), () async {
      final out = await searchNotebook(nb, _thumb, q);
      if (mounted) setState(() => hits = out);
    });
  }

  Future<void> _goHit(SearchHit h) async {
    await _open(h.page.id);
    setState(() => searching = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (h.id != null) editorKey.currentState?.reveal(h.id!);
    });
  }

  void _closeSearch() => setState(() {
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
              Expanded(
                child: Row(children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutQuart,
                    child: panel && !fullscreen ? _pagesPanel() : const SizedBox(width: 0),
                  ),
                  Expanded(
                    child: page == null
                        ? const Center(child: CircularProgressIndicator())
                        : PageEditor(
                            key: editorKey,
                            page: page!,
                            tools: widget.tools,
                            store: store,
                            readOnly: reading,
                            onChanged: _pageChanged,
                            onPrefsChanged: _prefsChanged,
                          ),
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

  Widget _pagesPanel() => PagesPanel(
        nb: nb,
        currentId: page?.id,
        onlyBookmarks: onlyBookmarks,
        thumb: _thumb,
        liveVersion: _liveVersion,
        onToggleBookmarksFilter: () => setState(() => onlyBookmarks = !onlyBookmarks),
        onSearch: () => setState(() => searching = true),
        onAddPage: () => _addPage(at: curIndex + 1),
        onOpen: (ref) => _open(ref.id),
        onToggleBookmark: _toggleBookmark,
        onAction: _pageAction,
      );

  Widget _topBar(ColorScheme cs) {
    final cur = curIndex >= 0 ? nb.pages[curIndex] : null;
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
        Expanded(child: searching ? _searchField() : _title(cs, cur)),
        if (searching)
          act(Symbols.close, 'Cerrar búsqueda', _closeSearch)
        else ...[
          act(Symbols.menu_book, reading ? 'Salir del modo lectura' : 'Modo lectura', () => setState(() => reading = !reading),
              on: reading, key: const Key('reading')),
          menuBtn(Symbols.add, 'Insertar', const Key('insert'), (at) async {
            final v = await showInsertMenu(context, at);
            if (v != null && mounted) await runInsert(v);
          }),
          act(Symbols.view_sidebar, 'Páginas', () => setState(() => panel = !panel), on: panel, key: const Key('pagesBtn')),
          act(Symbols.open_in_full, 'Pantalla completa', _toggleFullscreen),
          menuBtn(Symbols.more_vert, 'Más opciones', const Key('more'), (at) async {
            final v = await showMoreMenu(context, at, nb);
            if (v != null && mounted) await runMore(v);
          }),
        ],
      ]),
    );
  }

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

  /// Nombre del cuaderno (siempre arriba a la izquierda) y la página actual.
  Widget _title(ColorScheme cs, PageRef? cur) =>
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
        if (cur != null)
          Text('${cur.title} · ${curIndex + 1} de ${nb.pages.length}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]);
}
