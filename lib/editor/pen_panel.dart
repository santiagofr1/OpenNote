import 'dart:math';
import 'dart:ui' show Vertices, VertexMode;

import 'package:flutter/material.dart';

import '../domain/domain.dart';
import '../rendering/stroke_painter.dart';
import '../theme/colors.dart';

/// Trazo de muestra (una ola con presión variable) para previsualizar una punta.
Stroke _sampleStroke(String tip, String color, double w, double o, Size size, [PaintParams? pp]) {
  final pts = <double>[];
  if (pp != null || isPaint(tip)) {
    // la pintura se muestra en una franja recta (con las puntas a la vista)
    final x0 = w * .4 + 6;
    for (var i = 0; i < 40; i++) {
      pts.addAll([x0 + (size.width - 2 * x0) * i / 39, size.height / 2, .5]);
    }
    return Stroke('preview', tip, color, w, pts, o, pp);
  }
  const n = 60;
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    final x = 8 + t * (size.width - 16);
    final y = size.height / 2 + sin(t * pi * 2) * size.height * .28;
    pts.addAll([x, y, .25 + .7 * sin(t * pi)]);
  }
  return Stroke('preview', tip, color, w, pts, o);
}

class _SamplePainter extends CustomPainter {
  final String tip, color;
  final double w, o;
  final PaintParams? pp;
  _SamplePainter(this.tip, this.color, this.w, this.o, [this.pp]);
  @override
  void paint(Canvas c, Size size) => paintStroke(c, _sampleStroke(tip, color, w, o, size, pp));
  @override
  bool shouldRepaint(_SamplePainter x) => x.tip != tip || x.color != color || x.w != w || x.o != o || x.pp != pp;
}

/// Opciones del lápiz, del resaltador o de la pintura (según la herramienta actual): punta, grosor, opacidad,
/// color y goma. [align]: del lado de la barra. [onChange] se llama en cada cambio.
/// Al cerrarse, el color elegido entra a "recientes" y se avisa con [onChange]. Va después del cierre y no en el `dispose`
/// del panel: ahí el árbol está bloqueado y el `setState` del editor tira una excepción.
Future<void> showPenPanel(BuildContext context, ToolState ts, VoidCallback onChange, [Alignment align = Alignment.topCenter]) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black12,
    builder: (ctx) => Align(
      alignment: align,
      child: Padding(
        padding: align == Alignment.topCenter
            ? const EdgeInsets.only(top: 64)
            : align == Alignment.centerLeft
                ? const EdgeInsets.only(left: 70)
                : const EdgeInsets.only(right: 70),
        child: Material(
          color: Theme.of(ctx).colorScheme.surfaceContainerLow,
          elevation: 12,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(ctx).size.height - 90),
            child: ts.tool == Tool.paint ? _PaintPanel(ts: ts, onChange: onChange) : _PenPanel(ts: ts, onChange: onChange),
          ),
        ),
      ),
    ),
  ).then((_) {
    ts.pickColor(ts.current.color);
    onChange();
  });
}

/// Rótulo y fila con slider que comparten los paneles.
mixin _PanelParts<T extends StatefulWidget> on State<T> {
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
      );

  Widget _sliderRow(String label, String value, Widget slider) => Row(children: [
        SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
        Expanded(child: slider),
        SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
      ]);
}

class _PenPanel extends StatefulWidget {
  final ToolState ts;
  final VoidCallback onChange;
  const _PenPanel({required this.ts, required this.onChange});
  @override
  State<_PenPanel> createState() => _PenPanelState();
}

class _PenPanelState extends State<_PenPanel> with _PanelParts<_PenPanel> {
  ToolState get ts => widget.ts;
  bool custom = false;
  late HSVColor hsv = HSVColor.fromColor(parseColor(ts.current.color));

