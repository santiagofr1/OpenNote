import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'model.dart';
import 'painters.dart';
import 'pen_panel.dart';

/// Una acción deshacible: trazos que salieron/entraron y cómo estaban los textos antes/después.
class _Act {
  final List<Stroke> removed, added;
  final Map<String, TextBlock?> textBefore, textAfter;
  _Act({this.removed = const [], this.added = const [], this.textBefore = const {}, this.textAfter = const {}});
}

TextBlock _copyText(TextBlock t, [Offset d = Offset.zero]) => TextBlock(t.id, t.x + d.dx, t.y + d.dy, t.w, t.text);

Stroke _moved(Stroke s, Offset d, [String? id]) {
  final p = List<double>.of(s.pts);
  for (var i = 0; i < p.length; i += 3) {
    p[i] += d.dx;
    p[i + 1] += d.dy;
  }
  return Stroke(id ?? s.id, s.k, s.c, s.w, p, s.o);
}

class PageEditor extends StatefulWidget {
  final PageData page;
  final ToolState tools;
  final String title, subtitle;
  final VoidCallback onChanged, onPrefsChanged, onMenu, onBack;
  const PageEditor({
    super.key,
    required this.page,
    required this.tools,
    required this.title,
    required this.subtitle,
    required this.onChanged,
    required this.onPrefsChanged,
    required this.onMenu,
    required this.onBack,
  });

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> with SingleTickerProviderStateMixin {
  PageData get page => widget.page;
  ToolState get ts => widget.tools;

  final scroll = ScrollController();
  final inkVersion = ValueNotifier(0);
  final liveTick = ValueNotifier(0);
  final undo = <_Act>[], redo = <_Act>[];
  double scale = 1;

  // entrada en curso
  int? pointer;
  Stroke? live;
  Offset? eraserAt;
  List<Stroke>? erased;

  // selección
  final selS = <String>{}, selT = <String>{};
  Offset? bandA, bandB; // rectángulo que se está estirando
  Offset? dragFrom;
  Offset dragDelta = Offset.zero;
  bool moving = false;
  Map<String, Offset> textOrig = {};

  // texto
  final ctrls = <String, TextEditingController>{};
  final focus = <String, FocusNode>{};
  final textTimers = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    for (final t in page.texts.values) {
      _bindText(t);
    }
  }

  @override
  void dispose() {
    for (final t in textTimers.values) {
      t.cancel();
    }
    for (final c in ctrls.values) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
    scroll.dispose();
    hscroll.dispose();
    pullCtrl.dispose();
    _zoomPillT?.cancel();
    _lpTimer?.cancel();
    super.dispose();
  }

  void _changed() => widget.onChanged();

  // ---------------- entrada: lápiz / goma ----------------
  bool _isStylus(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  Offset _logical(Offset local) => local / scale;

  void _down(PointerDownEvent e) {
    final stylus = _isStylus(e);
    final mouse = e.kind == PointerDeviceKind.mouse;
    if (!stylus && !mouse) return; // el dedo solo scrollea (palma ignorada)
    if (pointer != null) return;
    if (mouse && e.buttons != kPrimaryMouseButton && e.buttons != kSecondaryMouseButton) return;
    final p = _logical(e.localPosition);
    if (_wantsEraser(e)) {
      pointer = e.pointer;
      _startErase(p);
      return;
    }
    if (ts.tool == Tool.text) return;
    pointer = e.pointer;
    if (ts.tool == Tool.select) {
      _selDown(p);
      return;
    }
    final pr = ts.current;
    live = Stroke(newId('s'), ts.tool == Tool.hl ? 'hl' : pr.tip, pr.color, pr.width, [], pr.opacity);
    _addPoint(e, p);
    liveTick.value++;
  }

  /// botón del S Pen apretado, punta goma del lápiz, o clic derecho del mouse
  bool _wantsEraser(PointerEvent e) =>
      e.kind == PointerDeviceKind.invertedStylus ||
      (_isStylus(e) && (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0) ||
      (e.kind == PointerDeviceKind.mouse && (e.buttons & kSecondaryMouseButton) != 0);

  void _startErase(Offset p) {
    erased = [];
    _eraseAt(p);
    eraserAt = p;
    liveTick.value++;
  }

  void _commitLive() {
    final s = live;
    live = null;
    if (s == null || s.n < 2) return;
    _smooth(s);
    s.invalidate();
    page.strokes[s.id] = s;
    inkVersion.value++;
    _pushUndo(_Act(added: [s]));
    _growIfNeeded(s.bounds.bottom);
    _changed();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != pointer) return;
    final p = _logical(e.localPosition);
    if (moving) {
      _selDrag(p);
      return;
    }
    if (bandA != null) {
      bandB = p;
      liveTick.value++;
      return;
    }
    if (live != null && _wantsEraser(e)) {
      // apretó el botón a mitad del trazo: lo que venía queda, y sigue borrando
      _commitLive();
      _startErase(p);
      return;
    }
    if (erased != null) {
      _eraseAt(p);
      eraserAt = p;
    } else if (live != null) {
      _addPoint(e, p);
    }
    liveTick.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != pointer) return;
    pointer = null;
    if (moving) {
      _selDrop();
      return;
    }
    if (bandA != null) {
      _selectIn(Rect.fromPoints(bandA!, bandB!));
      bandA = bandB = null;
      liveTick.value++;
      return;
    }
    if (erased != null) {
      if (erased!.isNotEmpty) _pushUndo(_Act(removed: erased!));
      erased = null;
      eraserAt = null;
      liveTick.value++;
      return;
    }
    final s = live;
    live = null;
    liveTick.value++;
    if (s == null || (e is PointerCancelEvent && s.n < 3)) return;
    live = s;
    _commitLive();
  }

