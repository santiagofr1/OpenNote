import 'dart:math';

import 'package:flutter/gestures.dart' show EagerGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/domain.dart';
import '../l10n/l10n.dart';
import '../theme/colors.dart';
import 'eyedropper.dart';

/// Vistas del selector de color (se guarda la elegida en [ToolState.colorView]).
const kColorViewPalette = 'palette', kColorViewWheel = 'wheel';

/// Muestra de color redonda de los paneles: círculo de 30 (el elegido, con borde blanco y aro [kAccent]) en un área de
/// toque de [hit] (40 como mínimo en tablet; en un panel angosto se achica para que entren las columnas).
class ColorDot extends StatelessWidget {
  final String color;
  final bool selected;
  final VoidCallback onTap;
  final double hit;
  const ColorDot({super.key, required this.color, required this.selected, required this.onTap, this.hit = 40});

  @override
  Widget build(BuildContext context) {
    final d = min(30.0, hit - 6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(child: _dot(context, color, selected, d)),
      ),
    );
  }

  static Widget _dot(BuildContext context, String c, bool on, double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: parseColor(c),
          shape: BoxShape.circle,
          border: Border.all(color: on ? Colors.white : Theme.of(context).colorScheme.outline.withValues(alpha: .55), width: on ? 3 : 1),
          boxShadow: on ? const [BoxShadow(color: kAccent, spreadRadius: 2)] : null,
        ),
      );
}

/// Envuelve un widget con la animación corta de "se guardó" (escala 1 → 1.15 → 1 en 220 ms). [builder] recibe la
/// función que la dispara.
class SavePulse extends StatefulWidget {
  final Widget Function(BuildContext context, VoidCallback pulse) builder;
  const SavePulse({super.key, required this.builder});
  @override
  State<SavePulse> createState() => _SavePulseState();
}

class _SavePulseState extends State<SavePulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.builder(context, () => _c.forward(from: 0)));
}

/// Un favorito: tocar lo usa; mantener apretado guarda ahí el color actual ([onSave] devuelve si cambió algo; si fue
/// así hay vibración y la muestra hace la animación de confirmación).
class FavoriteDot extends StatelessWidget {
  final String color;
  final bool selected;
  final VoidCallback onTap;
  final bool Function() onSave;
  const FavoriteDot({super.key, required this.color, required this.selected, required this.onTap, required this.onSave});

  @override
  Widget build(BuildContext context) => SavePulse(
        builder: (context, pulse) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () {
            if (!onSave()) return;
            HapticFeedback.mediumImpact();
            pulse();
          },
          child: SizedBox(width: 40, height: 40, child: Center(child: ColorDot._dot(context, color, selected, 30))),
        ),
      );
}

/// Grilla de muestras en filas de [perRow] columnas (cada celda se achica si el ancho no alcanza para 40).
class DotGrid extends StatelessWidget {
  final List<String> colors;
  final int perRow;
  final String? selected;
  final ValueChanged<String> onTap;
  const DotGrid({super.key, required this.colors, required this.perRow, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final hit = min(40.0, box.maxWidth / perRow);
        return Wrap(children: [for (final c in colors) ColorDot(color: c, selected: c == selected, onTap: () => onTap(c), hit: hit)]);
      });
}

/// El selector de color de todos los paneles: encabezado (color actual, vista Paleta / Rueda y cuentagotas), el cuerpo
/// según la vista y la fila de recientes.
///
/// [palette] es el contenido de la vista Paleta (lo arma cada panel). [onPick] avisa un color nuevo: [fromWheel] es
/// verdadero si sale de la rueda o del hex (que no entra a "recientes" en cada movimiento). Con [onEyedropper] nulo no
/// hay cuentagotas.
class ColorChooser extends StatefulWidget {
  final String color;
  final String view;
  final ValueChanged<String> onViewChanged;
  final Widget palette;
  final List<String> recent;
  final void Function(String hex, {required bool fromWheel}) onPick;
  final VoidCallback? onEyedropper;
  const ColorChooser({
    super.key,
    required this.color,
    required this.view,
    required this.onViewChanged,
    required this.palette,
    required this.onPick,
    this.recent = const [],
    this.onEyedropper,
  });
  @override
  State<ColorChooser> createState() => _ColorChooserState();
}

class _ColorChooserState extends State<ColorChooser> {
  // HSV propio: el tono no se pierde en los grises; se vuelve a sincronizar si el color cambia desde afuera
  late HSVColor hsv = HSVColor.fromColor(parseColor(widget.color));
  late final hex = TextEditingController(text: _digits(widget.color));
  final hexFocus = FocusNode();
  bool hexError = false;

  static String _digits(String c) => c.substring(1).toUpperCase();

  @override
  void didUpdateWidget(ColorChooser old) {
    super.didUpdateWidget(old);
    if (widget.color != old.color) {
      // el que salió de acá vuelve igual y no se toca; uno de afuera sí
      if (widget.color != hexOfColor(hsv.toColor())) hsv = HSVColor.fromColor(parseColor(widget.color));
      _syncHex();
    }
  }