  bool get isHl => ts.tool == Tool.hl;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = ts.current;
    final minW = isHl ? 6.0 : .6, maxW = isHl ? 60.0 : 16.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isHl ? 'Resaltador' : 'Lápiz', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        if (!isHl) ...[
          _label('Punta'),
          Row(children: [for (final (id, name) in tips) _tipCell(p, id, name)]),
          const SizedBox(height: 10),
          const SizedBox(height: 14),
        ],

        // vista previa con los valores actuales
        Container(
          height: 64,
          decoration: BoxDecoration(color: const Color(0xFFFFFEFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCD9D0))),
          child: CustomPaint(painter: _SamplePainter(p.tip, p.color, p.width, p.opacity), size: Size.infinite),
        ),
        const SizedBox(height: 10),

        _sliderRow('Grosor', p.width.toStringAsFixed(p.width < 10 ? 1 : 0), Slider(
          value: p.width.clamp(minW, maxW),
          min: minW,
          max: maxW,
          onChanged: (v) => _set(() => p.width = (v * 10).round() / 10),
        )),
        _sliderRow('Opacidad', '${(p.opacity * 100).round()}%', Slider(
          value: p.opacity,
          min: .1,
          max: 1,
          onChanged: (v) => _set(() => p.opacity = (v * 100).round() / 100),
        )),
        const SizedBox(height: 6),

        _label('Color'),
        if (isHl)
          Wrap(spacing: 6, runSpacing: 6, children: [for (final c in hlPalette) _swatch(c, c == p.color)])
        else ...[
          // grises arriba; abajo cada columna es una familia, de oscuro a claro
          Wrap(spacing: 6, children: [for (final c in palette.take(7)) _swatch(c, c == p.color)]),
          const SizedBox(height: 8),
          for (var tone = 0; tone < 4; tone++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, children: [
                for (var fam = 0; fam < 10; fam++) _swatch(palette[7 + fam * 4 + tone], palette[7 + fam * 4 + tone] == p.color),
              ]),
            ),
        ],
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => setState(() {
            custom = !custom;
            hsv = HSVColor.fromColor(parseColor(p.color));
          }),
          icon: Icon(custom ? Icons.expand_less : Icons.palette_outlined, size: 18),
          label: const Text('Color personalizado'),
        ),
        if (custom) ...[
          _GradientBar(
            colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
            value: hsv.hue / 360,
            onChanged: (v) => _custom(hsv.withHue(v * 360)),
          ),
          const SizedBox(height: 10),
          _GradientBar(
            colors: [hsv.withSaturation(0).toColor(), hsv.withSaturation(1).toColor()],
            value: hsv.saturation,
            onChanged: (v) => _custom(hsv.withSaturation(v)),
          ),
          const SizedBox(height: 10),
          _GradientBar(
            colors: [Colors.black, hsv.withValue(1).toColor()],
            value: hsv.value,
            onChanged: (v) => _custom(hsv.withValue(v)),
          ),
        ],

        if (!isHl) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _label('Goma (apretá el botón del lápiz)'),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(['Chica', 'Mediana', 'Grande'][i]),
                  selected: ts.eraserSize == i,
                  onSelected: (_) => _set(() => ts.eraserSize = i),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  /// Una punta de la lista con su muestra.
  Widget _tipCell(PenPreset p, String id, String name) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => _set(() => p.tip = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            color: p.tip == id ? scheme.surfaceContainerHighest : scheme.onSurface.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.tip == id ? scheme.primary : Colors.transparent, width: 1.5),
          ),
          child: Column(children: [
            SizedBox(
              height: 34,
              width: double.infinity,
              child: CustomPaint(painter: _SamplePainter(id, p.color, id == 'fine' ? 2.5 : 3.2, 1)),
            ),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 11.5, color: p.tip == id ? scheme.primary : scheme.onSurface), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  void _custom(HSVColor c) {
    setState(() => hsv = c);
    final hex = _hex(c.toColor());
    _set(() => ts.current.color = hex);
  }

  Widget _swatch(String c, bool on) => GestureDetector(
        onTap: () => _set(() {
          ts.pickColor(c);
          hsv = HSVColor.fromColor(parseColor(c));
        }),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: parseColor(c),
            shape: BoxShape.circle,
            border: Border.all(color: on ? Colors.white : const Color(0x22000000), width: on ? 3 : 1),
            boxShadow: on ? const [BoxShadow(color: kAccent, spreadRadius: 2)] : null,
          ),
        ),
      );
}