  void _addPoint(PointerEvent e, Offset p) {
    final pts = live!.pts;
    double pr = .5;
    if (_isStylus(e)) {
      final range = e.pressureMax - e.pressureMin;
      pr = range > 0 ? ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0) : .5;
    }
    if (pts.isNotEmpty) {
      final lx = pts[pts.length - 3], ly = pts[pts.length - 2];
      if ((p.dx - lx).abs() + (p.dy - ly).abs() < .6) return;
      pr = pts[pts.length - 1] * .65 + pr * .35; // suaviza la presión
    }
    pts.addAll([p.dx, p.dy, pr]);
    live!.invalidate();
  }

  /// promedio con los vecinos: saca el temblequeo sin deformar
  void _smooth(Stroke s) {
    final p = s.pts, n = s.n;
    if (n < 4) return;
    final c = List<double>.of(p);
    for (var i = 1; i < n - 1; i++) {
      for (var k = 0; k < 2; k++) {
        p[i * 3 + k] = (c[(i - 1) * 3 + k] + 2 * c[i * 3 + k] + c[(i + 1) * 3 + k]) / 4;
      }
    }
  }

  double get _eraserR => eraserSizes[ts.eraserSize];

  void _eraseAt(Offset pt) {
    final r = _eraserR;
    final hits = <Stroke>[];
    for (final s in page.strokes.values) {
      if (!s.bounds.inflate(r).contains(pt)) continue;
      final lim = r + s.w * .75, p = s.pts;
      var hit = s.n == 1 && (Offset(p[0], p[1]) - pt).distance < lim;
      for (var i = 1; i < s.n && !hit; i++) {
        if (_distSeg(pt, Offset(p[i * 3 - 3], p[i * 3 - 2]), Offset(p[i * 3], p[i * 3 + 1])) < lim) hit = true;
      }
      if (hit) hits.add(s);
    }
    if (hits.isEmpty) return;
    for (final s in hits) {
      page.strokes.remove(s.id);
    }
    erased!.addAll(hits);
    inkVersion.value++;
    _changed();
  }

  double _distSeg(Offset p, Offset a, Offset b) {
    final d = b - a, l = d.distanceSquared;
    final t = l == 0 ? 0.0 : (((p - a).dx * d.dx + (p - a).dy * d.dy) / l).clamp(0.0, 1.0);
    return (p - (a + d * t)).distance;
  }

  void _growIfNeeded(double y) {
    if (y > page.h - 250) {
      setState(() => page.h = heightFor(y ~/ kSheetStep + 2));
    }
  }

  // ---------------- deshacer ----------------
  void _pushUndo(_Act a) {
    undo.add(a);
    if (undo.length > 200) undo.removeAt(0);
    redo.clear();
    setState(() {});
  }

  void _undoRedo(List<_Act> from, List<_Act> to) {
    if (from.isEmpty) return;
    final a = from.removeLast();
    final undoing = identical(from, undo);
    final out = undoing ? a.added : a.removed, back = undoing ? a.removed : a.added;
    for (final s in out) {
      page.strokes.remove(s.id);
    }
    for (final s in back) {
      page.strokes[s.id] = s;
    }
    (undoing ? a.textBefore : a.textAfter).forEach((id, t) => _putText(id, t == null ? null : _copyText(t)));
    _clearSel();
    to.add(a);
    inkVersion.value++;
    _changed();
    setState(() {});
  }

  // ---------------- selección ----------------
  Size _textSize(TextBlock t) {
    final tp = TextPainter(
      text: TextSpan(text: t.text.isEmpty ? ' ' : t.text, style: const TextStyle(fontSize: kFont, height: kLine / kFont)),
      strutStyle: const StrutStyle(fontSize: kFont, height: kLine / kFont, forceStrutHeight: true),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: t.w);
    return Size(max(tp.width, 20), max(tp.height, kLine));
  }

  Rect _textRect(TextBlock t) => Offset(t.x, t.y) & _textSize(t);

  bool get hasSel => selS.isNotEmpty || selT.isNotEmpty;

  /// rectángulo que envuelve lo seleccionado, en su posición original (sin el arrastre en curso)
  Rect? get selRect {
    Rect? r;
    for (final id in selS) {
      final s = page.strokes[id];
      if (s != null) r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    for (final id in selT) {
      final t = page.texts[id];
      if (t == null) continue;
      final o = moving ? textOrig[id] : null;
      final tr = o != null ? _textRect(t).shift(o - Offset(t.x, t.y)) : _textRect(t);
      r = r == null ? tr : r.expandToInclude(tr);
    }
    return r?.inflate(6);
  }

  void _clearSel() {
    if (!hasSel && bandA == null) return;
    selS.clear();
    selT.clear();
    bandA = bandB = null;
    moving = false;
    if (mounted) setState(() {});
    liveTick.value++;
  }

  void _selDown(Offset p) {
    final r = selRect;
    if (r != null && r.inflate(12).contains(p)) {
      moving = true;
      dragFrom = p;
      dragDelta = Offset.zero;
      textOrig = {
        for (final id in selT)
          if (page.texts[id] != null) id: Offset(page.texts[id]!.x, page.texts[id]!.y)
      };
      inkVersion.value++; // oculta los seleccionados de la capa fija
      setState(() {});
      return;
    }
    _clearSel();
    bandA = bandB = p;
    liveTick.value++;
  }

  void _selDrag(Offset p) {
    dragDelta = p - dragFrom!;
    setState(() {
      for (final e in textOrig.entries) {
        final t = page.texts[e.key];
        if (t != null) {
          t.x = e.value.dx + dragDelta.dx;
          t.y = e.value.dy + dragDelta.dy;
        }
      }
    });
    liveTick.value++;
  }

  void _selDrop() {
    final d = dragDelta;
    if (d.distance < .5) {
      moving = false;
      dragDelta = Offset.zero;
      textOrig = {};
      inkVersion.value++;
      setState(() {});
      return;
    }
    final removed = <Stroke>[], added = <Stroke>[];
    for (final id in selS) {
      final s = page.strokes.remove(id);
      if (s == null) continue;
      final m = _moved(s, d);
      removed.add(s);
      added.add(m);
      page.strokes[id] = m;
    }
    final before = <String, TextBlock?>{}, after = <String, TextBlock?>{};
    for (final e in textOrig.entries) {
      final t = page.texts[e.key];
      if (t == null) continue;
      t.y = max(0.0, ((t.y - 4) / kLine).roundToDouble() * kLine + 4); // que caiga sobre el renglón
      t.x = t.x.clamp(0.0, kW - 60);
      before[e.key] = TextBlock(t.id, e.value.dx, e.value.dy, t.w, t.text);
      after[e.key] = _copyText(t);
    }
    moving = false;
    dragDelta = Offset.zero;
    textOrig = {};
    _pushUndo(_Act(removed: removed, added: added, textBefore: before, textAfter: after));
    inkVersion.value++;
    final r = selRect;
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  void _selectIn(Rect r) {
    selS.clear();
    selT.clear();
    if (r.width < 4 && r.height < 4) {
      setState(() {});
      return;
    }
    for (final s in page.strokes.values) {
      if (!r.overlaps(s.bounds)) continue;
      var inside = 0;
      for (var i = 0; i < s.pts.length; i += 3) {
        if (r.contains(Offset(s.pts[i], s.pts[i + 1]))) inside++;
      }
      if (inside * 2 >= s.n) selS.add(s.id); // la mitad o más adentro
    }
    for (final t in page.texts.values) {
      if (r.contains(_textRect(t).center)) selT.add(t.id);
    }
    setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1200), behavior: SnackBarBehavior.floating, width: 260));
  }

  void _copySel() {
    ts.clipStrokes = [
      for (final id in selS)
        if (page.strokes[id] != null) page.strokes[id]!
    ];
    ts.clipTexts = [
      for (final id in selT)
        if (page.texts[id] != null) _copyText(page.texts[id]!)
    ];
    setState(() {});
  }

  void _deleteSel() {
    final removed = [
      for (final id in selS)
        if (page.strokes[id] != null) page.strokes[id]!
    ];
    final before = <String, TextBlock?>{
      for (final id in selT)
        if (page.texts[id] != null) id: _copyText(page.texts[id]!)
    };
    for (final s in removed) {
      page.strokes.remove(s.id);
    }
    for (final id in before.keys) {
      _putText(id, null);
    }
    _pushUndo(_Act(removed: removed, textBefore: before, textAfter: {for (final id in before.keys) id: null}));
    _clearSel();
    inkVersion.value++;
    _changed();
  }

  /// pega trazos/textos (con ids nuevos), corridos [d], y los deja seleccionados
  void _insert(List<Stroke> strokes, List<TextBlock> texts, Offset d) {
    final added = [for (final s in strokes) _moved(s, d, newId('s'))];
    final after = <String, TextBlock>{};
    for (final t in texts) {
      final n = TextBlock(newId('t'), (t.x + d.dx).clamp(0.0, kW - 60), max(0.0, t.y + d.dy), t.w, t.text);
      after[n.id] = n;
    }
    for (final s in added) {
      page.strokes[s.id] = s;
    }
    after.forEach((id, t) => _putText(id, t));
    _pushUndo(_Act(
      added: added,
      textBefore: {for (final id in after.keys) id: null},
      textAfter: {for (final e in after.entries) e.key: _copyText(e.value)},
    ));
    if (ts.tool != Tool.select) _setTool(Tool.select);
    selS
      ..clear()
      ..addAll(added.map((s) => s.id));
    selT
      ..clear()
      ..addAll(after.keys);
    inkVersion.value++;
    final r = selRect;
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  void _duplicateSel() {
    _insert([
      for (final id in selS)
        if (page.strokes[id] != null) page.strokes[id]!
    ], [
      for (final id in selT)
        if (page.texts[id] != null) page.texts[id]!
    ], const Offset(30, 30));
  }

  void _paste() {
    if (!ts.hasClip) return;
    Rect? r;
    for (final s in ts.clipStrokes) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    for (final t in ts.clipTexts) {
      r = r == null ? _textRect(t) : r.expandToInclude(_textRect(t));
    }
    // si lo copiado está a la vista, se pega corrido; si no, arriba de lo que estás viendo
    final top = max(0.0, (scroll.offset - 16) / scale);
    final bottom = top + scroll.position.viewportDimension / scale;
    final d = (r!.top > top && r.top < bottom - 60) ? const Offset(30, 30) : Offset(90 - r.left, top + 60 - r.top);
    _insert(ts.clipStrokes, ts.clipTexts, d);
  }

  /// capa "en vivo": trazo en curso, goma, rectángulo de selección, lo que se arrastra
  void _paintLive(Canvas c) {
    final s = live;
    if (s != null) paintStroke(c, s);
    final e = eraserAt;
    if (e != null) {
      c.drawCircle(
        e,
        _eraserR,
        Paint()
          ..color = kMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale,
      );
    }
    final border = Paint()
      ..color = kAccent
      ..strokeWidth = 1.5 / scale;
    if (bandA != null && bandB != null) {
      final r = Rect.fromPoints(bandA!, bandB!);
      c.drawRect(r, Paint()..color = const Color(0x142F5BD3));
      dashedRect(c, r, border, 6 / scale);
    }
    if (moving) {
      c.save();
      c.translate(dragDelta.dx, dragDelta.dy);
      for (final id in selS) {
        final st = page.strokes[id];
        if (st != null) paintStroke(c, st);
      }
      c.restore();
    }
    final r = selRect;
    if (r != null) {
      final rr = r.shift(moving ? dragDelta : Offset.zero);
      c.drawRect(rr, Paint()..color = const Color(0x0F2F5BD3));
      dashedRect(c, rr, border, 6 / scale);
    }
  }

  // ---------------- texto ----------------
  void _bindText(TextBlock t) {
    final c = TextEditingController(text: t.text);
    final f = FocusNode();
    f.addListener(() {
      if (!f.hasFocus && c.text.trim().isEmpty && page.texts.containsKey(t.id)) {
        // bloque vacío al salir: se borra
        WidgetsBinding.instance.addPostFrameCallback((_) => _removeText(t.id));
      }
      setState(() {});
    });
    ctrls[t.id] = c;
    focus[t.id] = f;
  }

  /// pone (o saca, si es null) un bloque de texto, con su campo de edición
  void _putText(String id, TextBlock? t) {
    if (t == null) {
      page.texts.remove(id);
      textTimers.remove(id)?.cancel();
      final c = ctrls.remove(id), f = focus.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        c?.dispose();
        f?.dispose();
      });
      return;
    }
    page.texts[id] = t;
    if (ctrls[id] == null) {
      _bindText(t);
    } else if (ctrls[id]!.text != t.text) {
      ctrls[id]!.text = t.text;
    }
  }

  void _removeText(String id) {
    if (!mounted) return;
    setState(() {
      page.texts.remove(id);
      textTimers.remove(id)?.cancel();
      final c = ctrls.remove(id), f = focus.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        c?.dispose();
        f?.dispose();
      });
    });
    _changed();
  }

  void _tapPage(TapUpDetails d) {
    if (ts.tool != Tool.text) return;
    final focused = focus.values.any((f) => f.hasFocus);
    if (focused) {
      FocusScope.of(context).unfocus(); // primer toque afuera: solo cierra el texto
      return;
    }
    _createTextAt(_logical(d.localPosition));
  }

  void _createTextAt(Offset p) {
    final x = p.dx.clamp(16.0, kW - 120);
    var y = max(0.0, (p.dy / kLine).floorToDouble() * kLine + 4);
    if (y % kSheetStep > kSheetH - kLine) y = (y ~/ kSheetStep + 1) * kSheetStep + 4; // en el espacio entre hojas: a la siguiente
    final t = TextBlock(newId('t'), x.roundToDouble(), y, (kW - x - 30).roundToDouble(), '');
    setState(() {
      page.texts[t.id] = t;
      _bindText(t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus[t.id]?.requestFocus());
    _changed();
  }

  void _textChanged(TextBlock t, String v) {
    t.text = v;
    final lines = '\n'.allMatches(v).length + 1 + v.length ~/ 70;
    _growIfNeeded(t.y + lines * kLine);
    textTimers[t.id]?.cancel();
    textTimers[t.id] = Timer(const Duration(milliseconds: 300), _changed);
  }

  // ---------------- UI ----------------
  void _setTool(Tool t) {
    if (t != Tool.select) _clearSel();
    setState(() => ts.tool = t);
    if (t != Tool.text) FocusScope.of(context).unfocus();
  }

  ColorScheme get cs => Theme.of(context).colorScheme;

  // ---- barra acoplable: arriba / izquierda / derecha ----
  final _editorKey = GlobalKey();
  String? _dockPreview; // mientras se arrastra la barra
  Offset? _dragPos; // dónde está el dedo (coordenadas del editor)

  Offset _editorLocal(Offset g) => (_editorKey.currentContext!.findRenderObject() as RenderBox).globalToLocal(g);

  String _dockFor(Offset global) {
    final box = _editorKey.currentContext!.findRenderObject() as RenderBox;
    final p = box.globalToLocal(global), s = box.size;
    if (p.dy < s.height * .22 && p.dx > s.width * .2 && p.dx < s.width * .8) return 'top';
    return p.dx < s.width / 2 ? 'left' : 'right';
  }

  @override
  Widget build(BuildContext context) {
    final dock = ts.dock;
    final bar = TweenAnimationBuilder<double>(
      key: ValueKey(dock),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutQuart,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: FractionalTranslation(
          translation: switch (dock) { 'left' => Offset(-(1 - t) * .5, 0), 'right' => Offset((1 - t) * .5, 0), _ => Offset(0, -(1 - t) * .5) },
          child: child,
        ),
      ),
      child: AnimatedOpacity(
        opacity: _dockPreview != null ? .3 : 1,
        duration: const Duration(milliseconds: 150),
        child: _toolbar(vertical: dock != 'top'),
      ),
    );
    final canvas = Expanded(child: _canvasArea());
    final body = dock == 'top'
        ? Column(children: [bar, canvas])
        : Row(children: dock == 'left' ? [bar, canvas] : [canvas, bar]);
    return Stack(key: _editorKey, children: [
      body,
      if (_dockPreview != null) Positioned.fill(child: IgnorePointer(child: _dockGhost(_dockPreview!))),
      if (_dragPos != null)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 60),
          left: _dragPos!.dx - (_dockPreview == 'top' ? 120 : 30),
          top: _dragPos!.dy - (_dockPreview == 'top' ? 30 : 110),
          child: IgnorePointer(child: _barGhost(_dockPreview != 'top')),
        ),
    ]);
  }

  /// mini barra que sigue al dedo mientras se mueve la barra
  Widget _barGhost(bool vertical) {
    final kids = <Widget>[
      for (final i in [Symbols.stylus, Symbols.ink_highlighter, Symbols.keyboard, Symbols.highlight_alt])
        Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 20, weight: 300, color: cs.onSurfaceVariant)),
    ];
    return AnimatedScale(
      scale: 1,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: cs.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Flex(direction: vertical ? Axis.vertical : Axis.horizontal, mainAxisSize: MainAxisSize.min, children: kids),
        ),
      ),
    );
  }

  /// zona resaltada donde va a quedar la barra al soltarla
  Widget _dockGhost(String d) {
    final zone = Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: switch (d) {
        'top' => Align(alignment: Alignment.topCenter, child: SizedBox(height: 56, width: double.infinity, child: zone)),
        'left' => Align(alignment: Alignment.centerLeft, child: SizedBox(width: 64, height: double.infinity, child: zone)),
        _ => Align(alignment: Alignment.centerRight, child: SizedBox(width: 64, height: double.infinity, child: zone)),
      },
    );
  }

  // ---- hoja nueva: tirar hacia arriba al final y mantener ----
  late final pullCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _pullDone();
    });
  double pullAccum = 0;
  int touches = 0;
  bool pullJustAdded = false;

  bool _onScrollNote(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification && n.overscroll > 0 && n.dragDetails != null && touches > 0) {
      pullAccum += n.overscroll;
      if (pullAccum > 28 && !pullCtrl.isAnimating && pullCtrl.value == 0) {
        HapticFeedback.selectionClick();
        pullCtrl.forward();
      }
    } else if (n is ScrollUpdateNotification && n.metrics.extentAfter > 4 && pullCtrl.value > 0 && !pullJustAdded) {
      _pullCancel(); // volvió a subir: se cancela
    }
    return false;
  }

  void _pullCancel() {
    pullAccum = 0;
    if (pullCtrl.value > 0 && pullCtrl.value < 1) pullCtrl.reverse();
  }

  void _pullDone() {
    HapticFeedback.mediumImpact();
    final oldH = page.h;
    setState(() {
      page.h = heightFor(sheetCount(page.h) + 1);
      pullJustAdded = true;
    });
    _changed();
    // lleva a la hoja nueva
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll.animateTo(min(scroll.position.maxScrollExtent, (oldH + kGap) * scale), duration: const Duration(milliseconds: 420), curve: Curves.easeOutQuart);
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      pullCtrl.value = 0;
      pullAccum = 0;
      setState(() => pullJustAdded = false);
    });
  }

  Widget _pullIndicator() {
    return AnimatedBuilder(
      animation: pullCtrl,
      builder: (context, _) {
        final v = pullCtrl.value;
        final visible = v > 0 || pullJustAdded;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedScale(
              scale: visible ? 1 : .8,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutQuart,
              child: Material(
                color: cs.surfaceContainerHigh,
                elevation: 3,
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: pullJustAdded ? 1 : v,
                          strokeWidth: 3,
                          strokeCap: StrokeCap.round,
                          backgroundColor: cs.outlineVariant.withValues(alpha: .5),
                          color: cs.primary,
                        ),
                        Icon(pullJustAdded ? Symbols.check : Symbols.note_add, size: 18, weight: 400, color: cs.primary),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      pullJustAdded ? 'Hoja agregada' : 'Mantené para agregar una hoja',
                      style: TextStyle(color: cs.onSurface, fontSize: 14),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- zoom con dos dedos (y candado para fijarlo) ----
  final hscroll = ScrollController();
  final _touch = <int, Offset>{};
  bool pinching = false;
  double _pinchDist0 = 1, _pinchZoom0 = 1;
  double _sheetLeft = 0;
  bool _zoomPill = false;
  Timer? _zoomPillT;
  static const _topPad = 16.0;

  void _flashZoom() {
    _zoomPillT?.cancel();
    _lpTimer?.cancel();
    setState(() => _zoomPill = true);
    _zoomPillT = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _zoomPill = false);
    });
  }

  /// cambia el zoom dejando quieto el punto [f] (coordenadas del visor)
  void _setZoom(double z, Offset? f) {
    z = z.clamp(.5, 4.0);
    if ((z - ts.zoom).abs() < .001) return;
    f ??= Offset(hscroll.hasClients ? hscroll.position.viewportDimension / 2 : 0, scroll.hasClients ? scroll.position.viewportDimension / 2 : 0);
    final s0 = scale, l0 = _sheetLeft;
    final h0 = hscroll.hasClients ? hscroll.offset : 0.0;
    final v0 = scroll.hasClients ? scroll.offset : 0.0;
    final sx = (h0 + f.dx - l0) / s0, sy = (v0 + f.dy - _topPad) / s0;
    setState(() => ts.zoom = z);
    _flashZoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hscroll.hasClients) hscroll.jumpTo((sx * scale + _sheetLeft - f!.dx).clamp(0.0, hscroll.position.maxScrollExtent));
      if (scroll.hasClients) scroll.jumpTo((sy * scale + _topPad - f!.dy).clamp(0.0, scroll.position.maxScrollExtent));
    });
  }

  final _viewportKey = GlobalKey();

  void _touchDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touches++;
    _touch[e.pointer] = e.position;
    if (_touch.length == 1 && pointer == null) {
      _lpStart = e.position;
      _lpTimer = Timer(const Duration(milliseconds: 500), _lpFire);
    } else {
      _lpCancel(); // segundo dedo: es zoom, no menú
    }
    // dos dedos = pellizco (salvo que el zoom esté fijado o se esté escribiendo con el lápiz)
    if (_touch.length == 2 && !ts.zoomLocked && pointer == null) {
      final p = _touch.values.toList();
      _pinchDist0 = max(1, (p[0] - p[1]).distance);
      _pinchZoom0 = ts.zoom;
      _pullCancel();
      setState(() => pinching = true);
    }
  }

  void _touchMove(PointerMoveEvent e) {
    if (!_touch.containsKey(e.pointer)) return;
    _touch[e.pointer] = e.position;
    if (_lpStart != null && (e.position - _lpStart!).distance > 12) _lpCancel(); // se movió: es scroll
    if (!pinching || _touch.length < 2) return;
    final p = _touch.values.take(2).toList();
    final box = _viewportKey.currentContext!.findRenderObject() as RenderBox;
    final focal = box.globalToLocal((p[0] + p[1]) / 2);
    _setZoom(_pinchZoom0 * (p[0] - p[1]).distance / _pinchDist0, focal);
  }

  void _touchUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touch.remove(e.pointer);
    touches = max(0, touches - 1);
    _lpCancel();
    if (pinching && _touch.length < 2) {
      setState(() => pinching = false);
      widget.onPrefsChanged();
    }
    if (touches == 0) _pullCancel(); // soltó antes de completar: vuelve
  }

  void _toggleZoomLock() {
    setState(() => ts.zoomLocked = !ts.zoomLocked);
    HapticFeedback.selectionClick();
    _flashZoom();
    widget.onPrefsChanged();
  }

  Widget _zoomIndicator() => IgnorePointer(
        child: AnimatedOpacity(
          opacity: _zoomPill || pinching ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Material(
            color: cs.inverseSurface.withValues(alpha: .88),
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ts.zoomLocked ? Symbols.lock : Symbols.zoom_in, size: 16, weight: 400, color: cs.onInverseSurface),
                const SizedBox(width: 6),
                Text(
                  '${(ts.zoom * 100).round()}%${ts.zoomLocked ? ' · fijo' : ''}',
                  style: TextStyle(color: cs.onInverseSurface, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _canvasArea() {
    return Container(
      color: cs.surfaceContainerLow,
      child: LayoutBuilder(builder: (context, box) {
        final vw = box.maxWidth;
        final side = vw < 700 ? 6.0 : 24.0;
        final fit = min(vw - side * 2, 1100.0);
        final sw = fit * ts.zoom;
        scale = sw / kW;
        final sheetH = page.h * scale;
        final contentW = max(vw, sw + side * 2);
        _sheetLeft = (contentW - sw) / 2;
        final noScroll = pinching ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics();
        return Stack(children: [
          Listener(
            key: _viewportKey,
            onPointerDown: _touchDown,
            onPointerMove: _touchMove,
            onPointerUp: _touchUp,
            onPointerCancel: _touchUp,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNote,
              child: ScrollConfiguration(
                // el lápiz NO scrollea: solo dedo y touchpad
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
                  scrollbars: true,
                ),
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: noScroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  child: SingleChildScrollView(
                    controller: hscroll,
                    scrollDirection: Axis.horizontal,
                    physics: noScroll,
                    child: SizedBox(
                      width: contentW,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: _topPad),
                        Padding(
                          padding: EdgeInsets.only(left: _sheetLeft),
                          child: SizedBox(key: _sheetKey, width: sw, height: sheetH, child: _sheet(Size(sw, sheetH))),
                        ),
                        SizedBox(
                          width: contentW,
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
          Positioned(left: 0, right: 0, bottom: 28, child: Center(child: _pullIndicator())),
          Positioned(left: 0, right: 0, top: 14, child: Center(child: _zoomIndicator())),
        ]);
      }),
    );
  }

  Widget _sheet(Size size) {
    final textMode = ts.tool == Tool.text;
    final r = hasSel && !moving ? selRect : null;
    return Stack(clipBehavior: Clip.none, children: [
      _sheetInput(textMode),
      if (r != null)
        Positioned(
          left: max(0.0, r.left * scale),
          top: r.top * scale > 60 ? r.top * scale - 56 : r.bottom * scale + 8,
          child: _selMenu(),
        ),
    ]);
  }

  Widget _selMenu() {
    final fg = cs.onInverseSurface;
    Widget b(IconData i, String label, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 19, weight: 300, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontSize: 14)),
            ]),
          ),
        );
    return Material(
      color: cs.inverseSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          b(Symbols.content_copy, 'Copiar', () {
            _copySel();
            _toast('Copiado');
          }),
          b(Symbols.content_cut, 'Cortar', () {
            _copySel();
            _deleteSel();
          }),
          b(Symbols.control_point_duplicate, 'Duplicar', _duplicateSel),
          b(Symbols.delete, 'Eliminar', _deleteSel),
          IconButton(onPressed: _clearSel, icon: Icon(Symbols.close, size: 19, weight: 300, color: fg.withValues(alpha: .75)), tooltip: 'Deseleccionar'),
        ]),
      ),
    );
  }

  // ---- mantener el dedo sobre la hoja: menú contextual ----
  Timer? _lpTimer;
  Offset? _lpStart;
  final _sheetKey = GlobalKey();

  void _lpCancel() {
    _lpTimer?.cancel();
    _lpTimer = null;
    _lpStart = null;
  }

  void _lpFire() {
    final g = _lpStart;
    _lpCancel();
    if (g == null || !mounted || pinching || _touch.length != 1 || pointer != null) return;
    if (scroll.hasClients && scroll.position.isScrollingNotifier.value) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(g);
    if (!(Offset.zero & box.size).contains(local)) return;
    _longPressMenu(g, _logical(local));
  }

  Future<void> _longPressMenu(Offset g, Offset p) async {
    HapticFeedback.mediumImpact();
    PopupMenuItem<String> item(String v, IconData i, String label, {bool enabled = true}) => PopupMenuItem(
          value: v,
          enabled: enabled,
          child: Row(children: [
            Icon(i, size: 20, weight: 300, color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: .3)),
            const SizedBox(width: 12),
            Text(label),
          ]),
        );
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(g.dx, g.dy, g.dx + 1, g.dy + 1),
      items: [
        item('paste', Symbols.content_paste, 'Pegar acá', enabled: ts.hasClip),
        item('text', Symbols.keyboard, 'Escribir acá'),
        item('all', Symbols.select_all, 'Seleccionar todo', enabled: page.strokes.isNotEmpty || page.texts.isNotEmpty),
        item('sheet', Symbols.note_add, 'Agregar hoja al final'),
        item('zoom100', Symbols.fit_page_width, 'Zoom al ancho de la hoja', enabled: !ts.zoomLocked && (ts.zoom - 1).abs() > .01),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'paste':
        _pasteAt(p);
      case 'text':
        _setTool(Tool.text);
        _createTextAt(p);
      case 'all':
        _setTool(Tool.select);
        setState(() {
          selS
            ..clear()
            ..addAll(page.strokes.keys);
          selT
            ..clear()
            ..addAll(page.texts.keys);
        });
        liveTick.value++;
      case 'sheet':
        setState(() => page.h = heightFor(sheetCount(page.h) + 1));
        _changed();
      case 'zoom100':
        _setZoom(1, null);
        widget.onPrefsChanged();
    }
  }

  void _pasteAt(Offset p) {
    if (!ts.hasClip) return;
    Rect? r;
    for (final s in ts.clipStrokes) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    for (final t in ts.clipTexts) {
      r = r == null ? _textRect(t) : r.expandToInclude(_textRect(t));
    }
    _insert(ts.clipStrokes, ts.clipTexts, p - r!.topLeft);
  }

  Widget _sheetInput(bool textMode) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: textMode ? _tapPage : null,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: SheetPainter(page.bg, page.h, scale))),
            // textos (solo se tocan en modo texto)
            ...page.texts.values.map((t) => _textBlock(t, textMode)),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: InkPainter(page, scale, inkVersion, () => moving ? selS : const {}), isComplex: true),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: LivePainter(_paintLive, scale, liveTick)),
              ),
            ),
          ]),
      ),
    );
  }

  Widget _textBlock(TextBlock t, bool textMode) {
    final c = ctrls[t.id], f = focus[t.id];
    if (c == null || f == null) return const SizedBox.shrink();
    final fs = kFont * scale;
    return Positioned(
      left: t.x * scale,
      top: t.y * scale,
      width: t.w * scale,
      child: IgnorePointer(
        ignoring: !textMode,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            decoration: f.hasFocus && textMode
                ? BoxDecoration(color: const Color(0x082F5BD3), border: Border.all(color: const Color(0x552F5BD3)), borderRadius: BorderRadius.circular(3))
                : selT.contains(t.id)
                    ? BoxDecoration(color: const Color(0x1A2F5BD3), borderRadius: BorderRadius.circular(3))
                    : null,
            child: TextField(
              controller: c,
              focusNode: f,
              maxLines: null,
              style: TextStyle(fontSize: fs, color: kText, height: kLine / kFont),
              strutStyle: StrutStyle(fontSize: fs, height: kLine / kFont, forceStrutHeight: true),
              decoration: const InputDecoration.collapsed(hintText: ''),
              cursorColor: kAccent,
              onChanged: (v) => _textChanged(t, v),
            ),
          ),
          if (textMode)
            Positioned(
              left: -30,
              top: 0,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  t.x = (t.x + d.delta.dx / scale).clamp(0.0, kW - 60);
                  t.y = max(0.0, t.y + d.delta.dy / scale);
                  t.w = min(t.w, kW - t.x - 10).clamp(120.0, kW);
                }),
                onPanEnd: (_) => setState(() {
                  t.y = ((t.y - 4) / kLine).roundToDouble() * kLine + 4;
                  _changed();
                }),
                child: SizedBox(
                  width: 26,
                  height: max(kLine * scale, 28),
                  child: const Icon(Symbols.drag_indicator, size: 20, color: Color(0x99777777)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  // ---------------- barra de herramientas ----------------
  void _toolTap(Tool t) {
    if (ts.tool == t && (t == Tool.pen || t == Tool.hl)) {
      _openPanel(); // tocar de nuevo la herramienta elegida abre sus opciones
      return;
    }
    _setTool(t);
    widget.onPrefsChanged();
  }

  Future<void> _openPanel() async {
    final align = switch (ts.dock) { 'left' => Alignment.centerLeft, 'right' => Alignment.centerRight, _ => Alignment.topCenter };
    await showPenPanel(context, ts, () {
      setState(() {});
      widget.onPrefsChanged();
    }, align);
    if (mounted) setState(() {});
  }

  // Barra: zonas de tamaño fijo para que nada salte al cambiar de herramienta.
  // Arriba:   [mover][menú][título ......][herramientas] | [colores][grosor] | [deshacer][rehacer][fondo][pegar]
  // Costado:  lo mismo, en columna.
  Widget _toolbar({required bool vertical}) {
    final drawing = ts.tool == Tool.pen || ts.tool == Tool.hl;
    final cur = ts.current;
    final axis = vertical ? Axis.vertical : Axis.horizontal;
    return LayoutBuilder(builder: (context, box) {
      final room = vertical ? box.maxHeight : box.maxWidth;
      final compact = room < 820;
      final nColors = compact ? 4 : 6;
      final base = ts.tool == Tool.hl ? ts.hlRecent : ts.penRecent;
      final fill = ts.tool == Tool.hl ? hlPalette : palette;
      final colors = <String>[...base];
      for (final c in fill) {
        if (colors.length >= nColors) break;
        if (!colors.contains(c)) colors.add(c);
      }
      final side = BorderSide(color: cs.outlineVariant.withValues(alpha: .6));
      final children = <Widget>[
        _grip(vertical),
        _icon(Symbols.arrow_back, 'Volver a los cuadernos', widget.onBack),
        _icon(Symbols.view_sidebar, 'Páginas del cuaderno', widget.onMenu),
        if (!vertical) const SizedBox(width: 6),
        if (!vertical)
          Expanded(
            child: compact
                ? const SizedBox()
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(text: widget.title, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: cs.onSurface)),
                      TextSpan(text: '   ${widget.subtitle}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        if (vertical) const SizedBox(height: 4),
        _toolBtn(Tool.pen, Symbols.stylus, 'Lápiz · tocá de nuevo para opciones', ts.pen),
        _toolBtn(Tool.hl, Symbols.ink_highlighter, 'Resaltador · tocá de nuevo para opciones', ts.hl),
        _toolBtn(Tool.text, Symbols.keyboard, 'Texto con teclado', null),
        _toolBtn(Tool.select, Symbols.highlight_alt, 'Seleccionar', null),
        _divider(vertical),
        AnimatedOpacity(
          opacity: drawing ? 1 : .38,
          duration: const Duration(milliseconds: 160),
          child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: [
            for (final c in colors.take(nColors)) _swatch(c, drawing && cur.color == c, vertical),
            _moreColors(vertical),
            _widthBtn(cur, vertical),
          ]),
        ),
        _divider(vertical),
        _icon(Symbols.undo, 'Deshacer', undo.isEmpty ? null : () => _undoRedo(undo, redo)),
        _icon(Symbols.redo, 'Rehacer', redo.isEmpty ? null : () => _undoRedo(redo, undo)),
        _lockBtn(),
        _bgMenu(),
        IgnorePointer(
          ignoring: !ts.hasClip,
          child: AnimatedOpacity(
            opacity: ts.hasClip ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: _icon(Symbols.content_paste, 'Pegar', _paste),
          ),
        ),
      ];
      return Container(
        width: vertical ? 60 : null,
        height: vertical ? null : 56,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(
            bottom: ts.dock == 'top' ? side : BorderSide.none,
            right: ts.dock == 'left' ? side : BorderSide.none,
            left: ts.dock == 'right' ? side : BorderSide.none,
          ),
        ),
        padding: vertical ? const EdgeInsets.symmetric(vertical: 6) : const EdgeInsets.symmetric(horizontal: 6),
        child: vertical
            ? SingleChildScrollView(child: Column(children: children))
            : Row(children: children),
      );
    });
  }

  /// agarradera para mover la barra (arrastrala a un costado o arriba)
  Widget _grip(bool vertical) => Tooltip(
        message: 'Arrastrá para mover la barra',
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            HapticFeedback.lightImpact();
            setState(() {
              _dockPreview = _dockFor(d.globalPosition);
              _dragPos = _editorLocal(d.globalPosition);
            });
          },
          onPanUpdate: (d) {
            final t = _dockFor(d.globalPosition);
            if (t != _dockPreview) HapticFeedback.selectionClick();
            setState(() {
              _dockPreview = t;
              _dragPos = _editorLocal(d.globalPosition);
            });
          },
          onPanEnd: (_) {
            final t = _dockPreview;
            setState(() {
              _dockPreview = null;
              _dragPos = null;
              if (t != null) ts.dock = t;
            });
            widget.onPrefsChanged();
          },
          onPanCancel: () => setState(() {
            _dockPreview = null;
            _dragPos = null;
          }),
          child: SizedBox(
            width: vertical ? 60 : 26,
            height: vertical ? 26 : 56,
            child: RotatedBox(
              quarterTurns: vertical ? 1 : 0,
              child: Icon(Symbols.drag_indicator, size: 18, weight: 300, color: cs.onSurfaceVariant.withValues(alpha: .6)),
            ),
          ),
        ),
      );

  Widget _lockBtn() {
    final on = ts.zoomLocked;
    return Tooltip(
      message: on ? 'Zoom fijo (${(ts.zoom * 100).round()}%) · tocá para soltarlo' : 'Fijar el zoom',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggleZoomLock,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: on ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Icon(on ? Symbols.lock : Symbols.lock_open, size: 21, weight: on ? 400 : 300, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _divider(bool vertical) => Container(
        width: vertical ? 22 : 1,
        height: vertical ? 1 : 22,
        margin: vertical ? const EdgeInsets.symmetric(vertical: 8) : const EdgeInsets.symmetric(horizontal: 8),
        color: cs.outlineVariant,
      );

  Widget _icon(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        tooltip: tip,
        icon: Icon(icon, size: 22, weight: 300, opticalSize: 24),
        color: cs.onSurfaceVariant,
        disabledColor: cs.onSurface.withValues(alpha: .28),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _toolBtn(Tool t, IconData icon, String tip, PenPreset? preset) {
    final on = ts.tool == t;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toolTap(t),
        onLongPress: preset == null
            ? null
            : () {
                _setTool(t);
                _openPanel();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutQuart,
          width: 46,
          height: 44,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: on ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: 22, weight: on ? 400 : 300, opticalSize: 24, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
            if (preset != null)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: parseColor(preset.color).withValues(alpha: max(preset.opacity, .45)),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: .6), width: .5),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// tocar un color: si estás en texto/seleccionar, vuelve al lápiz con ese color
  void _pickQuick(String c) {
    if (ts.tool != Tool.pen && ts.tool != Tool.hl) _setTool(Tool.pen);
    setState(() => ts.pickColor(c));
    widget.onPrefsChanged();
  }

  Size _slot(bool vertical) => vertical ? const Size(48, 34) : const Size(32, 44);

  Widget _swatch(String c, bool on, bool vertical) => InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _pickQuick(c),
        child: SizedBox.fromSize(
          size: _slot(vertical),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: on ? 21 : 16,
              height: on ? 21 : 16,
              padding: EdgeInsets.all(on ? 2.5 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: on ? Border.all(color: cs.primary, width: 1.5) : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: parseColor(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outline.withValues(alpha: .6), width: .8),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _moreColors(bool vertical) => Tooltip(
        message: 'Más colores',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (ts.tool != Tool.pen && ts.tool != Tool.hl) _setTool(Tool.pen);
            _openPanel();
          },
          child: SizedBox.fromSize(
            size: _slot(vertical),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [
                    Color(0xFFD9625B), Color(0xFFDDB24A), Color(0xFF5FAE78), Color(0xFF5B8FD9), Color(0xFF9B78D0), Color(0xFFD9625B),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _widthBtn(PenPreset p, bool vertical) {
    final hl = ts.tool == Tool.hl;
    final d = hl ? (p.width / 60 * 18).clamp(5.0, 18.0) : (p.width / 16 * 16).clamp(2.5, 16.0);
    return Tooltip(
      message: 'Punta, grosor y opacidad',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (ts.tool != Tool.pen && ts.tool != Tool.hl) _setTool(Tool.pen);
          _openPanel();
        },
        child: SizedBox(
          width: vertical ? 48 : 40,
          height: vertical ? 40 : 44,
          child: Center(
            child: Container(
              width: d,
              height: hl ? d * .6 : d,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant,
                shape: hl ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: hl ? BorderRadius.circular(1.5) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bgMenu() => PopupMenuButton<String>(
        tooltip: 'Fondo de la hoja',
        icon: Icon(Symbols.background_grid_small, size: 22, weight: 300, color: cs.onSurfaceVariant),
        initialValue: page.bg,
        position: PopupMenuPosition.under,
        onSelected: (v) {
          setState(() => page.bg = v);
          _changed();
        },
        itemBuilder: (_) => [
          for (final (v, i, label) in const [
            ('lined', Symbols.format_align_justify, 'Rayado'),
            ('grid', Symbols.grid_4x4, 'Cuadriculado'),
            ('dots', Symbols.grid_goldenratio, 'Puntos'),
            ('blank', Symbols.crop_portrait, 'Liso'),
          ])
            PopupMenuItem(
              value: v,
              child: Row(children: [
                Icon(i, size: 20, weight: 300, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
                if (page.bg == v) Icon(Symbols.check, size: 18, weight: 500, color: cs.primary),
              ]),
            ),
        ],
      );
}
