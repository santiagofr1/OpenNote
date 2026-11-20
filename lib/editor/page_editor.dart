import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/storage.dart';
import '../domain/domain.dart';
import '../rendering/ink_layers.dart';
import '../rendering/paper.dart';
import '../rendering/text_layout.dart';
import '../widgets/dialogs.dart';
import 'context_menu.dart';
import 'dock_layout.dart';
import 'format_bar.dart';
import 'history.dart';
import 'ink.dart';
import 'items_layer.dart';
import 'live_layer.dart';
import 'pen_panel.dart';
import 'pull_to_add.dart';
import 'selection.dart';
import 'selection_menu.dart';
import 'text_blocks.dart';
import 'toolbar.dart';
import 'touch_gestures.dart';
import 'viewport.dart';
import 'zoom_indicator.dart';

/// Editor del cuaderno: la tira continua de hojas, con tinta, textos y elementos y su barra de herramientas.
///
/// Quién hace qué con cada puntero:
/// - lápiz (y mouse): dibuja, borra (botón del S Pen, punta goma o clic derecho) o selecciona;
/// - dedo: scrollea; dos dedos hacen zoom; uno quieto abre el menú de la hoja;
///   tirar hacia arriba al final agrega una hoja.
class PageEditor extends StatefulWidget {
  final NotebookDoc doc;
  final ToolState tools;
  final Storage store;
  final bool readOnly; // modo lectura: no se edita y no hay barra de herramientas
  final int initialSheet; // hoja a la que se va al abrir
  final ValueNotifier<int>? sheetNotifier; // hoja que se está viendo (la actualiza el editor al scrollear)
  final VoidCallback onChanged; // cambió el cuaderno (hay que guardarlo)
  final VoidCallback onPrefsChanged; // cambiaron las herramientas (prefs.json)
  const PageEditor({
    super.key,
    required this.doc,
    required this.tools,
    required this.store,
    this.readOnly = false,
    this.initialSheet = 0,
    this.sheetNotifier,
    required this.onChanged,
    required this.onPrefsChanged,
  });

  @override
  State<PageEditor> createState() => PageEditorState();
}

class PageEditorState extends State<PageEditor> with SingleTickerProviderStateMixin {
  NotebookDoc get doc => widget.doc;
  ToolState get ts => widget.tools;

  final scroll = ScrollController(), hscroll = ScrollController();
  final inkVersion = ValueNotifier(0); // repinta la capa de tinta fija
  final liveTick = ValueNotifier(0); // repinta la capa en vivo
  final history = History();
  final sel = Selection();
  late final texts = TextFields(onFocusChange: _rebuild, onLeftEmpty: _removeText, onEdited: _textEdited);
  late final pull = PullToAddSheet(vsync: this, onComplete: _addSheetFromPull);
  final touch = TouchTracker();
  late final stillPress = StillPressTimer(_onStillPress);
  SheetLayout layout = SheetLayout.initial;
  double get scale => layout.scale;

  // trazo o goma en curso: un solo puntero de lápiz/mouse a la vez
  int? pointer;
  Stroke? live;
  Offset? eraserAt;
  List<Stroke>? erased;

  bool _zoomPill = false;
  Timer? _zoomPillTimer;
  final _saveTimers = <String, Timer>{}; // textos y notas: se guarda al dejar de escribir
  final _viewportKey = GlobalKey(), _sheetKey = GlobalKey();

  /// Ids de los elementos seleccionados (lo usan los tests).
  Set<String> get selI => sel.items;

