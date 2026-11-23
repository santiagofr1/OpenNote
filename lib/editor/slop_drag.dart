import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Arrastre de un solo puntero que gana la arena apenas se mueve [slop] píxeles (más rápido que el scroll, que necesita
/// `kTouchSlop` = 18, y que un `PanGestureRecognizer`, que necesita `kPanSlop` = 36). Así con el dedo se puede mover un
/// elemento o agarrar una manija en vez de scrollear, y un toque quieto (sin llegar al umbral) no le gana a nadie: lo que
/// esté debajo (el botón de reproducir de un audio, por ejemplo) sigue recibiendo su toque.
///
/// [onStart] recibe donde apoyó el puntero (no donde cruzó el umbral, para que lo agarrado no salte), [onUpdate] la posición
/// actual (global) y [onEnd] avisa que soltó o se canceló. [canStart] se consulta al cruzar el umbral: si devuelve false
/// (por ejemplo hay dos dedos apoyados: es un pellizco) el reconocedor se retira.
class SlopDragRecognizer extends OneSequenceGestureRecognizer {
  SlopDragRecognizer({super.debugOwner, super.supportedDevices, this.slop = 6});

  double slop;
  bool Function()? canStart;
  void Function(Offset down)? onStart;
  void Function(Offset global)? onUpdate;
  VoidCallback? onEnd;

  int? _pointer;
  Offset _down = Offset.zero, _last = Offset.zero;
  bool _accepted = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return; // un solo puntero a la vez
    startTrackingPointer(event.pointer, event.transform);
    _pointer = event.pointer;
    _down = _last = event.position;
    _accepted = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _last = event.position;
      if (_accepted) {
        onUpdate?.call(_last);
      } else if ((_last - _down).distance > slop) {
        if (canStart?.call() == false) {
          _end(rejectArena: true);
        } else {
          resolve(GestureDisposition.accepted);
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _end(rejectArena: !_accepted);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer != _pointer || _accepted) return;
    _accepted = true;
    onStart?.call(_down);
    onUpdate?.call(_last);
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    _end(rejectArena: false);
  }

  void _end({required bool rejectArena}) {
    final p = _pointer;
    final wasAccepted = _accepted;
    _pointer = null;
    _accepted = false;
    if (p != null) {
      stopTrackingPointer(p);
      if (rejectArena) resolvePointer(p, GestureDisposition.rejected);
    }
    if (wasAccepted) onEnd?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'slop drag';
}

/// [child] (o nada) con un [SlopDragRecognizer] que no tapa los toques de lo que tiene debajo.
class SlopDrag extends StatelessWidget {
  final Set<PointerDeviceKind>? devices;
  final double slop;
  final bool Function()? canStart;
  final void Function(Offset down) onStart;
  final void Function(Offset global) onUpdate;
  final VoidCallback onEnd;
  final Widget? child;
  const SlopDrag({
    super.key,
    this.devices,
    this.slop = 6,
    this.canStart,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.child,
  });

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          SlopDragRecognizer: GestureRecognizerFactoryWithHandlers<SlopDragRecognizer>(
            () => SlopDragRecognizer(supportedDevices: devices),
            (r) => r
              ..supportedDevices = devices
              ..slop = slop
              ..canStart = canStart
              ..onStart = onStart
              ..onUpdate = onUpdate
              ..onEnd = onEnd,
          ),
        },
        child: child,
      );
}
