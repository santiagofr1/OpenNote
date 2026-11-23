import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../widgets/sheet_thumb.dart';
import 'thumb_cache.dart';

enum SheetAction { rename, addAfter, duplicate, moveUp, moveDown, delete }

/// Panel de hojas a la izquierda: contador, filtros y una miniatura por hoja en dos columnas.
/// Tocar una miniatura lleva a esa hoja; mantenerla apretada abre el menú de la hoja; el asa de abajo a la izquierda
/// (`thumbHandle-N`) se arrastra para mover la hoja: al soltarla sobre otra miniatura queda en esa posición.
/// (El long-press de la miniatura sigue abriendo el menú: por eso el arrastre va en un asa aparte, con dedo o lápiz.)
class PagesPanel extends StatefulWidget {
  final NotebookDoc doc;
  final SheetThumbCache thumbs; // miniaturas de las hojas que no están cargadas
  final ValueListenable<int> current; // hoja que se está viendo
  final ValueListenable<int> structure; // cambia al agregar, mover o borrar hojas (o cambiar su estilo)
  final ValueListenable<int> liveVersion; // cambia al editar la hoja abierta
  final bool onlyBookmarks;
  final VoidCallback onToggleBookmarksFilter, onSearch, onAdd;
  final ValueChanged<int> onOpen, onToggleBookmark;
  final void Function(int sheet, SheetAction action) onAction;
  final void Function(int from, int to) onMove; // arrastrar una miniatura: lleva la hoja [from] a la posición [to]
  final void Function(Rect anchor) onSections; // el botón de secciones: despliega la lista debajo de [anchor] (global)

  const PagesPanel({
    super.key,
    required this.doc,
    required this.thumbs,
    required this.current,
    required this.structure,
    required this.liveVersion,
    required this.onlyBookmarks,
    required this.onToggleBookmarksFilter,
    required this.onSearch,
    required this.onAdd,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onAction,
    required this.onMove,
    required this.onSections,
  });

  @override
  State<PagesPanel> createState() => _PagesPanelState();
}

class _PagesPanelState extends State<PagesPanel> {
  final _scroll = ScrollController();
  final _gridKey = GlobalKey();
  int? _dragFrom; // hoja que se está arrastrando
  Offset? _dragAt; // dedo / lápiz (global)
  Timer? _autoScroll;

