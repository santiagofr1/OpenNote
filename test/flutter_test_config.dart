// Configuración de todos los tests de test/: corren con el sistema en español, porque buscan los textos de la interfaz
// en español (flutter test arranca en en_US y, con las traducciones, la app saldría en inglés).

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // primero el main del archivo (algunos eligen su propio binding, p. ej. el de reloj real); los tests corren después
  await testMain();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localesTestValue = const [Locale('es', 'AR')];
  binding.platformDispatcher.localeTestValue = const Locale('es', 'AR');
}
