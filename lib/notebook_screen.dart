import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'common.dart';
import 'editor.dart';
import 'inserts.dart';
import 'model.dart';
import 'painters.dart';
import 'pdf_export.dart';
import 'pen_panel.dart';
import 'storage.dart';

/// Un cuaderno abierto: barra de arriba, panel de páginas y el editor.
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
  Timer? saveTimer, prefsTimer;
  bool dirty = false;

  // vista
  bool panel = false; // panel de páginas
  bool reading = false; // modo lectura
  bool fullscreen = false;
  bool onlyBookmarks = false;

  // búsqueda
  bool searching = false;
  final searchCtrl = TextEditingController();
  List<_Hit> hits = [];
  Timer? searchT;

  // miniaturas
  final thumbs = <String, PageData>{};
  final liveVersion = ValueNotifier(0);

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
    if (fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _flush(); // al salir de la app, guardar ya
  }

  // ================= guardado =================
  void _pageChanged() {
    dirty = true;
    liveVersion.value++;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _prefsChanged() {
    prefsTimer?.cancel();
    prefsTimer = Timer(const Duration(milliseconds: 500), () => store.savePrefs(widget.tools.toJson()));
  }

  Future<void> _flush() async {
    saveTimer?.cancel();
    saveTimer = null;
    final p = page;
    if (p != null && dirty) {
      dirty = false;
      nb.updated = DateTime.now().millisecondsSinceEpoch;
      await store.savePage(p);
      await store.saveIndex(widget.index);
    }
  }

  /// salir del cuaderno: guarda todo y vuelve a la biblioteca
  Future<void> leave([Object? result]) async {
    await _flush();
    prefsTimer?.cancel();
    await store.savePrefs(widget.tools.toJson());
    await store.saveIndex(widget.index);
    if (fullscreen) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _open(String id) async {
    if (page?.id == id) return;
    await _flush();
    if (page != null) thumbs[page!.id] = page!;
    final p = await store.loadPage(id);
    nb.last = id;
    unawaited(store.saveIndex(widget.index));
    if (mounted) setState(() => page = p);
  }

  // ================= páginas =================
  int get curIndex => nb.pages.indexWhere((p) => p.id == page?.id);

  Future<void> _addPage({int? at}) async {
    final p = PageData(newId('p'), bg: page?.bg ?? 'lined', paper: page?.paper ?? '#fffefb');
    await store.savePage(p);
    final i = at ?? nb.pages.length;
    setState(() => nb.pages.insert(i, PageRef(p.id, todayTitle())));
    thumbs[p.id] = p;
    nb.updated = DateTime.now().millisecondsSinceEpoch;
    await store.saveIndex(widget.index);
    await _open(p.id);
  }

  Future<void> _renamePage(PageRef p) async {
    final n = (await askText(context, 'Título de la página', initial: p.title))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => p.title = n);
    await store.saveIndex(widget.index);
  }

  Future<void> _duplicatePage(PageRef ref) async {
    await _flush();
    final src = ref.id == page?.id ? page! : await store.loadPage(ref.id);
    final dup = PageData.fromJson({...src.toJson(), 'id': newId('p')});
    await store.savePage(dup);
    thumbs[dup.id] = dup;
    setState(() => nb.pages.insert(nb.pages.indexOf(ref) + 1, PageRef(dup.id, '${ref.title} (copia)')));
    await store.saveIndex(widget.index);
  }

  Future<void> _movePage(PageRef ref, int delta) async {
    final i = nb.pages.indexOf(ref), j = i + delta;
    if (j < 0 || j >= nb.pages.length) return;
    setState(() {
      nb.pages.removeAt(i);
      nb.pages.insert(j, ref);
    });
    await store.saveIndex(widget.index);
  }

  Future<void> _deletePage(PageRef p) async {
    if (!await confirmDelete(context, 'Borrar "${p.title}"', 'Se borra la página con todo lo que tiene.')) return;
    await store.deletePage(p.id);
    final i = nb.pages.indexOf(p);
    setState(() => nb.pages.remove(p));
    thumbs.remove(p.id);
    await store.saveIndex(widget.index);
    if (p.id == page?.id) {
      saveTimer?.cancel();
      dirty = false;
      setState(() => page = null);
      if (nb.pages.isNotEmpty) {
        await _open(nb.pages[(i).clamp(0, nb.pages.length - 1)].id);
      } else {
        await _addPage();
      }
    }
  }

  Future<void> _toggleBookmark(PageRef p) async {
    setState(() => p.bookmark = !p.bookmark);
    HapticFeedback.selectionClick();
    await store.saveIndex(widget.index);
  }

  Future<PageData> _thumb(String id) async {
    if (id == page?.id) return page!;
    return thumbs[id] ??= await store.loadPage(id);
  }

  // ================= insertar (+) =================
  Future<void> _insertMenu(Offset at) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 200, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'pdf', child: MenuRow(Symbols.picture_as_pdf, 'PDF')),
        PopupMenuItem(value: 'voice', child: MenuRow(Symbols.mic, 'Grabación de voz')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'image', child: MenuRow(Symbols.image, 'Imagen')),
        PopupMenuItem(value: 'camera', child: MenuRow(Symbols.photo_camera, 'Cámara')),
        PopupMenuItem(value: 'audio', child: MenuRow(Symbols.music_note, 'Archivo de audio')),
        PopupMenuItem(value: 'sticky', child: MenuRow(Symbols.sticky_note_2, 'Nota adhesiva')),
        PopupMenuItem(value: 'page', child: MenuRow(Symbols.note_add, 'Página nueva')),
      ],
    );
    if (v == null || !mounted) return;
    await runInsert(v);
  }

  /// también lo usan los tests
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
          if (!mounted) return;
          final progress = ValueNotifier(0);
          unawaited(showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Importando PDF'),
              content: ValueListenableBuilder(
                valueListenable: progress,
                builder: (_, n, __) => Column(mainAxisSize: MainAxisSize.min, children: [
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
          final at = curIndex + 1;
          setState(() {
            for (var i = 0; i < pages.length; i++) {
              nb.pages.insert(at + i, PageRef(pages[i].$1.id, pages[i].$2));
              thumbs[pages[i].$1.id] = pages[i].$1;
            }
          });
          nb.updated = DateTime.now().millisecondsSinceEpoch;
          await store.saveIndex(widget.index);
          await _open(pages.first.$1.id);
          if (mounted) snack(context, '${pages.length} ${pages.length == 1 ? 'hoja importada' : 'hojas importadas'}');
      }
    } catch (e) {
      if (mounted) snack(context, 'No se pudo insertar: $e');
    }
  }

  // ================= menú ⋮ =================
  Future<void> _moreMenu(Offset at) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 260, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(value: 'search', child: MenuRow(Symbols.search, 'Buscar')),
        const PopupMenuItem(value: 'style', child: MenuRow(Symbols.palette, 'Estilo del cuaderno')),
        const PopupMenuItem(value: 'page', child: MenuRow(Symbols.tune, 'Configuración de página')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'saveas', child: MenuRow(Symbols.save_as, 'Guardar como')),
        const PopupMenuDivider(),
        _IconRow([
          (nb.favorite ? Symbols.star : Symbols.star, nb.favorite ? 'Quitar de favoritos' : 'Favorito', 'fav', nb.favorite),
          (nb.pin != null ? Symbols.lock : Symbols.lock_open, nb.pin != null ? 'Quitar bloqueo' : 'Bloquear con PIN', 'lock', nb.pin != null),
          (Symbols.share, 'Compartir', 'share', false),
          (Symbols.print, 'Imprimir', 'print', false),
          (Symbols.delete, 'Borrar cuaderno', 'delete', false),
        ]),
      ],
    );
    if (v == null || !mounted) return;
    await runMore(v);
  }

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
        await store.saveIndex(widget.index);
        if (mounted) snack(context, nb.favorite ? 'Agregado a favoritos' : 'Quitado de favoritos');
      case 'lock':
        await _toggleLock();
      case 'share':
        await _flush();
        if (!mounted) return;
        final bytes = await buildPdfWithProgress(context, store, nb);
        if (bytes == null) return;
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/pdf', name: '${nb.name}.pdf')],
          fileNameOverrides: ['${nb.name}.pdf'],
          title: nb.name,
        ));
      case 'print':
        await _flush();
        await Printing.layoutPdf(name: nb.name, onLayout: (_) => buildNotebookPdf(store, nb));
      case 'delete':
        if (!await confirmDelete(context, 'Borrar "${nb.name}"', 'Se borran sus ${nb.pages.length} páginas. No se puede deshacer.')) return;
        saveTimer?.cancel();
        dirty = false;
        for (final p in nb.pages) {
          await store.deletePage(p.id);
        }
        widget.index.notebooks.remove(nb);
        await store.saveIndex(widget.index);
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
      await store.saveIndex(widget.index);
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
    await store.saveIndex(widget.index);
    if (mounted) snack(context, 'Cuaderno bloqueado: se pide el PIN al abrirlo');
  }

  Future<void> _saveAs() async {
    final cs = Theme.of(context).colorScheme;
    Widget tile(IconData i, String t, String sub, String v) => ListTile(
          leading: Icon(i, weight: 300, color: cs.onSurfaceVariant),
          title: Text(t),
          subtitle: Text(sub),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.pop(context, v),
        );
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Text('Guardar como', style: Theme.of(ctx).textTheme.titleLarge)),
            tile(Symbols.picture_as_pdf, 'PDF del cuaderno', 'Todas las páginas', 'nb'),
            tile(Symbols.description, 'PDF de esta página', page == null ? '' : nb.pages[curIndex].title, 'page'),
            tile(Symbols.image, 'Imagen (PNG)', 'La hoja que estás viendo', 'png'),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    await _flush();
    if (!mounted) return;
    switch (v) {
      case 'nb':
        await exportPdfFlow(context, store, nb);
      case 'page':
        await exportPdfFlow(context, store, nb, only: [page!.id], name: '${nb.name} - ${nb.pages[curIndex].title}');
      case 'png':
        final sheet = editorKey.currentState?.visibleSheet ?? 0;
        final images = <String, dynamic>{};
        for (final it in page!.items.values) {
          if (it.type == 'image' && it.file != null) images[it.file!] = await decodeImage(await store.media(it.file!).readAsBytes());
        }
        final png = await renderSheetPng(page!, sheet, images: images.cast());
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Guardar imagen',
          fileName: '${nb.name} - ${nb.pages[curIndex].title} - hoja ${sheet + 1}.png'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-'),
          bytes: png,
          mimeType: 'image/png',
        );
        if (uri != null && mounted) snack(context, 'Imagen guardada');
    }
  }

  /// Estilo (todo el cuaderno) o configuración de página (solo esta)
  Future<void> _styleDialog({required bool all}) async {
    final p = page;
    if (p == null) return;
    var bg = p.bg, paper = p.paper;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final cs = Theme.of(ctx).colorScheme;
        Widget bgOpt(String v, IconData i, String label) => ChoiceChip(
              avatar: Icon(i, size: 18, weight: 300),
              label: Text(label),
              selected: bg == v,
              onSelected: (_) => set(() => bg = v),
            );
        Widget paperOpt(String c, String label) => Tooltip(
              message: label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => set(() => paper = c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: parseColor(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: paper == c ? cs.primary : cs.outlineVariant, width: paper == c ? 2.5 : 1),
                  ),
                ),
              ),
            );
        return AlertDialog(
          title: Text(all ? 'Estilo del cuaderno' : 'Configuración de página'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(all ? 'Se aplica a todas las páginas' : 'Solo a esta página', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text('Fondo', style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                bgOpt('lined', Symbols.format_align_justify, 'Rayado'),
                bgOpt('grid', Symbols.grid_4x4, 'Cuadriculado'),
                bgOpt('dots', Symbols.grid_goldenratio, 'Puntos'),
                bgOpt('blank', Symbols.crop_portrait, 'Liso'),
              ]),
              const SizedBox(height: 18),
              Text('Color del papel', style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, children: [
                paperOpt('#fffefb', 'Marfil'),
                paperOpt('#ffffff', 'Blanco'),
                paperOpt('#fbf3e0', 'Crema'),
                paperOpt('#f0efeb', 'Gris'),
                paperOpt('#eaf3fb', 'Celeste'),
                paperOpt('#eef6ec', 'Verde'),
              ]),
              if (!all) ...[
                const SizedBox(height: 18),
                Text('Hojas en esta página: ${sheetCount(p.h)}', style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      p.h = heightFor(sheetCount(p.h) + 1);
                      set(() {});
                    },
                    icon: const Icon(Symbols.add, size: 18),
                    label: const Text('Agregar hoja'),
                  ),
                  OutlinedButton.icon(
                    onPressed: sheetCount(p.h) > 1 && _lastSheetEmpty(p)
                        ? () {
                            p.h = heightFor(sheetCount(p.h) - 1);
                            set(() {});
                          }
                        : null,
                    icon: const Icon(Symbols.remove, size: 18),
                    label: const Text('Quitar la última (vacía)'),
                  ),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(key: const Key('styleOk'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
          ],
        );
      }),
    );
    if (r != true || !mounted) {
      editorKey.currentState?.refresh();
      _pageChanged();
      return;
    }
    p.bg = bg;
    p.paper = paper;
    _pageChanged();
    editorKey.currentState?.refresh();
    if (all) {
      await _flush();
      for (final ref in nb.pages) {
        if (ref.id == p.id) continue;
        final other = await store.loadPage(ref.id);
        other.bg = bg;
        other.paper = paper;
        await store.savePage(other);
        thumbs[ref.id] = other;
      }
      if (mounted) setState(() {});
    }
  }

  bool _lastSheetEmpty(PageData p) {
    final top = (sheetCount(p.h) - 1) * kSheetStep;
    return !p.strokes.values.any((s) => s.bounds.bottom > top) &&
        !p.texts.values.any((t) => t.y + kLine > top) &&
        !p.items.values.any((i) => i.y + i.h > top);
  }

  // ================= búsqueda =================
  void _search(String q) {
    searchT?.cancel();
    searchT = Timer(const Duration(milliseconds: 220), () async {
      q = q.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => hits = []);
        return;
      }
      final out = <_Hit>[];
      for (final ref in nb.pages) {
        final p = await _thumb(ref.id);
        for (final t in p.texts.values) {
          final i = t.text.toLowerCase().indexOf(q);
          if (i >= 0) out.add(_Hit(ref, t.id, _snippet(t.text, i, q.length)));
        }
        for (final it in p.items.values) {
          final i = it.text.toLowerCase().indexOf(q);
          if (it.type == 'sticky' && i >= 0) out.add(_Hit(ref, it.id, _snippet(it.text, i, q.length)));
        }
        if (ref.title.toLowerCase().contains(q)) out.add(_Hit(ref, null, 'Título: ${ref.title}'));
      }
      if (mounted) setState(() => hits = out);
    });
  }

  String _snippet(String s, int i, int n) {
    final a = (i - 30).clamp(0, s.length), b = (i + n + 50).clamp(0, s.length);
    return '${a > 0 ? '…' : ''}${s.substring(a, b).replaceAll('\n', ' ')}${b < s.length ? '…' : ''}';
  }

  Future<void> _goHit(_Hit h) async {
    await _open(h.page.id);
    setState(() => searching = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (h.id != null) editorKey.currentState?.reveal(h.id!);
    });
  }

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
                    child: panel && !fullscreen ? _pagesPanel(cs) : const SizedBox(width: 0),
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
            if (searching && !fullscreen) Positioned(top: 64, right: 12, width: 420, child: _searchResults(cs)),
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
        Expanded(
          child: searching
              ? TextField(
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
                )
              : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(nb.name,
                          key: const Key('nbTitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: cs.onSurface)),
                    ),
                    if (nb.favorite) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Symbols.star, size: 18, fill: 1, color: cs.primary)),
                    if (nb.pin != null) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Symbols.lock, size: 16, weight: 400, color: cs.onSurfaceVariant)),
                  ]),
                  if (cur != null)
                    Text('${cur.title} · ${curIndex + 1} de ${nb.pages.length}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
        ),
        if (searching)
          act(Symbols.close, 'Cerrar búsqueda', () => setState(() {
                searching = false;
                searchCtrl.clear();
                hits = [];
              }))
        else ...[
          act(Symbols.menu_book, reading ? 'Salir del modo lectura' : 'Modo lectura', () => setState(() => reading = !reading), on: reading, key: const Key('reading')),
          Builder(
            builder: (c) => act(Symbols.add, 'Insertar', () {
              final b = c.findRenderObject() as RenderBox;
              _insertMenu(b.localToGlobal(b.size.bottomRight(Offset.zero)));
            }, key: const Key('insert')),
          ),
          act(Symbols.view_sidebar, 'Páginas', () => setState(() => panel = !panel), on: panel, key: const Key('pagesBtn')),
          act(Symbols.open_in_full, 'Pantalla completa', _toggleFullscreen),
          Builder(
            builder: (c) => act(Symbols.more_vert, 'Más opciones', () {
              final b = c.findRenderObject() as RenderBox;
              _moreMenu(b.localToGlobal(b.size.bottomRight(Offset.zero)));
            }, key: const Key('more')),
          ),
        ],
      ]),
    );
  }

  Widget _searchResults(ColorScheme cs) {
    final q = searchCtrl.text.trim();
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: q.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(18),
                child: Text('Buscá en los textos, notas adhesivas y títulos de páginas', style: TextStyle(color: cs.onSurfaceVariant)),
              )
            : hits.isEmpty
                ? Padding(padding: const EdgeInsets.all(18), child: Text('Sin resultados para "$q"', style: TextStyle(color: cs.onSurfaceVariant)))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(6),
                    children: [
                      for (final h in hits)
                        ListTile(
                          key: Key('hit-${h.id ?? h.page.id}'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(Symbols.description, weight: 300, color: cs.onSurfaceVariant),
                          title: Text(h.page.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _goHit(h),
                        ),
                    ],
                  ),
      ),
    );
  }

  // ================= panel de páginas (miniaturas) =================
  Widget _pagesPanel(ColorScheme cs) {
    final list = onlyBookmarks ? nb.pages.where((p) => p.bookmark).toList() : nb.pages;
    return Container(
      key: const Key('pagesPanel'),
      width: 300,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
          child: Row(children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${curIndex + 1}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
                TextSpan(text: ' / ${nb.pages.length}', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
              ]),
              key: const Key('pageCounter'),
            ),
            const Spacer(),
            IconButton(
              tooltip: onlyBookmarks ? 'Ver todas' : 'Solo marcadas',
              isSelected: onlyBookmarks,
              onPressed: () => setState(() => onlyBookmarks = !onlyBookmarks),
              icon: Icon(Symbols.bookmark, weight: 300, fill: onlyBookmarks ? 1 : 0, color: onlyBookmarks ? cs.primary : cs.onSurfaceVariant),
            ),
            IconButton(
              tooltip: 'Buscar',
              onPressed: () => setState(() => searching = true),
              icon: Icon(Symbols.search, weight: 300, color: cs.onSurfaceVariant),
            ),
            IconButton(
              key: const Key('addPage'),
              tooltip: 'Página nueva',
              onPressed: () => _addPage(at: curIndex + 1),
              icon: Icon(Symbols.note_add, weight: 300, color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('No hay páginas marcadas', style: TextStyle(color: cs.onSurfaceVariant)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: .62,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _pageThumb(list[i], cs),
                ),
        ),
      ]),
    );
  }

  Widget _pageThumb(PageRef ref, ColorScheme cs) {
    final cur = ref.id == page?.id;
    final n = nb.pages.indexOf(ref) + 1;
    return GestureDetector(
      key: Key('thumb-$n'),
      onTap: () => _open(ref.id),
      onLongPressStart: (d) async {
        HapticFeedback.mediumImpact();
        final g = d.globalPosition;
        final v = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(g.dx, g.dy, g.dx + 1, g.dy + 1),
          items: [
            const PopupMenuItem(value: 'rename', child: MenuRow(Symbols.edit, 'Renombrar')),
            const PopupMenuItem(value: 'dup', child: MenuRow(Symbols.content_copy, 'Duplicar')),
            if (n > 1) const PopupMenuItem(value: 'up', child: MenuRow(Symbols.arrow_upward, 'Mover antes')),
            if (n < nb.pages.length) const PopupMenuItem(value: 'down', child: MenuRow(Symbols.arrow_downward, 'Mover después')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: MenuRow(Symbols.delete, 'Borrar', danger: true)),
          ],
        );
        switch (v) {
          case 'rename':
            _renamePage(ref);
          case 'dup':
            _duplicatePage(ref);
          case 'up':
            _movePage(ref, -1);
          case 'down':
            _movePage(ref, 1);
          case 'delete':
            _deletePage(ref);
        }
      },
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cur ? cs.primary : cs.outlineVariant.withValues(alpha: .6), width: cur ? 2.5 : 1),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cur ? 8 : 9),
              child: Stack(children: [
                Positioned.fill(
                  child: FutureBuilder<PageData>(
                    future: _thumb(ref.id),
                    builder: (_, snap) => snap.data == null
                        ? Container(color: const Color(0xFFFFFEFB))
                        : ValueListenableBuilder(
                            valueListenable: liveVersion,
                            builder: (_, v, __) => CustomPaint(painter: SheetThumbPainter(snap.data!, cur ? v : 0)),
                          ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: ref.bookmark ? 'Quitar marcador' : 'Marcar',
                    onPressed: () => _toggleBookmark(ref),
                    icon: Icon(Symbols.bookmark, size: 20, fill: ref.bookmark ? 1 : 0, weight: 400,
                        color: ref.bookmark ? cs.primary : const Color(0x55000000)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('$n · ${ref.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: cur ? cs.primary : cs.onSurfaceVariant, fontWeight: cur ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }
}

class _Hit {
  final PageRef page;
  final String? id;
  final String snippet;
  _Hit(this.page, this.id, this.snippet);
}

/// Fila de íconos al pie del menú ⋮ (favorito, bloquear, compartir, imprimir, borrar)
class _IconRow extends PopupMenuEntry<String> {
  final List<(IconData, String, String, bool)> items;
  const _IconRow(this.items);
  @override
  double get height => 56;
  @override
  bool represents(String? value) => false;
  @override
  State<_IconRow> createState() => _IconRowState();
}

class _IconRowState extends State<_IconRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final (icon, tip, value, on) in widget.items)
          IconButton(
            key: Key('more-$value'),
            tooltip: tip,
            onPressed: () => Navigator.pop(context, value),
            icon: Icon(icon, weight: 300, fill: on ? 1 : 0, color: value == 'delete' ? cs.error : (on ? cs.primary : cs.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
