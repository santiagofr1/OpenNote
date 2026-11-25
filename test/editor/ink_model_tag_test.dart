import 'dart:ui' show Locale;

import 'package:apuntes/editor/ink_model_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inkModelTag', () {
    test('mismo idioma y región con modelo propio: lang-REGIÓN', () {
      expect(inkModelTag('es', const Locale('es', 'AR')), 'es-AR');
      expect(inkModelTag('es', const Locale('es', 'ES')), 'es-ES');
      expect(inkModelTag('es', const Locale('es', 'MX')), 'es-MX');
      expect(inkModelTag('es', const Locale('es', 'US')), 'es-US');
      expect(inkModelTag('pt', const Locale('pt', 'BR')), 'pt-BR');
      expect(inkModelTag('pt', const Locale('pt', 'PT')), 'pt-PT');
      expect(inkModelTag('en', const Locale('en', 'GB')), 'en-GB');
      expect(inkModelTag('en', const Locale('en', 'ZA')), 'en-ZA');
    });

    test('región sin modelo propio: el genérico', () {
      expect(inkModelTag('es', const Locale('es', 'CL')), 'es');
      expect(inkModelTag('pt', const Locale('pt', 'AO')), 'pt');
      expect(inkModelTag('en', const Locale('en', 'NZ')), 'en');
    });

    test('el dispositivo está en otro idioma: el genérico', () {
      expect(inkModelTag('en', const Locale('es', 'AR')), 'en');
      expect(inkModelTag('pt', const Locale('es', 'ES')), 'pt');
      expect(inkModelTag('es', const Locale('en', 'US')), 'es');
    });

    test('sin región, o con mayúsculas y minúsculas mezcladas', () {
      expect(inkModelTag('es', const Locale('es')), 'es');
      expect(inkModelTag('es', const Locale('es', 'ar')), 'es-AR');
      expect(inkModelTag('es', Locale.fromSubtags(languageCode: 'es', scriptCode: 'Latn', countryCode: 'MX')), 'es-MX');
    });

    test('un idioma que no se ofrece queda como viene', () {
      expect(inkModelTag('fr', const Locale('fr', 'FR')), 'fr');
    });

    test('las listas son las de ML Kit (sin 002)', () {
      expect(kInkRegions['es'], {'AR', 'ES', 'MX', 'US'});
      expect(kInkRegions['en'], {'AU', 'CA', 'GB', 'IN', 'KE', 'NG', 'PH', 'US', 'ZA'});
      expect(kInkRegions['pt'], {'BR', 'PT'});
    });
  });
}
