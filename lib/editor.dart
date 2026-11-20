import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
  final VoidCallback onChanged, onPrefsChanged, onMenu;
  const PageEditor({super.key, required this.page, required this.tools, required this.title, required this.subtitle, required this.onChanged, required this.onPrefsChanged, required this.onMenu});

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
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
      setState(() => page.h = (y ~/ kSheetH + 2) * kSheetH);
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
    final p = _logical(d.localPosition);
    final x = p.dx.clamp(16.0, kW - 120);
    final y = max(0.0, (p.dy / kLine).floorToDouble() * kLine + 4);
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

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _toolbar(),
      const Divider(height: 1, color: Color(0xFFDCD9D0)),
      Expanded(child: _canvasArea()),
    ]);
  }

  Widget _canvasArea() {
    return Container(
      color: kDesk,
      child: LayoutBuilder(builder: (context, box) {
        final sw = min(box.maxWidth - (box.maxWidth < 700 ? 12 : 48), 1100.0);
        scale = sw / kW;
        final sheetH = page.h * scale;
        return ScrollConfiguration(
          // el lápiz NO scrollea: solo dedo y touchpad
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
            scrollbars: true,
          ),
          child: SingleChildScrollView(
            controller: scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(children: [
                Center(
                  child: Container(
                    width: sw,
                    height: sheetH,
                    decoration: const BoxDecoration(boxShadow: [
                      BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1)),
                      BoxShadow(color: Color(0x10000000), blurRadius: 24, offset: Offset(0, 6)),
                    ]),
                    child: _sheet(Size(sw, sheetH)),
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => page.h += kSheetH);
                    _changed();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Hoja'),
                ),
                const SizedBox(height: 60),
              ]),
            ),
          ),
        );
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
    Widget b(IconData i, String label, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 19, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ]),
          ),
        );
    return Material(
      color: const Color(0xFF2B2A27),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          b(Icons.content_copy, 'Copiar', () {
            _copySel();
            _toast('Copiado');
          }),
          b(Icons.content_cut, 'Cortar', () {
            _copySel();
            _deleteSel();
          }),
          b(Icons.control_point_duplicate, 'Duplicar', _duplicateSel),
          b(Icons.delete_outline, 'Eliminar', _deleteSel),
          IconButton(onPressed: _clearSel, icon: const Icon(Icons.close, size: 19, color: Colors.white70), tooltip: 'Deseleccionar'),
        ]),
      ),
    );
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
                  child: const Icon(Icons.drag_indicator, size: 20, color: Color(0x99777777)),
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
    await showPenPanel(context, ts, () {
      setState(() {});
      widget.onPrefsChanged();
    });
    if (mounted) setState(() {});
  }

  Widget _toolbar() {
    final showColors = ts.tool == Tool.pen || ts.tool == Tool.hl;
    final cur = ts.current;
    return Container(
      color: kPanel,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(children: [
        IconButton(onPressed: widget.onMenu, icon: const Icon(Icons.menu), tooltip: 'Cuadernos'),
        const SizedBox(width: 4),
        Flexible(
          flex: 2,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '  ${widget.subtitle}', style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 5,
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [
                _group([
                  _toolBtn(Tool.pen, Icons.edit, 'Lápiz (tocá de nuevo para opciones)', ts.pen),
                  _toolBtn(Tool.hl, Icons.border_color, 'Resaltador (tocá de nuevo para opciones)', ts.hl),
                  _toolBtn(Tool.text, Icons.title, 'Texto', null),
                  _toolBtn(Tool.select, Icons.highlight_alt, 'Seleccionar', null),
                ]),
                if (ts.tool == Tool.select && ts.hasClip) ...[
                  const SizedBox(width: 8),
                  _group([IconButton(onPressed: _paste, icon: const Icon(Icons.content_paste), tooltip: 'Pegar')]),
                ],
                if (showColors) ...[
                  const SizedBox(width: 8),
                  _group([
                    for (final c in ts.recent)
                      _swatch(c, cur.color == c, () {
                        setState(() => ts.pickColor(c));
                        widget.onPrefsChanged();
                      }),
                    _moreColors(),
                  ]),
                  const SizedBox(width: 8),
                  _group([_widthBtn(cur)]),
                ],
                const SizedBox(width: 8),
                _group([
                  IconButton(onPressed: undo.isEmpty ? null : () => _undoRedo(undo, redo), icon: const Icon(Icons.undo), tooltip: 'Deshacer'),
                  IconButton(onPressed: redo.isEmpty ? null : () => _undoRedo(redo, undo), icon: const Icon(Icons.redo), tooltip: 'Rehacer'),
                ]),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: 'Fondo',
                  icon: const Icon(Icons.wallpaper),
                  initialValue: page.bg,
                  onSelected: (v) {
                    setState(() => page.bg = v);
                    _changed();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'lined', child: Text('Rayado')),
                    PopupMenuItem(value: 'grid', child: Text('Cuadriculado')),
                    PopupMenuItem(value: 'dots', child: Text('Puntos')),
                    PopupMenuItem(value: 'blank', child: Text('Liso')),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _group(List<Widget> children) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: const Color(0x08000000), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _toolBtn(Tool t, IconData icon, String tip, PenPreset? preset) {
    final on = ts.tool == t;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toolTap(t),
        onLongPress: preset == null ? null : () {
          _setTool(t);
          _openPanel();
        },
        child: Container(
          width: 48,
          height: 40,
          decoration: on
              ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 2, offset: Offset(0, 1))])
              : null,
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: 22, color: on ? kAccent : kText),
            // rayita con el color actual de la herramienta
            if (preset != null)
              Positioned(
                bottom: 4,
                child: Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(color: parseColor(preset.color).withValues(alpha: max(preset.opacity, .35)), borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _swatch(String c, bool on, VoidCallback tap) => InkWell(
        customBorder: const CircleBorder(),
        onTap: tap,
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: parseColor(c),
              shape: BoxShape.circle,
              border: on ? Border.all(color: Colors.white, width: 2.5) : null,
              boxShadow: on ? const [BoxShadow(color: kAccent, spreadRadius: 2)] : const [BoxShadow(color: Color(0x33000000), spreadRadius: .5)],
            ),
          ),
        ),
      );

  Widget _moreColors() => Tooltip(
        message: 'Más colores',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openPanel,
          child: Container(
            width: 36,
            height: 40,
            alignment: Alignment.center,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Color(0xFFEF4444), Color(0xFFFACC15), Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFA855F7), Color(0xFFEF4444),
                ]),
              ),
            ),
          ),
        ),
      );

  /// muestra grosor y opacidad actuales; abre el panel
  Widget _widthBtn(PenPreset p) {
    final hl = ts.tool == Tool.hl;
    final d = hl ? (p.width / 60 * 22).clamp(6.0, 22.0) : (p.width / 16 * 20).clamp(3.0, 20.0);
    return Tooltip(
      message: 'Punta, grosor y opacidad',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openPanel,
        child: SizedBox(
          width: 44,
          height: 40,
          child: Center(
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: parseColor(p.color).withValues(alpha: p.opacity),
                shape: hl ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: hl ? BorderRadius.circular(2) : null,
                border: Border.all(color: const Color(0x22000000)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