  @override
  void initState() {
    super.initState();
    texts.attach(doc);
    scroll.addListener(_scheduleVisibleSheet);
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToSheet(widget.initialSheet, animate: false));
  }

  @override
  void didUpdateWidget(PageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // otro cuaderno en el mismo editor: lo de la anterior (deshacer, selección, campos) no sirve acá
    if (oldWidget.doc != widget.doc) {
      texts.attach(doc);
      history.clear();
      sel.clear();
      pointer = null;
      live = null;
      erased = null;
      eraserAt = null;
      liveTick.value++;
    }
  }

  @override
  void dispose() {
    final pending = _saveTimers.values.any((t) => t.isActive);
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    if (pending) widget.onChanged(); // lo último que se escribió también se guarda
    texts.dispose();
    scroll.dispose();
    hscroll.dispose();
    pull.dispose();
    inkVersion.dispose();
    liveTick.dispose();
    _zoomPillTimer?.cancel();
    stillPress.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _changed() => widget.onChanged();

  void _saveSoon(String id, Duration delay) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] = Timer(delay, _changed);
  }

  Offset _toPage(Offset local) => local / scale;

  /// Agrega hojas si [y] quedó cerca del final del cuaderno.
  void _growIfNeeded(double y) {
    if (y > doc.h - 250) setState(() => doc.growFor(y));
  }

  // ---------------- lápiz: dibujar, borrar, seleccionar ----------------
  void _down(PointerDownEvent e) {
    if (widget.readOnly || pointer != null) return;
    final action = penActionFor(e, ts.tool);
    if (action == null) return;
    pointer = e.pointer;
    final p = _toPage(e.localPosition);
    switch (action) {
      case PenAction.erase:
        _startErase(p);
      case PenAction.select:
        _selDown(p);
      case PenAction.draw:
        final pr = ts.current;
        live = Stroke(newId('s'), ts.tool == Tool.hl ? 'hl' : pr.tip, pr.color, pr.width, [], pr.opacity);
        appendInkPoint(live!, p, pressureOf(e));
        liveTick.value++;
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != pointer) return;
    final p = _toPage(e.localPosition);
    if (sel.moving) {
      _selDrag(p);
      return;
    }
    if (sel.bandA != null) {
      sel.bandB = p;
      liveTick.value++;
      return;
    }
    final s = live;
    if (s != null && wantsEraser(e)) {
      // apretó el botón a mitad del trazo: lo que venía queda, y sigue borrando
      live = null;
      _commitStroke(s);
      _startErase(p);
      return;
    }
    if (erased != null) {
      _eraseAt(p);
      eraserAt = p;
    } else if (s != null) {
      appendInkPoint(s, p, pressureOf(e));
    }
    liveTick.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != pointer) return;
    pointer = null;
    if (sel.moving) {
      _selDrop();
      return;
    }
    final band = sel.band;
    if (band != null) {
      sel.selectIn(doc, band, capture: sel.capture);
      sel.bandA = sel.bandB = null;
      setState(() {});
      liveTick.value++;
      return;
    }
    if (erased != null) {
      if (erased!.isNotEmpty) _pushUndo(EditAction(removed: erased!));
      erased = null;
      eraserAt = null;
      liveTick.value++;
      return;
    }
    final s = live;
    live = null;
    liveTick.value++;
    // cancelado por el sistema (ej. lo tomó como palma) apenas empezó: se descarta
    if (s == null || (e is PointerCancelEvent && s.n < 3)) return;
    _commitStroke(s);
  }

  /// El trazo terminado pasa a la página (suavizado), con su deshacer.
  void _commitStroke(Stroke s) {
    if (s.n < 2) return;
    s.smooth();
    s.z = doc.nextZ(); // arriba de todo
    doc.strokes[s.id] = s;
    inkVersion.value++;
    _pushUndo(EditAction(added: [s]));
    _growIfNeeded(s.bounds.bottom);
    _changed();
  }

  void _startErase(Offset p) {
    erased = [];
    _eraseAt(p);
    eraserAt = p;
    liveTick.value++;
  }

  void _eraseAt(Offset pt) {
    final hits = strokesHit(doc, pt, ts.eraserRadius);
    if (hits.isEmpty) return;
    for (final s in hits) {
      doc.strokes.remove(s.id);
    }
    erased!.addAll(hits);
    inkVersion.value++;
    _changed();
  }

  // ---------------- deshacer ----------------
  void _pushUndo(EditAction a) {
    history.push(a);
    setState(() {});
  }

  void _undoRedo({required bool undo}) {
    final a = undo ? history.undo() : history.redo();
    if (a == null) return;
    a.apply(doc, undo: undo, putText: texts.put);
    _clearSel();
    inkVersion.value++;
    _changed();
    setState(() {});
  }

  // ---------------- selección ----------------
  void _clearSel() {
    if (sel.isEmpty && sel.bandA == null) return;
    sel.clear();
    if (mounted) setState(() {});
    liveTick.value++;
  }

  /// Lápiz abajo con "seleccionar": dentro de la selección la mueve; afuera estira un rectángulo nuevo.
  void _selDown(Offset p) {
    final r = sel.bounds(doc);
    if (r != null && r.inflate(12).contains(p)) {
      sel.startDrag(doc, p);
      inkVersion.value++; // oculta los seleccionados de la capa fija
      setState(() {});
      return;
    }
    _clearSel();
    sel.bandA = sel.bandB = p;
    liveTick.value++;
  }

  void _selDrag(Offset p) {
    final drag = sel.drag!;
    final d = drag.delta = p - drag.from;
    setState(() {
      drag.textOrig.forEach((id, o) {
        final t = doc.texts[id];
        if (t != null) {
          t.x = o.dx + d.dx;
          t.y = o.dy + d.dy;
        }
      });
      drag.itemOrig.forEach((id, o) {
        final it = doc.items[id];
        if (it != null) {
          it.x = o.dx + d.dx;
          it.y = o.dy + d.dy;
        }
      });
    });
    liveTick.value++;
  }

  void _selDrop() {
    final drag = sel.drag!, d = drag.delta;
    sel.drag = null;
    if (d.distance < .5) {
      // fue un toque: nada se movió
      inkVersion.value++;
      setState(() {});
      return;
    }
    final removed = <Stroke>[], added = <Stroke>[];
    for (final id in sel.strokes) {
      final s = doc.strokes.remove(id);
      if (s == null) continue;
      final m = s.moved(d);
      removed.add(s);
      added.add(m);
      doc.strokes[id] = m;
    }
    final textBefore = <String, TextBlock?>{}, textAfter = <String, TextBlock?>{};
    drag.textOrig.forEach((id, o) {
      final t = doc.texts[id];
      if (t == null) return;
      t.y = max(0.0, doc.snapTextY(t.y)); // que caiga sobre el renglón de su hoja
      t.x = t.x.clamp(0.0, kW - 60);
      textBefore[id] = t.copy(d: o - Offset(t.x, t.y));
      textAfter[id] = t.copy();
    });
    final itemBefore = <String, Item?>{}, itemAfter = <String, Item?>{};
    drag.itemOrig.forEach((id, o) {
      final it = doc.items[id];
      if (it == null) return;
      itemBefore[id] = it.copy(d: o - Offset(it.x, it.y));
      itemAfter[id] = it.copy();
    });
    _pushUndo(EditAction(
        removed: removed,
        added: added,
        textBefore: textBefore,
        textAfter: textAfter,
        itemBefore: itemBefore,
        itemAfter: itemAfter));
    inkVersion.value++;
    final r = sel.bounds(doc);
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  void _copySel() {
    final c = ts.clipboard;
    c.strokes = sel.strokesOf(doc);
    c.texts = [for (final t in sel.textsOf(doc)) t.copy()];
    c.items = [for (final it in sel.itemsOf(doc)) it.copy()];
    setState(() {});
  }

  void _deleteSel() {
    final removed = sel.strokesOf(doc);
    final textBefore = {for (final t in sel.textsOf(doc)) t.id: t.copy()};
    final itemBefore = {for (final it in sel.itemsOf(doc)) it.id: it.copy()};
    for (final s in removed) {
      doc.strokes.remove(s.id);
    }
    for (final id in textBefore.keys) {
      texts.put(id, null);
    }
    for (final id in itemBefore.keys) {
      doc.items.remove(id);
    }
    _pushUndo(EditAction(
      removed: removed,
      textBefore: textBefore,
      textAfter: absent(textBefore.keys),
      itemBefore: itemBefore,
      itemAfter: absent(itemBefore.keys),
    ));
    _clearSel();
    inkVersion.value++;
    _changed();
  }

  /// Pega copias (con ids nuevos) corridas [d] y las deja seleccionadas.
  void _insert(List<Stroke> strokes, List<TextBlock> textBlocks, Offset d, List<Item> items) {
    final newStrokes = [for (final s in strokes) s.moved(d, id: newId('s'))];
    final newItems = [for (final it in items) it.copy(id: newId('i'), d: d)];
    final newTexts = [
      for (final t in textBlocks) t.copy(id: newId('t'), d: Offset((t.x + d.dx).clamp(0.0, kW - 60) - t.x, max(0.0, t.y + d.dy) - t.y))
    ];
    // las copias quedan arriba de todo, en el mismo orden que tenían entre sí
    doc.stackOnTop([...newStrokes, ...newTexts, ...newItems]);
    for (final it in newItems) {
      doc.items[it.id] = it;
    }
    for (final s in newStrokes) {
      doc.strokes[s.id] = s;
    }
    for (final t in newTexts) {
      texts.put(t.id, t);
    }
    _pushUndo(EditAction(
      added: newStrokes,
      textBefore: absent(newTexts.map((t) => t.id)),
      textAfter: {for (final t in newTexts) t.id: t.copy()},
      itemBefore: absent(newItems.map((it) => it.id)),
      itemAfter: {for (final it in newItems) it.id: it.copy()},
    ));
    if (ts.tool != Tool.select) _setTool(Tool.select);
    sel.replace(
      strokes: newStrokes.map((s) => s.id),
      texts: newTexts.map((t) => t.id),
      items: newItems.map((it) => it.id),
    );
    inkVersion.value++;
    final r = sel.bounds(doc);
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  /// Menú "Orden": mueve la selección en el orden de dibujo (con deshacer).
  void _reorderSel(ZMove m) {
    final ch = doc.reorder(sel.allIds, m, _rectOf);
    if (ch == null) return;
    _pushUndo(EditAction(zBefore: ch.before, zAfter: ch.after));
    inkVersion.value++;
    liveTick.value++;
    _changed();
  }

  Rect _rectOf(Layered e) => switch (e) {
        Stroke s => s.bounds,
        Item it => it.rect,
        TextBlock t => textRect(t, doc.lineAt(t.y)),
        _ => Rect.zero,
      };

  void _duplicateSel() => _insert(sel.strokesOf(doc), sel.textsOf(doc), const Offset(30, 30), sel.itemsOf(doc));

  /// Pegar desde la barra: si lo copiado está a la vista, corrido; si no, arriba de lo que se ve.
  void _paste() {
    final c = ts.clipboard;
    final r = clipboardBounds(c);
    if (r == null) return;
    final top = max(0.0, (scroll.offset - kTopPad) / scale);
    final bottom = top + scroll.position.viewportDimension / scale;
    final d = (r.top > top && r.top < bottom - 60) ? const Offset(30, 30) : Offset(90 - r.left, top + 60 - r.top);
    _insert(c.strokes, c.texts, d, c.items);
  }

  /// Pegar desde el menú de la hoja: la esquina de lo copiado va a [p].
  void _pasteAt(Offset p) {
    final c = ts.clipboard;
    final r = clipboardBounds(c);
    if (r == null) return;
    _insert(c.strokes, c.texts, p - r.topLeft, c.items);
  }

  // ---------------- texto ----------------
  void _removeText(String id) {
    if (!mounted) return;
    setState(() => texts.put(id, null));
    _changed();
  }

  void _tapPage(TapUpDetails d) {
    if (ts.tool != Tool.text) return;
    if (texts.anyFocused) {
      FocusScope.of(context).unfocus(); // primer toque afuera: solo cierra el texto
      return;
    }
    _createTextAt(_toPage(d.localPosition));
  }

  void _createTextAt(Offset p) {
    final x = p.dx.clamp(16.0, kW - 120);
    var y = max(0.0, doc.snapTextY(p.dy, floor: true)); // el renglón de esa hoja
    // en el espacio entre hojas (o sin lugar para un renglón): a la siguiente
    if (y % kSheetStep > kSheetH - doc.lineAt(y) && y ~/ kSheetStep < doc.sheetCount - 1) {
      y = doc.snapTextY((y ~/ kSheetStep + 1) * kSheetStep, floor: true);
    }
    _placeText(x, y);
  }

  /// Un bloque nuevo y vacío en ([x], [y]) (y ya sobre el renglón), con el foco y el teclado.
  void _placeText(double x, double y) {
    final t = TextBlock(newId('t'), x.roundToDouble(), y, (kW - x - 30).roundToDouble(), '')..z = doc.nextZ();
    setState(() => texts.put(t.id, t));
    texts.editor(t.id)?.focusAt(0, 0);
    showKeyboard();
    _growIfNeeded(y + doc.lineAt(y));
    _changed();
  }

  /// El tecladito de la barra: renglón nuevo debajo de lo último que se ve en la hoja visible
  /// (o en el primer renglón de la parte visible si no hay nada).
  void _newTextAtVisible() {
    final k = visibleSheet, sheetTop = k * kSheetStep, line = doc.lineAt(sheetTop + 1);
    final vh = scroll.hasClients ? scroll.position.viewportDimension / scale : 600 / scale;
    final top = scroll.hasClients ? max(0.0, (scroll.offset - kTopPad) / scale) : sheetTop;
    final region = Rect.fromLTRB(0, max(top, sheetTop), kW, min(top + vh, sheetTop + kSheetH));
    double? bottom;
    void see(Rect r) {
      if (r.overlaps(region)) bottom = max(bottom ?? r.bottom, r.bottom);
    }

    for (final s in doc.strokes.values) {
      see(s.bounds);
    }
    for (final t in doc.texts.values) {
      see(textRect(t, doc.lineAt(t.y)));
    }
    for (final it in doc.items.values) {
      see(it.rect);
    }
    // el renglón de abajo de lo último (se sube un renglón menos un pelo: queda en el más cercano hacia abajo)
    var y = bottom != null
        ? doc.snapTextY(bottom! + line - 0.01, floor: true)
        : doc.snapTextY(max(region.top + line * .5, sheetTop + mmToUnits(kTopMarginMm) - line) + line - 0.01, floor: true);
    if (y - sheetTop > kSheetH - line && k < doc.sheetCount - 1) {
      y = doc.snapTextY((k + 1) * kSheetStep + 1, floor: false); // no entra: a la hoja siguiente
    }
    _placeText(mmToUnits(kMarginMm) + 10, y);
    if (scroll.hasClients && y + line > region.bottom) {
      final to = (y * scale + kTopPad - scroll.position.viewportDimension * .4).clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(to, duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuart);
    }
  }

  /// Tocar el tecladito estando en modo texto: vuelve a abrir el teclado en el último bloque escrito.
  void _reopenKeyboard() {
    final id = texts.lastEdited;
    if (id != null && doc.texts.containsKey(id)) {
      texts.focusEnd(id);
    } else {
      _newTextAtVisible();
    }
  }

  void _textEdited(TextBlock t) {
    // estimación de renglones (70 letras por renglón) para agregar hojas a tiempo
    var lines = 0;
    for (final p in t.body.paras) {
      lines += 1 + p.length ~/ 70;
    }
    _growIfNeeded(t.y + lines * doc.lineAt(t.y));
    _saveSoon(t.id, const Duration(milliseconds: 300));
  }

  // ---------------- herramientas ----------------
  void _setTool(Tool t) {
    if (t != Tool.select) _clearSel();
    setState(() => ts.tool = t);
    if (t != Tool.text) FocusScope.of(context).unfocus();
  }

  void _toolTap(Tool t) {
    if (t == Tool.text) {
      if (ts.tool == Tool.text) {
        _reopenKeyboard();
      } else {
        _setTool(t);
        _newTextAtVisible();
        widget.onPrefsChanged();
      }
      return;
    }
    if (ts.tool == t && ts.drawing) {
      _openPanel(); // tocar de nuevo la herramienta elegida abre sus opciones
      return;
    }
    _setTool(t);
    widget.onPrefsChanged();
  }

  Future<void> _openPanel() async {
    final align = switch (ts.dock) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.topCenter
    };
    await showPenPanel(context, ts, () {
      setState(() {});
      widget.onPrefsChanged();
    }, align);
    if (mounted) setState(() {});
  }

  /// Colores y grosor: desde texto/seleccionar, vuelve al lápiz.
  void _openPanelForDrawing() {
    if (!ts.drawing) _setTool(Tool.pen);
    _openPanel();
  }

  void _pickQuick(String c) {
    if (!ts.drawing) _setTool(Tool.pen);
    setState(() => ts.pickColor(c));
    widget.onPrefsChanged();
  }

  // ---------------- hoja nueva tirando ----------------
  void _addSheetFromPull() {
    final oldH = doc.h;
    setState(doc.addSheet);
    _changed();
    // lleva a la hoja nueva
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll.animateTo(min(scroll.position.maxScrollExtent, (oldH + kGap) * scale),
          duration: const Duration(milliseconds: 420), curve: Curves.easeOutQuart);
    });
  }

  // ---------------- dedos: zoom y menú de la hoja ----------------
  Offset get _scrollOffset => Offset(hscroll.hasClients ? hscroll.offset : 0, scroll.hasClients ? scroll.offset : 0);

  void _flashZoom() {
    _zoomPillTimer?.cancel();
    stillPress.cancel();
    setState(() => _zoomPill = true);
    _zoomPillTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _zoomPill = false);
    });
  }

  /// Cambia el zoom dejando quieto el punto [focal] del visor (el centro si es null).
  void _setZoom(double z, [Offset? focal]) {
    z = z.clamp(.5, 4.0);
    if ((z - ts.zoom).abs() < .001) return;
    final f = focal ??
        Offset(hscroll.hasClients ? hscroll.position.viewportDimension / 2 : 0,
            scroll.hasClients ? scroll.position.viewportDimension / 2 : 0);
    final anchor = layout.toPage(f, _scrollOffset);
    setState(() => ts.zoom = z);
    _flashZoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final to = layout.scrollFor(anchor, f); // con la escala nueva
      if (hscroll.hasClients) hscroll.jumpTo(to.dx.clamp(0.0, hscroll.position.maxScrollExtent));
      if (scroll.hasClients) scroll.jumpTo(to.dy.clamp(0.0, scroll.position.maxScrollExtent));
    });
  }

  void _touchDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touch.down(e.pointer, e.position);
    if (touch.length == 1 && pointer == null) {
      stillPress.start(e.position);
    } else {
      stillPress.cancel(); // segundo dedo: es zoom, no menú
    }
    // dos dedos = pellizco (salvo que el zoom esté fijado o se esté escribiendo con el lápiz)
    if (touch.length == 2 && !ts.zoomLocked && pointer == null) {
      touch.startPinch(ts.zoom);
      pull.cancel();
      setState(() {});
    }
  }

  void _touchMove(PointerMoveEvent e) {
    if (!touch.tracks(e.pointer)) return;
    touch.move(e.pointer, e.position);
    stillPress.moved(e.position);
    final p = touch.pinch();
    if (p == null) return;
    final box = _viewportKey.currentContext!.findRenderObject() as RenderBox;
    _setZoom(p.zoom, box.globalToLocal(p.focal));
  }

  void _touchUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touch.up(e.pointer);
    stillPress.cancel();
    if (touch.pinching && touch.length < 2) {
      setState(() => touch.pinching = false);
      widget.onPrefsChanged();
    }
    if (touch.count == 0) pull.cancel(); // soltó antes de completar: vuelve
  }

  void _toggleZoomLock() {
    setState(() => ts.zoomLocked = !ts.zoomLocked);
    HapticFeedback.selectionClick();
    _flashZoom();
    widget.onPrefsChanged();
  }

  /// Un dedo quieto sobre la hoja: menú contextual (si no se está scrolleando ni escribiendo).
  void _onStillPress(Offset g) {
    if (!mounted || touch.pinching || touch.length != 1 || pointer != null) return;
    if (scroll.hasClients && scroll.position.isScrollingNotifier.value) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(g);
    if (!(Offset.zero & box.size).contains(local)) return;
    _sheetMenu(g, _toPage(local));
  }

  Future<void> _sheetMenu(Offset global, Offset p) async {
    HapticFeedback.mediumImpact();
    final v = await showSheetMenu(
      context,
      global,
      canPaste: !ts.clipboard.isEmpty,
      canSelectAll: !doc.isEmpty,
      canResetZoom: !ts.zoomLocked && (ts.zoom - 1).abs() > .01,
    );
    if (!mounted) return;
    switch (v) {
      case SheetMenuAction.paste:
        _pasteAt(p);
      case SheetMenuAction.text:
        _setTool(Tool.text);
        _createTextAt(p);
      case SheetMenuAction.selectAll:
        _setTool(Tool.select);
        setState(() => sel.selectAll(doc));
        liveTick.value++;
      case SheetMenuAction.addSheet:
        setState(doc.addSheet);
        _changed();
      case SheetMenuAction.zoomToWidth:
        _setZoom(1);
        widget.onPrefsChanged();
      case null:
        break;
    }
  }

  // ---------------- lo que usa la pantalla del cuaderno ----------------
  /// Centro de lo que se está viendo, en coordenadas de la página.
  Offset get viewCenter {
    final vw = hscroll.hasClients ? hscroll.position.viewportDimension : kW * scale;
    final vh = scroll.hasClients ? scroll.position.viewportDimension : 600.0;
    final c = layout.toPage(Offset(vw / 2, vh / 2), _scrollOffset);
    return Offset(c.dx.clamp(0, kW), c.dy.clamp(0, doc.h));
  }

  /// Hoja que se está viendo (0, 1, 2...).
  int get visibleSheet => doc.sheetOfY(viewCenter.dy);

  bool _sheetCheckPending = false;

  /// El scroll puede avisar en pleno armado de pantalla: se mira recién después del cuadro.
  void _scheduleVisibleSheet() {
    if (_sheetCheckPending) return;
    _sheetCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetCheckPending = false;
      if (mounted) _updateVisibleSheet();
    });
  }

  /// Avisa a la pantalla qué hoja se ve ahora (y refresca la barra, que muestra el fondo de esa hoja).
  void _updateVisibleSheet() {
    final k = visibleSheet, n = widget.sheetNotifier;
    if (n != null && n.value != k) {
      n.value = k;
      if (mounted) setState(() {});
    }
  }

  /// Lleva la vista al principio de la hoja [k].
  void scrollToSheet(int k, {bool animate = true}) {
    if (!mounted) return;
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToSheet(k, animate: animate));
      return;
    }
    final y = (k.clamp(0, doc.sheetCount - 1) * kSheetStep * scale).clamp(0.0, scroll.position.maxScrollExtent);
    if (animate) {
      scroll.animateTo(y, duration: const Duration(milliseconds: 380), curve: Curves.easeOutQuart);
    } else {
      scroll.jumpTo(y);
    }
  }

  /// Después de agregar, duplicar, mover o borrar hojas desde afuera: lo que dependía del orden
  /// anterior (deshacer, selección, campos de texto) ya no sirve. Las operaciones de hojas no se deshacen.
  void sheetsChanged() {
    texts.attach(doc);
    history.clear();
    sel.clear();
    pointer = null;
    live = null;
    erased = null;
    eraserAt = null;
    _changed();
    setState(() {});
    inkVersion.value++;
    liveTick.value++;
    _updateVisibleSheet();
  }

  /// Agrega un elemento centrado en lo que se está viendo y lo deja seleccionado.
  void insertItem(Item it) {
    final c = viewCenter;
    it.x = (c.dx - it.w / 2).clamp(10.0, max(10.0, kW - it.w - 10));
    it.y = max(0.0, c.dy - it.h / 2);
    it.z = doc.nextZ();
    doc.items[it.id] = it;
    _pushUndo(EditAction(itemBefore: {it.id: null}, itemAfter: {it.id: it.copy()}));
    _setTool(Tool.select);
    sel.replace(items: [it.id]);
    _growIfNeeded(it.y + it.h);
    _changed();
    setState(() {});
    liveTick.value++;
  }

  /// Lleva la vista a un texto o elemento y lo deja seleccionado (búsqueda).
  void reveal(String id) {
    final t = doc.texts[id], it = doc.items[id];
    final y = t?.y ?? it?.y;
    if (y == null) return;
    _setTool(Tool.select);
    setState(() => sel.replace(texts: [if (t != null) id], items: [if (it != null) id]));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo((y * scale + kTopPad - 120).clamp(0.0, scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 380), curve: Curves.easeOutQuart);
      }
    });
    liveTick.value++;
  }

  /// Después de cambiar fondo/papel desde afuera.
  void refresh() {
    setState(() {});
    inkVersion.value++;
  }

  // ---------------- armado ----------------
  @override
  Widget build(BuildContext context) => DockLayout(
        dock: ts.dock,
        hideToolbar: widget.readOnly,
        canvas: _canvasArea(),
        toolbar: (vertical, grip) => EditorToolbar(
          ts: ts,
          vertical: vertical,
          grip: grip,
          canUndo: history.canUndo,
          canRedo: history.canRedo,
          bg: doc.sheets[visibleSheet].bg,
          onToolTap: _toolTap,
          onToolLongPress: (t) {
            _setTool(t);
            _openPanel();
          },
          onPickColor: _pickQuick,
          onBg: (v) {
            setState(() => doc.sheets[visibleSheet].setBg(v)); // la hoja que se está viendo
            _changed();
          },
          onOpenPanel: _openPanelForDrawing,
          onUndo: () => _undoRedo(undo: true),
          onRedo: () => _undoRedo(undo: false),
          onToggleZoomLock: _toggleZoomLock,
          onPaste: _paste,
        ),
        onDock: (d) {
          setState(() => ts.dock = d);
          widget.onPrefsChanged();
        },
      );

  /// Visor: scroll vertical y horizontal con la página centrada, y los avisos flotantes.
  Widget _canvasArea() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: LayoutBuilder(builder: (context, box) {
        layout = SheetLayout(box.maxWidth, ts.zoom);
        final sheetSize = Size(layout.sheetWidth, doc.h * scale);
        // durante el pellizco no scrollea: si no, el zoom tironea
        final physics = touch.pinching ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics();
        return Stack(children: [
          Listener(
            key: _viewportKey,
            onPointerDown: _touchDown,
            onPointerMove: _touchMove,
            onPointerUp: _touchUp,
            onPointerCancel: _touchUp,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => pull.onScroll(n, touching: touch.count > 0),
              child: ScrollConfiguration(
                // el lápiz NO scrollea: solo dedo y touchpad
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
                  scrollbars: true,
                ),
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: physics,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  child: SingleChildScrollView(
                    controller: hscroll,
                    scrollDirection: Axis.horizontal,
                    physics: physics,
                    child: SizedBox(
                      width: layout.contentWidth,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: kTopPad),
                        Padding(
                          padding: EdgeInsets.only(left: layout.sheetLeft),
                          child: SizedBox.fromSize(key: _sheetKey, size: sheetSize, child: _sheet()),
                        ),
                        SizedBox(
                          width: layout.contentWidth,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 70),
                            child: Text(
                              'Al final, deslizá hacia arriba y mantené para agregar una hoja',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: .7), fontSize: 13),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 28, child: Center(child: PullIndicator(pull))),
          if (ts.tool == Tool.text && texts.anyFocused)
            Positioned(left: 0, right: 0, bottom: 0, child: FormatBar(fields: texts)),
          Positioned(
            left: 0,
            right: 0,
            top: 14,
            child: Center(
              child: ZoomIndicator(visible: _zoomPill || touch.pinching, zoom: ts.zoom, locked: ts.zoomLocked),
            ),
          ),
        ]);
      }),
    );
  }

  /// La página: capas + menú de la selección + esquina para agrandar un elemento.
  Widget _sheet() {
    final textMode = ts.tool == Tool.text;
    final r = !sel.isEmpty && !sel.moving ? sel.bounds(doc) : null;
    final resizable = r != null && sel.singleItem ? doc.items[sel.items.first] : null;
    return Stack(clipBehavior: Clip.none, children: [
      _layers(textMode),
      if (r != null)
        Positioned(
          left: max(0.0, r.left * scale),
          top: r.top * scale > 60 ? r.top * scale - 56 : r.bottom * scale + 8,
          child: SelectionMenu(
            onCopy: () {
              _copySel();
              snack(context, 'Copiado', duration: const Duration(milliseconds: 1200), width: 260);
            },
            onCut: () {
              _copySel();
              _deleteSel();
            },
            onDuplicate: _duplicateSel,
            onDelete: _deleteSel,
            onClose: _clearSel,
            onOrder: _reorderSel,
          ),
        ),
      if (resizable != null)
        ResizeHandle(
          item: resizable,
          scale: scale,
          onResize: () => setState(() => liveTick.value++),
          onResizeEnd: (before) {
            _pushUndo(EditAction(itemBefore: {resizable.id: before}, itemAfter: {resizable.id: resizable.copy()}));
            _changed();
          },
        ),
    ]);
  }

  /// De abajo hacia arriba: papel, y después todo en el orden de dibujo (un solo orden para trazos,
  /// textos y elementos), y arriba la capa en vivo.
  ///
  /// Rendimiento: la tinta no se dibuja trazo por trazo en widgets. Los trazos seguidos en el orden forman
  /// una tanda ([ZRun]) y cada tanda es una capa con caché ([RepaintBoundary]) que solo se repinta cuando
  /// cambian sus trazos. Una página normal (cientos de trazos y los textos/imágenes de siempre) es una
  /// sola tanda, igual que antes; cada imagen, nota o texto que quede "en el medio" de la tinta suma una
  /// capa más. Los widgets llevan clave para conservar su estado (campos de texto, audio) al reordenarse.
  Widget _layers(bool textMode) {
    final runs = zRuns(doc.drawOrder());
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: textMode ? _tapPage : null,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: SheetPainter(doc.sheets, scale))),
          for (var i = 0; i < runs.length; i++) _run(runs[i], i, textMode),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                // método y no closure: tiene que leer el trazo en curso al pintar, no al armar
                painter: LivePainter(_paintLive, scale, liveTick),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _run(ZRun run, int i, bool textMode) {
    final strokes = run.strokes;
    if (strokes != null) {
      return Positioned.fill(
        key: ValueKey('ink-$i'),
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
                painter: InkPainter(doc, strokes, scale, inkVersion, () => sel.moving ? sel.strokes : const {}),
                isComplex: true),
          ),
        ),
      );
    }
    final e = run.single;
    if (e is Item) {
      return ItemView(
        key: ValueKey('item-${e.id}'),
        item: e,
        file: widget.store.media(e.file ?? ''),
        scale: scale,
        textMode: textMode,
        selected: sel.items.contains(e.id),
        onStickyChanged: (v) {
          e.text = v;
          _saveSoon(e.id, const Duration(milliseconds: 350));
        },
      );
    }
    return _textBlock(e as TextBlock, textMode);
  }

  void _paintLive(Canvas c) => paintLiveLayer(c,
      doc: doc, scale: scale, sel: sel, live: live, eraserAt: eraserAt, eraserRadius: ts.eraserRadius);

  Widget _textBlock(TextBlock t, bool textMode) {
    final ed = texts.editor(t.id);
    if (ed == null) return const SizedBox.shrink();
    return TextBlockView(
      key: ValueKey('text-${t.id}'),
      block: t,
      editor: ed,
      scale: scale,
      line: doc.lineAt(t.y),
      textMode: textMode,
      selected: sel.texts.contains(t.id),
      onHandleDrag: (delta) => setState(() {
        t.x = (t.x + delta.dx / scale).clamp(0.0, kW - 60);
        t.y = max(0.0, t.y + delta.dy / scale);
        t.w = min(t.w, kW - t.x - 10).clamp(120.0, kW);
      }),
      onHandleDragEnd: () => setState(() {
        t.y = doc.snapTextY(t.y);
        _changed();
      }),
    );
  }
}
