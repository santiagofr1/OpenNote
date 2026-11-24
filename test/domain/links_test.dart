import 'dart:ui';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLink', () {
    test('web, hoja y cuaderno', () {
      expect(parseLink('https://ejemplo.com/a?b=1'), LinkWeb(Uri.parse('https://ejemplo.com/a?b=1')));
      expect(parseLink('http://ejemplo.com'), isA<LinkWeb>());
      expect(parseLink('sheet:h123'), const LinkSheet('h123'));
      expect(parseLink('nb:n9'), const LinkNotebook('n9'));
    });
    test('lo inválido da null', () {
      for (final s in ['', 'sheet:', 'nb:', 'ejemplo.com', 'javascript:alert(1)', 'ftp://x.com', 'https://']) {
        expect(parseLink(s), isNull, reason: s);
      }
    });
  });

  group('normalizeUrl', () {
    test('agrega https si falta el esquema y recorta', () {
      expect(normalizeUrl('  ejemplo.com '), 'https://ejemplo.com');
      expect(normalizeUrl('es.wikipedia.org/wiki/Luz'), 'https://es.wikipedia.org/wiki/Luz');
      expect(normalizeUrl('http://ejemplo.com'), 'http://ejemplo.com');
      expect(normalizeUrl('HTTPS://Ejemplo.com'), 'HTTPS://Ejemplo.com');
      expect(normalizeUrl('localhost:8080'), 'https://localhost:8080');
    });
    test('solo http / https con dominio', () {
      for (final s in ['', '   ', 'hola', 'mailto:a@b.com', 'javascript:alert(1)', 'ftp://x.com', 'a b.com', 'file:///etc/passwd', 'https://.com']) {
        expect(normalizeUrl(s), '', reason: s);
      }
    });
  });

  test('linkLabel', () {
    expect(linkLabel(LinkWeb(Uri.parse('https://es.wikipedia.org/wiki/Luz'))), 'es.wikipedia.org/wiki/Luz');
    expect(linkLabel(LinkWeb(Uri.parse('https://ejemplo.com/'))), 'ejemplo.com');
    expect(linkLabel(const LinkSheet('a'), sheetName: (id) => 'Hoja 3'), 'Hoja 3');
    expect(linkLabel(const LinkSheet('a')), 'Hoja que ya no existe');
    expect(linkLabel(const LinkNotebook('a'), notebookName: (id) => 'Física'), 'Física');
  });

  group('coordenadas de PDF', () {
    // página de 600 x 800 pt mostrada en un elemento de 300 x 400 en (100, 1000)
    final it = Item('p', 'pdf', 100, 1000, 300, 400, file: 'a.pdf');
    const page = Size(600, 800);

    test('pdfPointFor: origen abajo', () {
      expect(pdfPointFor(it, const Offset(100, 1000), page), const Offset(0, 800)); // arriba a la izquierda
      expect(pdfPointFor(it, const Offset(400, 1400), page), const Offset(600, 0)); // abajo a la derecha
      expect(pdfPointFor(it, const Offset(250, 1100), page), const Offset(300, 600));
      expect(pdfPointFor(it, const Offset(50, 1100), page), isNull);
    });

    test('itemRectForPdfRect es la inversa', () {
      final r = itemRectForPdfRect(it, 0, 800, 600, 0, page);
      expect(r, it.rect);
      final r2 = itemRectForPdfRect(it, 60, 700, 300, 600, page); // un renglón cerca de arriba
      expect(r2, const Rect.fromLTRB(130, 1050, 250, 1100));
      final c = r2.center;
      final back = pdfPointFor(it, c, page)!;
      expect(back, const Offset(180, 650));
    });
  });

  test('un Item link pasa por el codec de hojas', () {
    final it = Item('l1', 'link', 10, 20, 300, 40, text: 'https://ejemplo.com');
    final back = decodeSheet(encodeSheet(SheetContent(items: [it]))).items.single;
    expect(back.type, 'link');
    expect(back.text, 'https://ejemplo.com');
    expect([back.x, back.y, back.w, back.h], [10, 20, 300, 40]);
    final s = Item('l2', 'link', 0, 0, 50, 50, text: 'sheet:h1');
    expect(Item.fromJson(s.toJson()).text, 'sheet:h1');
  });
}
