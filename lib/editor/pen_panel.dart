import 'dart:math';
import 'dart:ui' show Vertices, VertexMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../domain/domain.dart';
import '../l10n/l10n.dart';
import '../rendering/stroke_painter.dart';
import '../theme/colors.dart';
import 'color_chooser.dart';
import 'eyedropper.dart';

/// Trazo de muestra (una ola con presión variable) para previsualizar una punta.
Stroke _sampleStroke(String tip, String color, double w, double o, Size size, [PaintParams? pp]) {
  final pts = <double>[];
  if (pp != null || isPaint(tip)) {
    // la pintura se muestra en una S suave (con las puntas a la vista) que deja ver cómo toma las curvas
    final x0 = w * .4 + 6;
    final amp = max(0.0, (size.height - w * .9) / 2 - 2);
    for (var i = 0; i < 60; i++) {
      final t = i / 59;
      pts.addAll([x0 + (size.width - 2 * x0) * t, size.height / 2 + sin(t * 2 * pi) * amp, .5]);
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

/// Opciones del lápiz, del resaltador o del Decorador (pintura) (según la herramienta actual): punta, grosor, opacidad,
/// color y goma. [align]: del lado de la barra. [onChange] se llama en cada cambio.
/// Al cerrarse, el color elegido entra a "recientes" y se avisa con [onChange]. Va después del cierre y no en el `dispose`
/// del panel: ahí el árbol está bloqueado y el `setState` del editor tira una excepción.
/// Devuelve el destino del cuentagotas si se lo tocó (el panel se cierra y el editor pone el modo cuentagotas), o null.
Future<EyeTarget?> showPenPanel(BuildContext context, ToolState ts, VoidCallback onChange,
    {Alignment align = Alignment.topCenter}) {
  return showDialog<EyeTarget>(
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
            child: ts.tool == Tool.paint
                ? _PaintPanel(ts: ts, onChange: onChange)
                : ts.tool == Tool.shape
                    ? _ShapePanel(ts: ts, onChange: onChange)
                    : _PenPanel(ts: ts, onChange: onChange),
          ),
        ),
      ),
    ),
  ).then((target) {
    onChange();
    return target;
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

  /// Favoritos: tocar uno lo elige (la rueda, el hex y el cuentagotas lo editan); "+" suma uno; mantener apretado
  /// abre el menú para borrarlo. [set] aplica el cambio y avisa.
  Widget _favSection(ToolState ts, void Function(VoidCallback) set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context.l10n.penFavorites),
          Wrap(children: [
            for (final (i, c) in ts.favorites.indexed)
              Builder(builder: (dotContext) => FavoriteDot(
                    key: ValueKey('panelFav-$i'),
                    color: c,
                    selected: ts.favSel == i,
                    onTap: () => set(() => ts.useFavorite(i)),
                    onLongPress: ts.favorites.length > 1 ? () => _favMenu(dotContext, ts, i, set) : null,
                  )),
            if (ts.favorites.length < ToolState.kFavMax)
              AddFavoriteDot(
                key: const ValueKey('panelFavAdd'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  set(() => ts.addFavorite());
                },
              ),
          ]),
          const SizedBox(height: 2),
          Text(context.l10n.penFavHelp, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  /// Menú del favorito [i] (anclado a su muestra) con la única opción de borrarlo.
  Future<void> _favMenu(BuildContext dotContext, ToolState ts, int i, void Function(VoidCallback) set) async {
    HapticFeedback.selectionClick();
    final box = dotContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(dotContext).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(box.localToGlobal(Offset.zero, ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
      Offset.zero & overlay.size,
    );
    final del = await showMenu<bool>(
      context: dotContext,
      position: pos,
      items: [
        PopupMenuItem<bool>(
          key: const ValueKey('panelFavDelete'),
          value: true,
          child: Row(children: [const Icon(Icons.delete_outline, size: 20), const SizedBox(width: 10), Text(context.l10n.penFavDelete)]),
        ),
      ],
    );
    if (del == true && mounted) set(() => ts.removeFavorite(i));
  }
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
  bool get isHl => ts.tool == Tool.hl;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }

  @override
  Widget build(BuildContext context) {
    final p = ts.current;
    final minW = isHl ? 6.0 : .6, maxW = isHl ? 60.0 : 16.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isHl ? context.l10n.penPanelHighlighter : context.l10n.penPanelPencil, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        if (!isHl) ...[
          _label(context.l10n.penTip),
          // las puntas van de a 4 por fila (con 11 no entran en una)
          for (var i = 0; i < tips.length; i += 4)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(children: [
                for (var j = i; j < i + 4; j++)
                  if (j < tips.length) _tipCell(p, tips[j].$1, tips[j].$2(context.l10n)) else const Expanded(child: SizedBox()),
              ]),
            ),
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

        _sliderRow(context.l10n.penWidth, p.width.toStringAsFixed(p.width < 10 ? 1 : 0), Slider(
          value: p.width.clamp(minW, maxW),
          min: minW,
          max: maxW,
          onChanged: (v) => _set(() => p.width = (v * 10).round() / 10),
        )),
        _sliderRow(context.l10n.penOpacity, '${(p.opacity * 100).round()}%', Slider(
          value: p.opacity,
          min: .1,
          max: 1,
          onChanged: (v) => _set(() => p.opacity = (v * 100).round() / 100),
        )),
        const SizedBox(height: 6),

        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context.l10n.penSmartShapes),
              Text(context.l10n.penSmartShapesHint,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          Switch(key: const Key('shapeSnapSwitch'), value: ts.shapeSnap, onChanged: (v) => _set(() => ts.shapeSnap = v)),
        ]),
        const SizedBox(height: 6),

        _favSection(ts, (f) => _set(f)),
        const SizedBox(height: 12),
        ColorChooser(
          color: p.color,
          onPick: (hex, {required fromWheel}) => _set(() => ts.setColor(hex)),
          onEyedropper: () => Navigator.of(context).pop(EyeTarget.tool),
        ),

        if (!isHl) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _label(context.l10n.penEraser),
          Wrap(runSpacing: 6, children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text([context.l10n.penEraserSmall, context.l10n.penEraserMedium, context.l10n.penEraserLarge][i]),
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
        key: Key('tip-$id'),
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
              child: CustomPaint(painter: _SamplePainter(id, p.color, id == 'fine' ? 2.5 : (id == 'neon' ? 2.2 : 3.2), 1)),
            ),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 11.5, color: p.tip == id ? scheme.primary : scheme.onSurface), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

/// Opciones de la herramienta Formas: qué forma, relleno con color y pegar a la cuadrícula. El borde usa el lápiz.
class _ShapePanel extends StatefulWidget {
  final ToolState ts;
  final VoidCallback onChange;
  const _ShapePanel({required this.ts, required this.onChange});
  @override
  State<_ShapePanel> createState() => _ShapePanelState();
}

class _ShapePanelState extends State<_ShapePanel> with _PanelParts<_ShapePanel> {
  ToolState get ts => widget.ts;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.shapesTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [for (final (id, name) in shapeKinds) _kindCell(cs, id, name(context.l10n))]),
        const SizedBox(height: 14),
        _label(context.l10n.shapesBorder),
        Text(context.l10n.shapesBorderHint, style: sub),
        const SizedBox(height: 8),
        Wrap(children: [for (final (i, c) in ts.penFav.indexed) ColorDot(key: Key('shapePen-${c.substring(1)}'), color: c, selected: ts.penFavSel == i, onTap: () => _set(() => ts.useFavorite(i)))]),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: _label(context.l10n.shapesFill)),
          Switch(key: const Key('shapeFillSwitch'), value: ts.shapeFill, onChanged: (v) => _set(() => ts.shapeFill = v)),
        ]),
        if (!shapeFillable(ts.shapeKind)) Text(context.l10n.shapesNoFill, style: sub),
        if (ts.shapeFill) ...[
          const SizedBox(height: 6),
          ColorChooser(
            color: ts.shapeFillColor,
            onPick: (hex, {required fromWheel}) => _set(() => ts.shapeFillColor = hex),
            onEyedropper: () => Navigator.of(context).pop(EyeTarget.shapeFill),
          ),
        ],
        const Divider(height: 24),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context.l10n.shapesSnapGrid),
              Text(context.l10n.shapesSnapGridHint, style: sub),
            ]),
          ),
          Switch(key: const Key('shapeGridSwitch'), value: ts.shapeGrid, onChanged: (v) => _set(() => ts.shapeGrid = v)),
        ]),
      ]),
    );
  }

  Widget _kindCell(ColorScheme cs, String id, String name) {
    final on = ts.shapeKind == id;
    return Expanded(
      child: GestureDetector(
        key: Key('shapeKind-$id'),
        onTap: () => _set(() => ts.shapeKind = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
          decoration: BoxDecoration(
            color: on ? cs.surfaceContainerHighest : cs.onSurface.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? cs.primary : Colors.transparent, width: 1.5),
          ),
          child: Column(children: [
            SizedBox(height: 30, width: 30, child: CustomPaint(painter: _KindIconPainter(id, on ? cs.primary : cs.onSurface))),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 10.5, color: on ? cs.primary : cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

/// Dibujito de una forma del panel (las mismas que genera [exactShapePoints], en un cuadro de 30 x 30).
class _KindIconPainter extends CustomPainter {
  final String kind;
  final Color color;
  _KindIconPainter(this.kind, this.color);

  @override
  void paint(Canvas c, Size size) {
    final mid = size.center(Offset.zero);
    final pts = kind == 'circle'
        ? exactShapePoints(kind, mid, mid + Offset(size.width / 2 - 4, 0))
        : exactShapePoints(kind, const Offset(4, 4), Offset(size.width - 4, size.height - 4));
    final path = Path();
    for (var i = 0; i < pts.length; i += 3) {
      i == 0 ? path.moveTo(pts[i], pts[i + 1]) : path.lineTo(pts[i], pts[i + 1]);
    }
    c.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_KindIconPainter o) => o.kind != kind || o.color != color;
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

/// Panel del Decorador (pintura): arriba, fija, la vista previa de la franja; abajo (con scroll) el tipo de trazo, el
/// ancho y los tres componentes activables: fondo, brillo y formas (al menos uno queda prendido).
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

  void _pp(PaintParams Function(PaintParams) f) => _set(() => ts.paintParams = f(pp));

  bool get _glitterOn => pp.glitter > 0;

  /// ¿Se puede apagar el componente? Solo si queda otro prendido.
  bool _canOff(bool bg, bool glitter, bool shapes) => [pp.bg && bg, _glitterOn && glitter, pp.shapes && shapes].any((x) => x);

  Widget _switchRow(String label, Key key, bool on, bool canOff, ValueChanged<bool> set) => Row(children: [
        Expanded(child: _label(label)),
        Switch(key: key, value: on, onChanged: on && !canOff ? null : set),
      ]);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      // fijo: siempre a la vista, aunque se scrolleen los ajustes
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.l10n.paintPanelTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            key: const Key('paintPreview'),
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: const Color(0xFFFFFEFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCD9D0))),
            child: CustomPaint(painter: _SamplePainter(p.tip, p.color, p.width, p.opacity, pp), size: Size.infinite),
          ),
        ]),
      ),
      const Divider(height: 1),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(context.l10n.paintStroke),
            Row(children: [for (final (id, name) in paintStyles) _styleCell(scheme, id, name(context.l10n))]),
            const SizedBox(height: 10),
            _sliderRow(context.l10n.paintWidth, p.width.round().toString(), Slider(
              value: p.width.clamp(16.0, 70.0),
              min: 16,
              max: 70,
              onChanged: (v) => _set(() => p.width = v.roundToDouble()),
            )),
            const Divider(height: 20),
            _switchRow(context.l10n.paintBackground, const Key('paintBgSwitch'), pp.bg, _canOff(false, true, true), (on) => _pp((q) => q.copyWith(bg: on))),
            if (pp.bg) ...[
              _favSection(ts, (f) => _set(f)),
              const SizedBox(height: 12),
              ColorChooser(
                color: p.color,
                onPick: (hex, {required fromWheel}) => _set(() => ts.setColor(hex)),
                onEyedropper: () => Navigator.of(context).pop(EyeTarget.tool),
              ),
              const SizedBox(height: 4),
              _sliderRow(context.l10n.penOpacity, '${(p.opacity * 100).round()}%', Slider(
                value: p.opacity.clamp(.2, 1.0),
                min: .2,
                max: 1,
                onChanged: (v) => _set(() => p.opacity = (v * 100).round() / 100),
              )),
            ],
            const Divider(height: 20),
            _switchRow(context.l10n.paintGlitter, const Key('paintGlitterSwitch'), _glitterOn, _canOff(true, false, true), (on) => _pp((q) => q.copyWith(glitter: on ? .5 : 0))),
            if (_glitterOn)
              _sliderRow(context.l10n.paintAmount, '${(pp.glitter * 100).round()}%', Slider(
                value: pp.glitter,
                min: .05,
                onChanged: (v) => _pp((q) => q.copyWith(glitter: (v * 100).round() / 100)),
              )),
            const Divider(height: 20),
            _switchRow(context.l10n.shapesTitle, const Key('paintShapesSwitch'), pp.shapes, _canOff(true, true, false), (on) => _pp((q) => q.copyWith(shapes: on))),
            if (pp.shapes) ..._shapeOptions(scheme),
          ]),
        ),
      ),
    ]);
  }

  /// Una opción del tipo de trazo, con su muestra (usa el color, el ancho y los ajustes actuales, con el fondo prendido).
  Widget _styleCell(ColorScheme scheme, String id, String name) {
    final on = pp.style == id;
    return Expanded(
      child: GestureDetector(
        key: Key('paintSt-$id'),
        onTap: () => _pp((q) => q.copyWith(style: id)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            color: on ? scheme.surfaceContainerHighest : scheme.onSurface.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? scheme.primary : Colors.transparent, width: 1.5),
          ),
          child: Column(children: [
            Container(
              height: 40,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: const Color(0xFFFFFEFB), borderRadius: BorderRadius.circular(8)),
              child: CustomPaint(painter: _SamplePainter(p.tip, p.color, min(p.width, 22), p.opacity, pp.copyWith(style: id, bg: true))),
            ),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 11.5, color: on ? scheme.primary : scheme.onSurface), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  /// Grilla de formas, color (Auto, paleta, recientes, propio), cantidad y tamaño.
  List<Widget> _shapeOptions(ColorScheme scheme) {
    final custom = pp.shapeColor != null && pp.shapeColor!.startsWith('#') ? pp.shapeColor! : '#ffffff';
    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, name) in paintShapes)
          GestureDetector(
            key: Key('paintShape-$id'),
            onTap: () => _set(() => p.tip = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 56,
              height: 62,
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
              decoration: BoxDecoration(
                color: p.tip == id ? scheme.surfaceContainerHighest : scheme.onSurface.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.tip == id ? scheme.primary : Colors.transparent, width: 1.5),
              ),
              // el nombre toma lo que sobre (con la letra del sistema agrandada no desborda la celda)
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(height: 28, width: 28, child: CustomPaint(painter: _ShapePainter(id.substring(6), scheme.onSurface.withValues(alpha: .75)))),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(name(context.l10n), style: TextStyle(fontSize: 10.5, color: p.tip == id ? scheme.primary : scheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      ColorChooser(
        color: custom,
        onPick: (hex, {required fromWheel}) => _pp((q) => q.copyWith(shapeColor: hex)),
        onEyedropper: () => Navigator.of(context).pop(EyeTarget.paintShape),
        extras: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          // "Auto": el color de cada forma (blanco, fondo aclarado, dorado)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pp((q) => q.copyWith(autoColor: true)),
            child: Container(
              key: const Key('paintShapeAuto'),
              constraints: const BoxConstraints(minHeight: 40),
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: pp.shapeColor == null ? kAccent : const Color(0x33000000), width: pp.shapeColor == null ? 2 : 1),
                ),
                child: Text(context.l10n.paintAuto, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
          for (final c in const ['light', 'dark'])
            ColorDot(key: Key('shapeColor-$c'), color: _shapeSwatch(c), selected: c == pp.shapeColor, onTap: () => _pp((q) => q.copyWith(shapeColor: c))),
        ]),
      ),
      const SizedBox(height: 6),
      _sliderRow(context.l10n.paintAmount, '${(pp.density * 100).round()}%', Slider(
        value: pp.density,
        onChanged: (v) => _pp((q) => q.copyWith(density: (v * 100).round() / 100)),
      )),
      _sliderRow(context.l10n.paintSize, '${(pp.size * 100).round()}%', Slider(
        value: pp.size,
        onChanged: (v) => _pp((q) => q.copyWith(size: (v * 100).round() / 100)),
      )),
    ];
  }

  /// Color para mostrar de una opción de forma ('light' / 'dark' salen del fondo).
  String _shapeSwatch(String c) {
    if (c != 'light' && c != 'dark') return c;
    final bg = parseColor(p.color);
    final t = c == 'light' ? Color.lerp(bg, Colors.white, .6)! : Color.lerp(bg, Colors.black, .35)!;
    return '#${(t.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