  @override
  void dispose() {
    hex.dispose();
    hexFocus.dispose();
    super.dispose();
  }

  void _syncHex() {
    if (hexFocus.hasFocus) return; // no se pisa lo que se está tipeando
    final t = _digits(widget.color);
    if (hex.text != t) hex.text = t;
    if (hexError) setState(() => hexError = false);
  }

  void _setHsv(HSVColor c) {
    setState(() => hsv = c);
    final h = hexOfColor(c.toColor());
    if (!hexFocus.hasFocus) hex.text = _digits(h);
    widget.onPick(h, fromWheel: true);
  }

  /// Aplica el texto del campo: 6 cifras (o 3, que se duplican). Si no es válido no toca nada y marca el error.
  void _applyHex(String text, {required bool submit}) {
    var t = text.trim().replaceFirst('#', '');
    if (t.length == 3 && submit) t = t.split('').map((e) => e + e).join();
    final ok = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t);
    if (ok) {
      final h = '#${t.toLowerCase()}';
      if (submit) hex.text = t.toUpperCase(); // un hex de 3 cifras queda escrito entero
      setState(() {
        hexError = false;
        hsv = HSVColor.fromColor(parseColor(h));
      });
      widget.onPick(h, fromWheel: true);
    } else {
      setState(() => hexError = submit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wheel = widget.view == kColorViewWheel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(cs, wheel),
      const SizedBox(height: 8),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
          child: wheel
              ? KeyedSubtree(key: const ValueKey('wheelBody'), child: _wheelBody(cs))
              : Align(key: const ValueKey('paletteBody'), alignment: Alignment.topLeft, child: widget.palette),
        ),
      ),
      if (widget.recent.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(context.l10n.colorRecent, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Wrap(key: const Key('colorRecent'), children: [
          for (final c in widget.recent)
            ColorDot(color: c, selected: c == widget.color, onTap: () => widget.onPick(c, fromWheel: false)),
        ]),
      ],
    ]);
  }

  Widget _header(ColorScheme cs, bool wheel) {
    return Row(children: [
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(context.l10n.penColor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: parseColor(widget.color), shape: BoxShape.circle, border: Border.all(color: const Color(0x33000000))),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(widget.color.toUpperCase(),
                key: const Key('colorHexLabel'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .06), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _seg(cs, const Key('colorViewPalette'), (c) => Icon(Icons.grid_view_rounded, size: 20, color: c), context.l10n.colorViewPalette, !wheel, kColorViewPalette),
          _seg(cs, const Key('colorViewWheel'), (c) => _HueRingIcon(on: wheel), context.l10n.colorViewWheel, wheel, kColorViewWheel),
        ]),
      ),
      if (widget.onEyedropper != null) ...[
        const SizedBox(width: 8),
        IconButton(
          key: const Key('eyedropper'),
          tooltip: context.l10n.colorEyedropper,
          onPressed: widget.onEyedropper,
          icon: Icon(Icons.colorize_outlined, size: 20, semanticLabel: context.l10n.colorEyedropper),
          style: IconButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero, foregroundColor: cs.onSurfaceVariant),
        ),
      ],
    ]);
  }

  Widget _seg(ColorScheme cs, Key key, Widget Function(Color) icon, String tip, bool on, String view) => Tooltip(
        message: tip,
        child: Semantics(
          button: true,
          selected: on,
          label: tip,
          excludeSemantics: true,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onViewChanged(view),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: on ? cs.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: on ? const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))] : null,
              ),
              child: Center(child: icon(on ? cs.primary : cs.onSurfaceVariant)),
            ),
          ),
        ),
      );

  Widget _wheelBody(ColorScheme cs) => Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        ColorWheel(hsv: hsv, onChanged: _setHsv),
        const SizedBox(height: 10),
        SizedBox(
          width: 150,
          child: TextField(
            key: const Key('colorHex'),
            controller: hex,
            focusNode: hexFocus,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), _UpperCase()],
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              prefixText: '#',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hexError ? cs.error : cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hexError ? cs.error : cs.primary, width: 1.5)),
            ),
            onChanged: (t) => _applyHex(t, submit: false),
            onSubmitted: (t) => _applyHex(t, submit: true),
          ),
        ),
      ]);
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) => v.copyWith(text: v.text.toUpperCase());
}

/// Rueda de color: anillo de tono y, adentro, el cuadrado de saturación y brillo (estilo Krita / GIMP). Lado: el ancho
/// disponible, hasta 260. El que empieza a arrastrar sobre el anillo mueve el tono y el que empieza en el cuadrado mueve
/// saturación y brillo, hasta soltar. Nunca scrollea el panel mientras se arrastra.
class ColorWheel extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const ColorWheel({super.key, required this.hsv, required this.onChanged});

  static const maxSide = 260.0, ringWidth = 22.0, gap = 8.0, knob = 22.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = min(box.maxWidth.isFinite ? box.maxWidth : maxSide, maxSide);
        return Center(child: _Wheel(side: side, hsv: hsv, onChanged: onChanged));
      });
}

class _Wheel extends StatefulWidget {
  final double side;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _Wheel({required this.side, required this.hsv, required this.onChanged});
  @override
  State<_Wheel> createState() => _WheelState();
}

