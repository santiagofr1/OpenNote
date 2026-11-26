import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// A qué color se le aplica lo que toma el cuentagotas.
enum EyeTarget {
  /// El color de la herramienta actual (lápiz, resaltador o fondo del Decorador).
  tool,

  /// El relleno de las formas.
  shapeFill,

  /// El color de las formitas del Decorador.
  paintShape,
}

/// '#rrggbb' (minúsculas) de un color, sin la transparencia.
String hexOfColor(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Una captura de la pantalla en píxeles RGBA y su relación con las coordenadas lógicas.
class PixelBuffer {
  final int width, height;
  final Uint8List rgba;

  /// Píxeles de la captura por cada píxel lógico.
  final double pixelRatio;
  PixelBuffer(this.width, this.height, this.rgba, this.pixelRatio) : assert(rgba.length >= width * height * 4);

  /// Posición (en píxeles de la captura, sin salirse del borde) de un punto lógico.
  ({int x, int y}) pixelOf(Offset logical) => (
        x: (logical.dx * pixelRatio).floor().clamp(0, width - 1),
        y: (logical.dy * pixelRatio).floor().clamp(0, height - 1),
      );

  /// Color opaco del píxel que está bajo el punto lógico [logical]. Fuera de la captura toma el del borde más cercano.
  Color colorAt(Offset logical) {
    final p = pixelOf(logical);
    final i = (p.y * width + p.x) * 4;
    return Color.fromARGB(0xFF, rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// Lo mismo en '#rrggbb'.
  String hexAt(Offset logical) => hexOfColor(colorAt(logical));
}

/// Capa que se pone sobre la hoja mientras el cuentagotas está activo: avisa qué hacer, muestra la lupa mientras se
/// apoya y se arrastra, y al soltar entrega el color con [onPick]. Se come todos los toques (no se dibuja ni se scrollea).
/// [image] es la captura de lo que se ve (en píxeles, [PixelBuffer.pixelRatio] por píxel lógico).
class EyedropperOverlay extends StatefulWidget {
  final ui.Image image;
  final PixelBuffer pixels;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;
  const EyedropperOverlay({super.key, required this.image, required this.pixels, required this.onPick, required this.onCancel});

  /// Diámetro de la lupa y cuánto se amplía cada píxel lógico.
  static const loupeSize = 96.0, zoom = 8.0;

  @override
  State<EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<EyedropperOverlay> {
  Offset? pos;
  int? pointer; // el dedo o lápiz que manda; los demás se ignoran

  void _down(PointerDownEvent e) {
    if (pointer != null) return;
    pointer = e.pointer;
    HapticFeedback.selectionClick();
    setState(() => pos = e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == pointer) setState(() => pos = e.localPosition);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != pointer) return;
    final p = e.localPosition;
    pointer = null;
    setState(() => pos = null);
    widget.onPick(widget.pixels.hexAt(p));
  }

  void _cancelPointer(PointerCancelEvent e) {
    if (e.pointer != pointer) return;
    pointer = null;
    setState(() => pos = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final at = pos;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(builder: (context, box) {
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: Listener(
                key: const Key('eyedropperLayer'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancelPointer,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Center(
              child: Material(
                color: cs.inverseSurface,
                elevation: 3,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(context.l10n.eyedropperHint,
                          key: const Key('eyedropperHint'),
                          style: TextStyle(color: cs.onInverseSurface, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      key: const Key('eyedropperCancel'),
                      tooltip: context.l10n.eyedropperCancel,
                      onPressed: widget.onCancel,
                      icon: Icon(Icons.close_rounded, size: 20, color: cs.onInverseSurface, semanticLabel: context.l10n.eyedropperCancel),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          if (at != null) _loupe(at, box.biggest, widget.pixels.colorAt(at)),
        ]);
      }),
    );
  }

  /// La lupa va arriba del dedo; si no entra arriba, abajo. Nunca se sale por los costados.
  Widget _loupe(Offset at, Size area, Color under) {
    const s = EyedropperOverlay.loupeSize, gap = 28.0;
    final r = s / 2;
    final above = at.dy - gap - s >= 0;
    final cy = above ? at.dy - gap - r : at.dy + gap + r;
    final cx = at.dx.clamp(r, max(r, area.width - r));
    return Positioned(
      left: cx - r,
      top: cy - r,
      width: s,
      height: s,
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('eyedropperLoupe'),
          painter: LoupePainter(widget.image, widget.pixels.pixelRatio, at, under),
        ),
      ),
    );
  }
}

/// La lupa: la captura ampliada alrededor de [at] (punto lógico), con una retícula en el centro y un aro grueso del
/// color que está debajo.
class LoupePainter extends CustomPainter {
  final ui.Image image;
  final double pixelRatio;
  final Offset at;
  final Color under;
  LoupePainter(this.image, this.pixelRatio, this.at, this.under);

  @override
  void paint(Canvas c, Size size) {
    final r = size.width / 2, center = size.center(Offset.zero);
    const ring = 8.0;
    // el aro con una sombra corrida hacia abajo
    c.drawCircle(center + const Offset(0, 1.5), r, Paint()..color = const Color(0x55000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // la captura ampliada: cada píxel lógico ocupa [EyedropperOverlay.zoom] de la lupa
    final inner = r - ring;
    final span = (inner * 2) / EyedropperOverlay.zoom * pixelRatio; // lado, en píxeles de la captura, de lo que se ve
    final cx = at.dx * pixelRatio, cy = at.dy * pixelRatio;
    final src = Rect.fromCenter(center: Offset(cx.floorToDouble() + .5, cy.floorToDouble() + .5), width: span, height: span);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: inner)));
    c.drawColor(Colors.white, BlendMode.src);
    c.drawImageRect(image, src, Rect.fromCircle(center: center, radius: inner), Paint()..filterQuality = FilterQuality.none);
    c.restore();
    // retícula: el píxel del centro, con borde claro y oscuro para que se vea sobre cualquier color
    final cell = Rect.fromCenter(center: center, width: EyedropperOverlay.zoom, height: EyedropperOverlay.zoom);
    c.drawRect(cell.inflate(1), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = Colors.black87);
    c.drawRect(cell.deflate(.2), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white);
    // aro del color de abajo y filete fino por dentro y por fuera
    c.drawCircle(center, inner + ring / 2, Paint()..style = PaintingStyle.stroke..strokeWidth = ring..color = under);
    c.drawCircle(center, r - 1.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    c.drawCircle(center, r - .25, Paint()..style = PaintingStyle.stroke..strokeWidth = .5..color = const Color(0x66000000));
    c.drawCircle(center, inner, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x55000000));
  }

  @override
  bool shouldRepaint(LoupePainter o) => o.image != image || o.at != at || o.under != under || o.pixelRatio != pixelRatio;
}

/// Saca la captura de [boundary] (lo que se ve: tinta, PDF, imagen o fondo) como píxeles RGBA y como imagen.
Future<({ui.Image image, PixelBuffer pixels})?> captureBoundary(RenderRepaintBoundary boundary, double pixelRatio) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    image.dispose();
    return null;
  }
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return (image: image, pixels: PixelBuffer(image.width, image.height, bytes, pixelRatio));
}
