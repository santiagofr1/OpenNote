import 'dart:ui' show Locale;

/// Regiones con modelo propio de escritura a mano en ML Kit, por idioma. Ver los modelos base en
/// developers.google.com/ml-kit/vision/digital-ink-recognition/base-models (el `002` no se usa).
const kInkRegions = <String, Set<String>>{
  'es': {'AR', 'ES', 'MX', 'US'},
  'en': {'AU', 'CA', 'GB', 'IN', 'KE', 'NG', 'PH', 'US', 'ZA'},
  'pt': {'BR', 'PT'},
};

/// Los idiomas de escritura a mano que ofrece la app.
const kInkLanguages = ['es', 'en', 'pt'];

/// La etiqueta del modelo de ML Kit para escribir en [lang] (es, en o pt): si el dispositivo está en el mismo idioma y
/// su región tiene modelo propio, `lang-REGIÓN` (por ejemplo `es-AR`); si no, el genérico (`es`).
String inkModelTag(String lang, Locale device) {
  final regions = kInkRegions[lang];
  if (regions == null) return lang;
  final country = device.countryCode?.toUpperCase();
  if (device.languageCode.toLowerCase() == lang && country != null && regions.contains(country)) return '$lang-$country';
  return lang;
}