/// Vértices de una forma suelta (para la muestra de las celdas).
class _VertSink implements ShapeSink {
  final pos = <Offset>[], cols = <Color>[], idx = <int>[];
  final Color color;
  _VertSink(this.color);
  @override
  int get count => pos.length;
  @override
  int v(double x, double y, [int c = 0]) {
    pos.add(Offset(x, y));
    cols.add(color);
    return pos.length - 1;
  }

  @override
  void tri(int a, int b, int c) => idx..add(a)..add(b)..add(c);
}

/// Una forma de la pintura dibujada sola (en la celda del panel).
class _ShapePainter extends CustomPainter {
  final String shape;
  final Color color;
  _ShapePainter(this.shape, this.color);
  @override
  void paint(Canvas c, Size size) {
    final sink = _VertSink(color);
    paintShape(sink, shape, size.width / 2, size.height / 2, size.shortestSide / 2 - 1, 1.2, 0xFF000000);
    if (sink.idx.isEmpty) return;
    c.drawVertices(Vertices(VertexMode.triangles, sink.pos, colors: sink.cols, indices: sink.idx), BlendMode.dst, Paint());
  }

  @override
  bool shouldRepaint(_ShapePainter x) => x.shape != shape || x.color != color;
}

/// Panel de la pintura: forma, fondo, ancho, opacidad, brillo y formitas, con vista previa de la franja.
class _PaintPanel extends StatefulWidget {
  final ToolState ts;
  final VoidCallback onChange;
  const _PaintPanel({required this.ts, required this.onChange});
  @override
  State<_PaintPanel> createState() => _PaintPanelState();
}

