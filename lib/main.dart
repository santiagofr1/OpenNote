import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'editor/handwriting.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApuntesApp());
  // baja el modelo de la letra en silencio, después del primer cuadro y sin competir con la carga inicial
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 3), () => unawaited(handwriting?.ensureModel()));
  });
}
