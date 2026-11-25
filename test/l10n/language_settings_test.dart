import 'dart:convert';
import 'dart:io';

import 'package:apuntes/l10n/l10n.dart';
import 'package:apuntes/l10n/language_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/l10n_app.dart';

void main() {
  group('resolveAppLocale (idioma de la app según el sistema)', () {
    test('es, en y pt (con cualquier región) se respetan', () {
      expect(resolveAppLocale(const [Locale('es', 'CL')]), const Locale('es'));
      expect(resolveAppLocale(const [Locale('pt', 'PT')]), const Locale('pt'));
      expect(resolveAppLocale(const [Locale('pt', 'BR')]), const Locale('pt'));
      expect(resolveAppLocale(const [Locale('en', 'AU')]), const Locale('en'));
    });

    test('un idioma que no es es/en/pt: inglés', () {
      expect(resolveAppLocale(const [Locale('de', 'DE')]), const Locale('en'));
      expect(resolveAppLocale(const [Locale('fr')]), const Locale('en'));
      expect(resolveAppLocale(const []), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
    });

    test('se usa el primero de la lista que esté soportado', () {
      expect(resolveAppLocale(const [Locale('de'), Locale('fr'), Locale('pt', 'BR'), Locale('es')]), const Locale('pt'));
    });
  });

  group('LanguageSettings', () {
    test('por defecto: sistema y "igual que la app"', () {
      final s = LanguageSettings();
      expect(s.appLanguage, 'system');
      expect(s.inkLanguage, 'app');
      expect(s.locale, isNull);
      expect(s.effectiveInk('pt'), 'pt');
    });

    test('elegir a mano, valores inválidos y avisos', () {
      final s = LanguageSettings();
      var n = 0;
      s.addListener(() => n++);
      s.appLanguage = 'en';
      expect(s.locale, const Locale('en'));
      s.appLanguage = 'en'; // igual: no avisa
      expect(n, 1);
      s.inkLanguage = 'pt';
      expect(s.effectiveInk('en'), 'pt');
      s.appLanguage = 'klingon'; // inválido: vuelve al sistema
      expect(s.appLanguage, 'system');
      expect(s.toJson(), {'appLanguage': 'system', 'inkLanguage': 'pt'});
    });

    test('load lee las preferencias (y tolera basura)', () {
      final s = LanguageSettings();
      expect(s.loaded, isFalse);
      s.load({'appLanguage': 'pt', 'inkLanguage': 'es'});
      expect((s.appLanguage, s.inkLanguage, s.loaded), ('pt', 'es', true));
      s.load({'appLanguage': 5, 'inkLanguage': 'zz'});
      expect((s.appLanguage, s.inkLanguage), ('system', 'app'));
      s.load(null);
      expect((s.appLanguage, s.inkLanguage), ('system', 'app'));
    });
  });

  group('archivos .arb', () {
    for (final lang in ['es', 'en', 'pt']) {
      test('app_$lang.arb es un JSON válido con su @@locale', () {
        final j = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map;
        expect(j['@@locale'], lang);
      });
    }

    test('app_es.arb: cada clave tiene su descripción', () {
      final j = jsonDecode(File('lib/l10n/app_es.arb').readAsStringSync()) as Map<String, dynamic>;
      final keys = j.keys.where((k) => !k.startsWith('@')).toList();
      expect(keys.length, greaterThan(100));
      for (final k in keys) {
        final meta = j['@$k'];
        expect(meta, isA<Map>(), reason: 'falta @$k');
        expect((meta as Map)['description'], isA<String>(), reason: 'falta la descripción de $k');
      }
    });
  });

  testWidgets('L en español devuelve los textos de siempre', (t) async {
    late L l;
    await t.pumpWidget(l10nApp(Builder(builder: (c) {
      l = c.l10n;
      return const SizedBox();
    })));
    expect(l.libraryTitle, 'Cuadernos');
    expect(l.libraryNew, 'Nuevo');
    expect(l.libraryHome, 'Inicio');
    expect(l.commonCancel, 'Cancelar');
    expect(l.newNotebookTitle, 'Nuevo cuaderno');
    expect(l.menuMoreShortcuts, 'Atajos de teclado');
    expect(l.settingsTitle, 'Ajustes');
    expect(l.libraryNotebookCount(1), '1 cuaderno');
    expect(l.libraryNotebookCount(3), '3 cuadernos');
    expect(l.deleteNotebookBody(1), 'Se borran sus 1 hoja. No se puede deshacer.');
    expect(l.deleteNotebookBody(4), 'Se borran sus 4 hojas. No se puede deshacer.');
    expect(l.exportFolderProgress(2, 5), 'Cuaderno 2 de 5');
  });

  testWidgets('con "en" todavía sin traducir, se usa el español', (t) async {
    late L l;
    await t.pumpWidget(l10nApp(locale: const Locale('en'), Builder(builder: (c) {
      l = c.l10n;
      return const SizedBox();
    })));
    expect(Localizations.localeOf(t.element(find.byType(SizedBox))), const Locale('en'));
    expect(l.settingsTitle, isNotEmpty);
  });
}