class _PaintPanelState extends State<_PaintPanel> with _PanelParts<_PaintPanel> {
  ToolState get ts => widget.ts;
  PenPreset get p => ts.paint;
  PaintParams get pp => ts.paintParams;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }

  void _pp({double? glitter, double? density, double? size, String? shapeColor, bool autoColor = false}) => _set(() {
        ts.paintParams = PaintParams(
          glitter: glitter ?? pp.glitter,
          density: density ?? pp.density,
          size: size ?? pp.size,
          shapeColor: autoColor ? null : (shapeColor ?? pp.shapeColor),
        );
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final none = p.tip == 'paint-none';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pintura', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          key: const Key('paintPreview'),
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFFFFFEFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCD9D0))),
          child: CustomPaint(painter: _SamplePainter(p.tip, p.color, p.width, p.opacity, pp), size: Size.infinite),
        ),
        const SizedBox(height: 12),
        _label('Formas'),
        // grilla de formas (el panel entero hace scroll)
        LayoutBuilder(builder: (context, box) {
          final cell = (box.maxWidth - 6 * 4) / 5; // 5 por fila
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, name) in paintShapes)
              GestureDetector(
                key: Key(id),
                onTap: () => _set(() => p.tip = id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: cell,
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                  decoration: BoxDecoration(
                    color: p.tip == id ? scheme.surfaceContainerHighest : scheme.onSurface.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.tip == id ? scheme.primary : Colors.transparent, width: 1.5),
                  ),
                  child: Column(children: [
                    SizedBox(height: 30, width: 30, child: CustomPaint(painter: _ShapePainter(id.substring(6), scheme.onSurface.withValues(alpha: .75)))),
                    const SizedBox(height: 3),
                    Text(name, style: TextStyle(fontSize: 10, color: p.tip == id ? scheme.primary : scheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 14),
        _label('Fondo'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in [...paintPalette, ...ts.paintRecent.where((c) => !paintPalette.contains(c))]) _dot(c, c == p.color, () => _set(() => ts.pickColor(c))),
        ]),
        const SizedBox(height: 10),
        _sliderRow('Ancho', p.width.round().toString(), Slider(
          value: p.width.clamp(16.0, 70.0),
          min: 16,
          max: 70,
          onChanged: (v) => _set(() => p.width = v.roundToDouble()),
        )),
        _sliderRow('Opacidad', '${(p.opacity * 100).round()}%', Slider(
          value: p.opacity.clamp(.2, 1.0),
          min: .2,
          max: 1,
          onChanged: (v) => _set(() => p.opacity = (v * 100).round() / 100),
        )),
        const Divider(height: 20),
        Row(children: [
          Expanded(child: _label('Brillo')),
          Switch(
            key: const Key('glitterSwitch'),
            value: pp.glitter > 0,
            onChanged: (on) => _pp(glitter: on ? .5 : 0),
          ),
        ]),
        _sliderRow('Cantidad', '${(pp.glitter * 100).round()}%', Slider(
          value: pp.glitter,
          onChanged: (v) => _pp(glitter: (v * 100).round() / 100),
        )),
        const Divider(height: 20),
        _label('Formitas'),
        Opacity(
          opacity: none ? .4 : 1,
          child: IgnorePointer(
            ignoring: none,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                // "Auto": el color de cada forma (blanco, fondo aclarado, dorado)
                GestureDetector(
                  onTap: () => _pp(autoColor: true),
                  child: Container(
                    key: const Key('shapeColor-auto'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: pp.shapeColor == null ? kAccent : const Color(0x33000000), width: pp.shapeColor == null ? 2 : 1),
                    ),
                    child: const Text('Auto', style: TextStyle(fontSize: 12)),
                  ),
                ),
                for (final c in paintShapeColors) _dot(_shapeSwatch(c), c == pp.shapeColor, () => _pp(shapeColor: c), key: Key('shapeColor-$c')),
                for (final c in ts.penRecent.take(4).where((c) => !paintShapeColors.contains(c)))
                  _dot(c, c == pp.shapeColor, () => _pp(shapeColor: c)),
              ]),
              const SizedBox(height: 6),
              _sliderRow('Cantidad', '${(pp.density * 100).round()}%', Slider(
                value: pp.density,
                onChanged: (v) => _pp(density: (v * 100).round() / 100),
              )),
              _sliderRow('Tamaño', '${(pp.size * 100).round()}%', Slider(
                value: pp.size,
                onChanged: (v) => _pp(size: (v * 100).round() / 100),
              )),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Color para mostrar de una opción de forma ('light' / 'dark' salen del fondo).
  String _shapeSwatch(String c) {
    if (c != 'light' && c != 'dark') return c;
    final bg = parseColor(p.color);
    final t = c == 'light' ? Color.lerp(bg, Colors.white, .6)! : Color.lerp(bg, Colors.black, .35)!;
    return '#${(t.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  Widget _dot(String c, bool on, VoidCallback onTap, {Key? key}) => GestureDetector(
        onTap: onTap,
        child: Container(
          key: key ?? Key('paint-${c.substring(1)}'),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: parseColor(c),
            shape: BoxShape.circle,
            border: Border.all(color: on ? Colors.white : const Color(0x22000000), width: on ? 3 : 1),
            boxShadow: on ? const [BoxShadow(color: kAccent, spreadRadius: 2)] : null,
          ),
        ),
      );
}

/// Barra con degradé que se arrastra (para tono, saturación, brillo)
class _GradientBar extends StatelessWidget {
  final List<Color> colors;
  final double value;
  final ValueChanged<double> onChanged;
  const _GradientBar({required this.colors, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      void at(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0));
      return GestureDetector(
        onTapDown: (d) => at(d.localPosition),
        onHorizontalDragUpdate: (d) => at(d.localPosition),
        child: SizedBox(
          height: 30,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
            Container(
              height: 22,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), gradient: LinearGradient(colors: colors)),
            ),
            Positioned(
              left: (value * w - 13).clamp(-2.0, w - 24),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
