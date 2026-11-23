import 'dart:async';
import 'dart:math';
import 'dart:ui';

/// Dedos apoyados en el visor y el pellizco de zoom.
/// Se lleva a mano (y no con un GestureDetector) para que el scroll siga funcionando debajo.
class TouchTracker {
  final _pos = <int, Offset>{}; // posición global de cada dedo
  int count = 0; // dedos apoyados (decide si "tirar" para agregar hoja)
  bool pinching = false;
  bool panning = false; // dos dedos arrastrando la hoja (con el zoom fijado)
  double _dist0 = 1, _zoom0 = 1;

  int get length => _pos.length;
  bool tracks(int pointer) => _pos.containsKey(pointer);

  void down(int pointer, Offset global) {
    count++;
    _pos[pointer] = global;
  }

  /// Suelta todos los dedos (el menú de la hoja se abre con el dedo apoyado y el levantado puede no llegar acá).
  void clear() {
    _pos.clear();
    count = 0;
    pinching = false;
    panning = false;
  }

  void move(int pointer, Offset global) => _pos[pointer] = global;

  void up(int pointer) {
    _pos.remove(pointer);
    count = max(0, count - 1);
  }

  /// Arranca el pellizco con dos dedos apoyados, desde el zoom actual.
  void startPinch(double zoom) {
    final p = _pos.values.take(2).toList();
    _dist0 = max(1, (p[0] - p[1]).distance);
    _zoom0 = zoom;
    pinching = true;
  }

  /// Punto medio (global) de los dos primeros dedos; null si hay menos de dos.
  Offset? get midpoint {
    if (_pos.length < 2) return null;
    final p = _pos.values.take(2).toList();
    return (p[0] + p[1]) / 2;
  }

  void startPan() => panning = true;
  void endPan() => panning = false;

  /// Zoom pedido por los dos primeros dedos y su punto medio (global); null si no hay pellizco.
  ({double zoom, Offset focal})? pinch() {
    if (!pinching || _pos.length < 2) return null;
    final p = _pos.values.take(2).toList();
    return (zoom: _zoom0 * (p[0] - p[1]).distance / _dist0, focal: (p[0] + p[1]) / 2);
  }
}

/// Mantener un solo dedo quieto 500 ms. Se hace a mano porque un LongPressGestureDetector
/// le gana la arena al pellizco y al scroll.
class StillPressTimer {
  StillPressTimer(this.onFire);
  final void Function(Offset global) onFire;
  static const delay = Duration(milliseconds: 500);
  static const slop = 12.0; // si se mueve más que esto, es scroll

  Timer? _timer;
  Offset? _start;

  void start(Offset global) {
    _timer?.cancel();
    _start = global;
    _timer = Timer(delay, _fire);
  }

  void moved(Offset global) {
    if (_start != null && (global - _start!).distance > slop) cancel();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _start = null;
  }

  void _fire() {
    final g = _start;
    cancel();
    if (g != null) onFire(g);
  }
}
