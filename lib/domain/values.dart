import 'dart:math';
import 'dart:ui';

final _rnd = Random.secure();

/// Id corto y aleatorio con prefijo: 's' trazo, 't' texto, 'i' elemento, 'p' página, 'n' cuaderno, 'c' sección, 'm' archivo.
String newId(String prefix) =>
    prefix + List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _safeFileName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');

/// ¿[v] sirve de id que se usa como nombre de carpeta o de archivo (cuaderno, hoja, plantilla)? Solo letras, números, `_` y `-`:
/// sin `..`, sin separadores. Los ids vienen de disco, de la nube o de un `.vynote`: se validan SIEMPRE con esto.
bool isSafeId(Object? v) => v is String && _safeId.hasMatch(v);

/// ¿[v] sirve de nombre de archivo suelto dentro de `media/`? (sin rutas, no empieza con punto).
bool isSafeFileName(Object? v) => v is String && _safeFileName.hasMatch(v) && !v.contains('..');

/// '#rrggbb' → Color opaco.
/// Un color mal escrito (de un archivo roto o de otra versión) no tira: cae al negro tinta de siempre.
Color parseColor(String s) => Color((int.tryParse(s.length > 1 ? s.substring(1) : '', radix: 16) ?? 0x22211e) & 0xFFFFFF | 0xFF000000);

/// Número del JSON como double (los archivos viejos pueden traer int o nada).
double jsonDouble(dynamic v, [double d = 0]) => v is num ? v.toDouble() : d;

/// Número entero del JSON: acepta también los escritos con decimales (1700000000000.0, como los escriben otros programas).
int jsonInt(dynamic v, [int d = 0]) => v is num && v.isFinite ? v.toInt() : d;

/// Redondeo a un decimal: achica los archivos sin perder nada visible.
double round1(double v) => (v * 10).round() / 10;

/// Redondeo a dos decimales (presión, opacidad).
double round2(double v) => (v * 100).round() / 100;