  NotebookDoc get doc => widget.doc;
  SheetThumbCache get thumbs => widget.thumbs;
  ValueListenable<int> get current => widget.current;
  ValueListenable<int> get structure => widget.structure;
  ValueListenable<int> get liveVersion => widget.liveVersion;
  bool get onlyBookmarks => widget.onlyBookmarks;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _dragStart(int k) {
    setState(() => _dragFrom = k);
    HapticFeedback.mediumImpact();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _tickScroll());
  }

  void _dragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (mounted) setState(() => _dragFrom = null);
  }

  /// Arrastrando cerca del borde de arriba o de abajo de la grilla, esta scrollea sola.
  void _tickScroll() {
    final at = _dragAt, box = _gridKey.currentContext?.findRenderObject();
    if (at == null || box is! RenderBox || !_scroll.hasClients) return;
    final y = box.globalToLocal(at).dy, h = box.size.height;
    const edge = 56.0;
    final dy = y < edge ? -(edge - y) / 4 : (y > h - edge ? (y - (h - edge)) / 4 : 0.0);
    if (dy == 0) return;
    _scroll.jumpTo((_scroll.offset + dy).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final onAdd = widget.onAdd, onSearch = widget.onSearch, onToggleBookmarksFilter = widget.onToggleBookmarksFilter;
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('pagesPanel'),
      width: 300,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([current, structure]),
        builder: (context, _) {
          final n = doc.sheetCount, cur = current.value.clamp(0, n - 1);
          final list = [
            for (var k = 0; k < n; k++)
              if (!onlyBookmarks || doc.sheets[k].bookmark) k
          ];
          return Column(children: [
            _sectionsButton(context, cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 6),
              child: Row(children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${cur + 1}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    TextSpan(text: ' / $n', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                  ]),
                  key: const Key('pageCounter'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: onlyBookmarks ? 'Ver todas' : 'Solo marcadas',
                  isSelected: onlyBookmarks,
                  onPressed: onToggleBookmarksFilter,
                  icon: Icon(Symbols.bookmark,
                      weight: 300, fill: onlyBookmarks ? 1 : 0, color: onlyBookmarks ? cs.primary : cs.onSurfaceVariant),
                ),
                IconButton(
                  tooltip: 'Buscar',
                  onPressed: onSearch,
                  icon: Icon(Symbols.search, weight: 300, color: cs.onSurfaceVariant),
                ),
                IconButton(
                  key: const Key('addPage'),
                  tooltip: 'Hoja nueva después de la actual',
                  onPressed: onAdd,
                  icon: Icon(Symbols.note_add, weight: 300, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('No hay hojas marcadas', style: TextStyle(color: cs.onSurfaceVariant)))
                  : GridView.builder(
                      key: _gridKey,
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio: .62,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _thumb(context, list[i], cur, cs),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  /// La sección abierta con una flechita: al tocarla se despliega la lista de secciones (siempre visible, aunque haya una).
  Widget _sectionsButton(BuildContext context, ColorScheme cs) {
    final nb = doc.nb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Builder(
        builder: (c) => Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('sectionsButton'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final b = c.findRenderObject() as RenderBox;
              widget.onSections(b.localToGlobal(Offset.zero) & b.size);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Icon(Symbols.folder_open, size: 20, weight: 300, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nb.activeSection.name,
                      key: const Key('sectionName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface)),
                ),
                Icon(Symbols.keyboard_arrow_down, size: 22, weight: 300, color: cs.onSurfaceVariant),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, int k, int cur, ColorScheme cs) {
    return DragTarget<int>(
      key: Key('thumbDrop-${k + 1}'),
      onWillAcceptWithDetails: (d) => d.data != k,
      onAcceptWithDetails: (d) => widget.onMove(d.data, k),
      builder: (context, candidates, _) => Opacity(
        opacity: _dragFrom == k ? .35 : 1,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: candidates.isEmpty ? null : Border.all(color: cs.tertiary, width: 3),
          ),
          child: _thumbBody(context, k, cur, cs),
        ),
      ),
    );
  }

  Widget _handle(int k, ColorScheme cs) {
    final n = k + 1;
    return Draggable<int>(
      key: Key('thumbHandle-$n'),
      data: k,
      onDragStarted: () => _dragStart(k),
      onDragUpdate: (d) => _dragAt = d.globalPosition,
      onDragEnd: (_) => _dragEnd(),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        color: cs.primaryContainer,
        child: SizedBox(
          width: 84,
          height: 112,
          child: Center(child: Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer))),
        ),
      ),
      child: Tooltip(
        message: 'Arrastrar para mover',
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: cs.surface.withValues(alpha: .85), shape: BoxShape.circle),
          child: Icon(Symbols.drag_handle, size: 22, weight: 400, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _thumbBody(BuildContext context, int k, int cur, ColorScheme cs) {
    final onOpen = widget.onOpen, onToggleBookmark = widget.onToggleBookmark;
    final meta = doc.sheets[k], isCur = k == cur, n = k + 1;
    return GestureDetector(
      key: Key('thumb-$n'),
      onTap: () => onOpen(k),
      // El menú se abre al soltar, no al reconocer el long-press: abrir una ruta con el dedo apoyado
      // hace que el Navigator cancele el puntero, y en los tests (que sueltan por su cuenta) el
      // reconocedor quedaba trabado en "posible" y la próxima pulsación se perdía.
      onLongPress: () => HapticFeedback.mediumImpact(),
      onLongPressUp: () async {
        final v = await _sheetMenu(context, k);
        if (v != null) widget.onAction(k, v);
      },
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isCur ? cs.primary : cs.outlineVariant.withValues(alpha: .6), width: isCur ? 2.5 : 1),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isCur ? 8 : 9),
              child: Stack(children: [
                Positioned.fill(
                  child: _SheetThumb(
                    doc: doc,
                    meta: meta,
                    sheet: k,
                    cache: thumbs,
                    liveVersion: liveVersion,
                    // al editar solo se repinta la hoja abierta; con la estructura cambian todas
                    version: structure.value * 1000003,
                    isCur: isCur,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: meta.bookmark ? 'Quitar marcador' : 'Marcar',
                    onPressed: () => onToggleBookmark(k),
                    icon: Icon(Symbols.bookmark,
                        size: 20,
                        fill: meta.bookmark ? 1 : 0,
                        weight: 400,
                        color: meta.bookmark ? cs.primary : const Color(0x55000000)),
                  ),
                ),
                Positioned(left: 4, bottom: 4, child: _handle(k, cs)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(meta.title.isEmpty ? '$n' : '$n · ${meta.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                color: isCur ? cs.primary : cs.onSurfaceVariant,
                fontWeight: isCur ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }

  /// Menú de una hoja como hoja inferior: se ve entero en vertical y en horizontal (si no entra, scrollea).
  Future<SheetAction?> _sheetMenu(BuildContext context, int k) {
    final cs = Theme.of(context).colorScheme;
    Widget tile(SheetAction a, IconData i, String t, {bool danger = false}) => ListTile(
          key: Key('sheetAction-${a.name}'),
          leading: Icon(i, weight: 300, color: danger ? cs.error : cs.onSurfaceVariant),
          title: Text(t, style: TextStyle(color: danger ? cs.error : cs.onSurface)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.pop(context, a),
        );
    return showModalBottomSheet<SheetAction>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Hoja ${k + 1}${doc.sheets[k].title.isEmpty ? '' : ' · ${doc.sheets[k].title}'}',
                    style: Theme.of(ctx).textTheme.titleMedium)),
            tile(SheetAction.rename, Symbols.edit, 'Renombrar'),
            tile(SheetAction.addAfter, Symbols.note_add, 'Hoja nueva después'),
            tile(SheetAction.duplicate, Symbols.content_copy, 'Duplicar'),
            if (k > 0) tile(SheetAction.moveUp, Symbols.arrow_upward, 'Mover antes'),
            if (k < doc.sheetCount - 1) tile(SheetAction.moveDown, Symbols.arrow_downward, 'Mover después'),
            if (doc.sheetCount > 1) tile(SheetAction.delete, Symbols.delete, 'Borrar', danger: true),
          ]),
        ),
      ),
    );
  }
}

/// Miniatura de una hoja: si está cargada se dibuja del documento vivo; si no, se lee de disco (con caché) y mientras
/// tanto se ve el papel. Se redibuja sola cuando la hoja se carga o se descarga.
class _SheetThumb extends StatefulWidget {
  final NotebookDoc doc;
  final SheetMeta meta;
  final int sheet, version;
  final bool isCur;
  final SheetThumbCache cache;
  final ValueListenable<int> liveVersion;
  const _SheetThumb(
      {required this.doc,
      required this.meta,
      required this.sheet,
      required this.cache,
      required this.liveVersion,
      required this.version,
      required this.isCur});

  @override
  State<_SheetThumb> createState() => _SheetThumbState();
}

class _SheetThumbState extends State<_SheetThumb> {
  late NotebookDoc _paper; // solo el papel de esta hoja, para mientras se lee

  @override
  void initState() {
    super.initState();
    widget.doc.addLoadListener(_onLoad);
    _paper = NotebookDoc.single(widget.meta, SheetContent());
  }

  @override
  void didUpdateWidget(_SheetThumb old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) {
      old.doc.removeLoadListener(_onLoad);
      widget.doc.addLoadListener(_onLoad);
    }
    if (old.meta != widget.meta) _paper = NotebookDoc.single(widget.meta, SheetContent());
  }

  @override
  void dispose() {
    widget.doc.removeLoadListener(_onLoad);
    super.dispose();
  }

  void _onLoad(String id, bool loaded) {
    if (mounted && id == widget.meta.id) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = widget, m = w.meta;
    if (w.doc.isLoaded(m.id)) {
      return ValueListenableBuilder(
        valueListenable: w.liveVersion,
        builder: (_, v, _) =>
            SheetThumb(doc: w.doc, sheet: w.sheet, version: w.version + (w.isCur ? v : 0), store: w.cache.store),
      );
    }
    final nb = w.doc.nb;
    final cached = w.cache.peek(nb, m);
    if (cached != null) return SheetThumb(doc: cached, version: m.rev, store: w.cache.store);
    return FutureBuilder<NotebookDoc?>(
      key: ValueKey('${m.id}#${m.rev}'),
      future: w.cache.get(nb, m),
      builder: (_, snap) =>
          SheetThumb(doc: snap.data ?? _paper, version: snap.data == null ? -1 : m.rev, store: w.cache.store),
    );
  }
}
