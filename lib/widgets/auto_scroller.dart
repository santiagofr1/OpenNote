import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Scroll automático mientras se arrastra cerca de los bordes de una lista (de arriba y abajo, o de izquierda y derecha
/// con [axis] horizontal).
class AutoScroller {
  AutoScroller(this.controller, this.viewport, {this.axis = Axis.vertical, this.onScrolled});
  final ScrollController controller;

  /// Caja de la lista que se desplaza (para saber dónde están sus bordes).
  final GlobalKey viewport;

  /// Eje que se desplaza: vertical usa `dy` y el alto de la caja; horizontal, `dx` y el ancho.
  final Axis axis;

  /// Se llama después de cada salto que realmente movió el scroll.
  final VoidCallback? onScrolled;

  /// Franja (px) de cada borde donde empieza a moverse, y velocidad máxima (px por cuadro de 16 ms).
  static const edge = 90.0, maxSpeed = 18.0;

  Timer? _timer;
  Offset? _pos;

  /// Velocidad con signo para un dedo a [y] px del tope de una lista de alto [h]: negativa sube, positiva baja.
  static double speedFor(double y, double h) {
    if (y < edge) return -maxSpeed * min(1.0, (edge - y) / edge);
    if (y > h - edge) return maxSpeed * min(1.0, (y - (h - edge)) / edge);
    return 0;
  }

  void moved(Offset global) {
    _pos = global;
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _pos = null;
  }

  void _tick() {
    final p = _pos;
    final box = viewport.currentContext?.findRenderObject();
    if (p == null || box is! RenderBox || !box.attached || !controller.hasClients) return;
    final local = box.globalToLocal(p);
    final v = axis == Axis.vertical ? speedFor(local.dy, box.size.height) : speedFor(local.dx, box.size.width);
    if (v == 0) return;
    final pos = controller.position;
    final before = pos.pixels;
    controller.jumpTo((before + v).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    if (pos.pixels != before) onScrolled?.call();
  }
}
