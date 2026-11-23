import 'dart:math';
import 'dart:ui';

final _rnd = Random.secure();

/// Id corto y aleatorio con prefijo: 's' trazo, 't' texto, 'i' elemento, 'p' página, 'n' cuaderno, 'c' sección, 'm' archivo.
String newId(String prefix) =>
    prefix + List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// '#rrggbb' → Color opaco.
Color parseColor(String s) => Color(int.parse(s.substring(1), radix: 16) | 0xFF000000);

/// Número del JSON como double (los archivos viejos pueden traer int o nada).
double jsonDouble(dynamic v, [double d = 0]) => v is num ? v.toDouble() : d;

/// Redondeo a un decimal: achica los archivos sin perder nada visible.
double round1(double v) => (v * 10).round() / 10;

/// Redondeo a dos decimales (presión, opacidad).
double round2(double v) => (v * 100).round() / 100;
