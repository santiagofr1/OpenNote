import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ¿Está apretado Ctrl (o Cmd en Mac)? Con eso la ruedita del mouse hace zoom en vez de scroll.
bool ctrlHeld() => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

/// Física que NO acepta la ruedita mientras hay Ctrl apretado: así el scroll no se registra en el resolver de
/// señales del puntero y gana el zoom del visor. Con Ctrl apretado tampoco se arrastra con el dedo (en la tablet
/// no hay Ctrl).
class NoCtrlWheelPhysics extends ScrollPhysics {
  const NoCtrlWheelPhysics({super.parent});

  @override
  NoCtrlWheelPhysics applyTo(ScrollPhysics? ancestor) => NoCtrlWheelPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => !ctrlHeld() && super.shouldAcceptUserOffset(position);
}

/// Factor de zoom de un giro de ruedita de [dy] píxeles (una muesca en Linux trae ~53, o sea ~10 %). Hacia arriba
/// (dy negativo) agranda.
double wheelZoomFactor(double dy) => exp(-dy * 0.002);
