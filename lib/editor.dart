import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'model.dart';
import 'painters.dart';

enum Tool { pen, hl, eraser, text }

const penColors = ['#22211e', '#2f5bd3', '#d33a2c', '#1f8a4c', '#e2730b', '#7c3aed'];
const hlColors = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
const sizes = {
  'pen': [1.6, 2.6, 4.2],
  'hl': [14.0, 22.0, 32.0],
  'eraser': [8.0, 16.0, 30.0],
};
const kAccent = Color(0xFF2F5BD3);
const kPanel = Color(0xFFF6F5F1);
const kDesk = Color(0xFFECEBE6);
const kText = Color(0xFF22211E);

class _Act {
  final bool add;
  final List<Stroke> strokes;
  _Act(this.add, this.strokes);
}

/// Herramientas elegidas: viven fuera del editor para que no se pierdan al cambiar de página.
class ToolState {
  Tool tool = Tool.pen;
  final color = {'pen': penColors[0], 'hl': hlColors[0]};
  final size = {'pen': 1, 'hl': 1, 'eraser': 1};
}

class PageEditor extends StatefulWidget {
  final PageData page;
  final ToolState tools;
  final String title, subtitle;
  final VoidCallback onChanged;
  final VoidCallback onMenu;
  const PageEditor({super.key, required this.page, required this.tools, required this.title, required this.subtitle, required this.onChanged, required this.onMenu});

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
    if (mouse && e.buttons != kPrimaryMouseButton) return;
    final penButton = e.kind == PointerDeviceKind.invertedStylus || (stylus && (e.buttons & kSecondaryStylusButton) != 0);
    final tool = penButton ? Tool.eraser : ts.tool;
    if (tool == Tool.text) return;
    pointer = e.pointer;
    final p = _logical(e.localPosition);
    if (tool == Tool.eraser) {
      erased = [];
      _eraseAt(p);
      eraserAt = p;
      liveTick.value++;
      return;
    }
    final k = tool == Tool.hl ? 'hl' : 'pen';
    live = Stroke(newId('s'), k, ts.color[k]!, sizes[k]![ts.size[k]!], []);
    _addPoint(e, p);
    liveTick.value++;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != pointer) return;
    final p = _logical(e.localPosition);
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
    if (erased != null) {
      if (erased!.isNotEmpty) _pushUndo(_Act(false, erased!));
      erased = null;
      eraserAt = null;
      liveTick.value++;
      return;
    }
    final s = live;
    live = null;
    liveTick.value++;
    if (s == null || (e is PointerCancelEvent && s.n < 3)) return;
    _smooth(s);
    page.strokes[s.id] = s;
    inkVersion.value++;
    _pushUndo(_Act(true, [s]));
    _growIfNeeded(s.bounds.bottom);
    _changed();
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

  double get _eraserR => sizes['eraser']![ts.size['eraser']!];

  void _eraseAt(Offset pt) {
    final r = _eraserR;
    final hits = <Stroke>[];
    for (final s in page.strokes.values) {
      if (!s.bounds.inflate(r).contains(pt)) continue;
      final lim = r + s.w / 2, p = s.pts;
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
    final add = a.add == identical(from, redo);
    for (final s in a.strokes) {
      if (add) {
        page.strokes[s.id] = s;
      } else {
        page.strokes.remove(s.id);
      }
    }
    to.add(a);
    inkVersion.value++;
    _changed();
    setState(() {});
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
                child: CustomPaint(painter: InkPainter(page, scale, inkVersion), isComplex: true),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: LivePainter(() => live, () => eraserAt, () => _eraserR, scale, liveTick)),
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
  Widget _toolbar() {
    final k = ts.tool == Tool.hl ? 'hl' : ts.tool == Tool.eraser ? 'eraser' : 'pen';
    final colorKey = ts.tool == Tool.hl ? 'hl' : 'pen';
    final showColors = ts.tool == Tool.pen || ts.tool == Tool.hl;
    final showSizes = ts.tool != Tool.text;
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
              TextSpan(text: '  ${widget.subtitle}', style: const TextStyle(color: Color(0xFF7A776E), fontSize: 13)),
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
                  _toolBtn(Tool.pen, const Icon(Icons.edit), 'Lápiz'),
                  _toolBtn(Tool.hl, const Icon(Icons.border_color), 'Resaltador'),
                  _toolBtn(Tool.eraser, const _EraserIcon(), 'Goma'),
                  _toolBtn(Tool.text, const Icon(Icons.title), 'Texto'),
                ]),
                if (showColors) ...[
                  const SizedBox(width: 8),
                  _group([
                    for (final c in colorKey == 'hl' ? hlColors : penColors)
                      _swatch(c, ts.color[colorKey] == c, () => setState(() => ts.color[colorKey] = c)),
                  ]),
                ],
                if (showSizes) ...[
                  const SizedBox(width: 8),
                  _group([
                    for (var i = 0; i < 3; i++)
                      _sizeBtn([5.0, 9.0, 14.0][i], ts.size[k] == i, () => setState(() => ts.size[k] = i)),
                  ]),
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

  Widget _toolBtn(Tool t, Widget icon, String tip) {
    final on = ts.tool == t;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _setTool(t),
        child: Container(
          width: 44,
          height: 40,
          decoration: on
              ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 2, offset: Offset(0, 1))])
              : null,
          child: IconTheme(data: IconThemeData(color: on ? kAccent : kText, size: 22), child: Center(child: icon)),
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

  Widget _sizeBtn(double dot, bool on, VoidCallback tap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tap,
        child: Container(
          width: 38,
          height: 40,
          alignment: Alignment.center,
          decoration: on ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)) : null,
          child: Container(width: dot, height: dot, decoration: BoxDecoration(color: on ? kAccent : kText, shape: BoxShape.circle)),
        ),
      );
}

class _EraserIcon extends StatelessWidget {
  const _EraserIcon();
  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? kText;
    return CustomPaint(size: const Size(22, 22), painter: _EraserPainter(color));
  }
}

class _EraserPainter extends CustomPainter {
  final Color color;
  _EraserPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    c.save();
    c.translate(s.width / 2, s.height / 2 - 1);
    c.rotate(-pi / 4);
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -5, 18, 10), const Radius.circular(2));
    c.drawRRect(r, p);
    c.drawLine(const Offset(-2, -5), const Offset(-2, 5), p);
    c.restore();
    c.drawLine(Offset(s.width * .3, s.height - 2), Offset(s.width - 2, s.height - 2), p);
  }

  @override
  bool shouldRepaint(_EraserPainter o) => o.color != color;
}