enum _Zone { ring, square }

class _WheelState extends State<_Wheel> {
  _Zone? zone; // lo que se está arrastrando
  late HSVColor cur = widget.hsv; // durante el arrastre manda lo último, sin esperar la vuelta del padre

  double get side => widget.side;
  Offset get center => Offset(side / 2, side / 2);
  double get outer => side / 2;
  double get inner => outer - ColorWheel.ringWidth;

  /// Cuadrado inscripto en el círculo interior (con un respiro respecto del anillo).
  Rect get square {
    final half = (inner - ColorWheel.gap) / sqrt2;
    return Rect.fromCenter(center: center, width: half * 2, height: half * 2);
  }

  @override
  void didUpdateWidget(_Wheel old) {
    super.didUpdateWidget(old);
    cur = widget.hsv;
  }

  void _down(Offset p) {
    final d = (p - center).distance;
    zone = d >= inner - 4 ? _Zone.ring : _Zone.square;
    _at(p);
  }

  void _at(Offset p) {
    if (zone == _Zone.ring) {
      final a = atan2(p.dy - center.dy, p.dx - center.dx); // en pantalla crece hacia la derecha y abajo
      cur = cur.withHue((a * 180 / pi + 360) % 360);
    } else {
      final sq = square;
      cur = cur
          .withSaturation(((p.dx - sq.left) / sq.width).clamp(0.0, 1.0))
          .withValue(1 - ((p.dy - sq.top) / sq.height).clamp(0.0, 1.0));
    }
    widget.onChanged(cur);
  }

  @override
  Widget build(BuildContext context) {
    final sq = square;
    final hue = cur.hue * pi / 180;
    final ringMid = (outer + inner) / 2;
    final hueAt = center + Offset(cos(hue), sin(hue)) * ringMid;
    final sqAt = Offset(sq.left + cur.saturation * sq.width, sq.top + (1 - cur.value) * sq.height);
    // el recognizer "eager" gana la arena al instante: arrastrar acá nunca scrollea el panel
    return RawGestureDetector(
      gestures: {EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(EagerGestureRecognizer.new, (_) {})},
      child: Listener(
        key: const Key('colorWheel'),
        onPointerDown: (e) => _down(e.localPosition),
        onPointerMove: (e) => _at(e.localPosition),
        onPointerUp: (_) => zone = null,
        onPointerCancel: (_) => zone = null,
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _WheelPainter(cur.hue, sq, ringWidth: ColorWheel.ringWidth))),
            // marcas de las zonas (para ubicarlas): no reciben toques
            Positioned.fill(key: const Key('colorRing'), child: const IgnorePointer(child: SizedBox.expand())),
            Positioned.fromRect(key: const Key('colorSquare'), rect: sq, child: const IgnorePointer(child: SizedBox.expand())),
            _knob(hueAt, HSVColor.fromAHSV(1, cur.hue, 1, 1).toColor()),
            _knob(sqAt, cur.toColor()),
          ]),
        ),
      ),
    );
  }

  Widget _knob(Offset at, Color fill) => Positioned(
        left: at.dx - ColorWheel.knob / 2,
        top: at.dy - ColorWheel.knob / 2,
        child: IgnorePointer(
          child: Container(
            width: ColorWheel.knob,
            height: ColorWheel.knob,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
          ),
        ),
      );
}

class _WheelPainter extends CustomPainter {
  final double hue;
  final Rect square;
  final double ringWidth;
  _WheelPainter(this.hue, this.square, {required this.ringWidth});

  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    // anillo de tono: degradé en barrido desde las 3 en punto, en el sentido del reloj (como crece el ángulo en pantalla)
    final full = Rect.fromCircle(center: center, radius: outer);
    c.drawCircle(
      center,
      outer - ringWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..isAntiAlias = true
        ..shader = SweepGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]).createShader(full),
    );
    // cuadrado de saturación (izquierda a derecha, de blanco al tono) y brillo (arriba a abajo, a negro)
    final rr = RRect.fromRectAndRadius(square, const Radius.circular(8));
    c.save();
    c.clipRRect(rr);
    c.drawRect(square, Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()]).createShader(square));
    c.drawRect(
      square,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Colors.black]).createShader(square),
    );
    c.restore();
    c.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x22000000));
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.hue != hue || o.square != square;
}

/// Ícono de la vista Rueda: un anillito con todos los tonos (apagado cuando la vista no está elegida).
class _HueRingIcon extends StatelessWidget {
  final bool on;
  const _HueRingIcon({required this.on});
  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: on ? 1 : .55, child: const SizedBox.square(dimension: 18, child: CustomPaint(painter: _HueRingPainter())));
}

class _HueRingPainter extends CustomPainter {
  const _HueRingPainter();
  @override
  void paint(Canvas c, Size size) {
    final r = Offset.zero & size;
    c.drawCircle(
        r.center,
        size.shortestSide / 2 - 2.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..shader = SweepGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), .85, .95).toColor()])
              .createShader(r));
  }

  @override
  bool shouldRepaint(_HueRingPainter o) => false;
}
