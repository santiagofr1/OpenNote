import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/updates.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Ajustes guardados (prefs.json), enlaces, extensiones de archivos elegidos y coordenadas de los links de PDF.
///
/// OJO con las preferencias: `LibraryScreen._load` llama a `tools.load(prefs)` SIN try/catch antes de `setState(index = ...)`.
/// Si `ToolState.load` tira por UN valor de tipo raro (prefs.json editado a mano, restaurado de un backup viejo o escrito
/// por otra versión), la biblioteca no termina de cargar: la app queda inutilizable hasta borrar prefs.json.
void main() {
  group('ToolState.load con prefs.json raro', () {
    // clave -> valores de tipo equivocado o fuera de rango que puede traer un archivo editado o de otra versión
    final raros = <String, List<Object?>>{
      'tool': [3, null, 'nada', [], {}],
      'pen': [5, 'x', [], true],
      'hl': [5, 'x', [], true],
      'paint': [5, 'x', [], true],
      'paintParams': [5, 'x', [], {'g': 'a'}],
      'penRecent': [5, 'x', {}, [1, 2], [null], ['#fff', 3]],
      'hlRecent': [[1], 'x'],
      'paintRecent': [[true], 'x'],
      'penFav': [5, [1, 2, 3, 4], ['#a', '#b'], 'x'],
      'eraserSize': [1.0, 1.5, 'x', null, -4, 99, true, 1e20],
      'dock': [5, 'abajo', null, []],
      'zoom': ['x', 0, -3, 1e9, 1e-9, null, true],
      'zoomLocked': [1, 'si', null],
      'shapeSnap': [1, 'x'],
      'shapeKind': [5, 'hexagono', null],
      'shapeFill': [1, 'x'],
      'shapeFillColor': [5, 'rojo', '#12', null, '#gggggg'],
      'shapeGrid': [0, 'x'],
      'colorView': [5, 'otra'],
      'exportBg': [0, 'x'],
    };
    raros.forEach((clave, valores) {
      for (final v in valores) {
        test('"$clave": ${jsonEncode(v)} no tira (la biblioteca depende de que cargar los ajustes no falle)', () {
          expect(() => ToolState().load({clave: v}), returnsNormally);
        });
      }
    });

    // valores sueltos de los lápices (cada uno dentro de pen / hl / paint)
    final lapices = <Map<String, Object?>>[
      {'tip': 3},
      {'color': 5},
      {'width': 'a'},
      {'width': null},
      {'opacity': 'a'},
      {'width': -3},
      {'width': 0},
      {'width': 1e300},
      {'opacity': 7},
      {'opacity': -1},
    ];
    for (final p in lapices) {
      for (final cual in ['pen', 'hl', 'paint']) {
        test('$cual ${jsonEncode(p)} no tira', () {
          expect(() => ToolState().load({cual: p}), returnsNormally);
        });
        test('$cual ${jsonEncode(p)}: el lápiz queda usable (ancho > 0 y finito, opacidad entre 0 y 1)', () {
          final t = ToolState();
          try {
            t.load({cual: p});
          } catch (_) {
            return; // ya lo dice el test de arriba
          }
          final l = switch (cual) { 'pen' => t.pen, 'hl' => t.hl, _ => t.paint };
          expect(l.width.isFinite && l.width > 0 && l.width <= 200, isTrue, reason: 'ancho ${l.width}');
          expect(l.opacity >= 0 && l.opacity <= 1, isTrue, reason: 'opacidad ${l.opacity}');
        });
      }
    }

    test('lo que se carga queda dentro de los rangos (zoom, borrador, colores favoritos) con valores numéricos fuera de rango', () {
      final t = ToolState()..load({'zoom': 1e9, 'eraserSize': 99, 'penFav': ['#1', '#2', '#3', '#4']});
      expect(t.zoom, inInclusiveRange(.5, 4));
      expect(t.eraserSize, inInclusiveRange(0, 2));
      expect(t.penFav.length, ToolState.kFavCount);
      final u = ToolState()..load({'zoom': -7, 'eraserSize': -7});
      expect(u.zoom, inInclusiveRange(.5, 4));
      expect(u.eraserSize, inInclusiveRange(0, 2));
    });

    for (final seed in kSeeds) {
      test('ida y vuelta con ajustes al azar (semilla $seed): load(toJson) es estable', () {
        final r = Random(seed);
        String color() => '#${r.nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}';
        for (var it = 0; it < 100; it++) {
          final t = ToolState()
            ..tool = Tool.values[r.nextInt(Tool.values.length)]
            ..eraserSize = r.nextInt(3)
            ..dock = ['top', 'left', 'right'][r.nextInt(3)]
            ..zoom = .5 + r.nextDouble() * 3.5
            ..zoomLocked = r.nextBool()
            ..shapeSnap = r.nextBool()
            ..shapeKind = shapeKinds[r.nextInt(shapeKinds.length)].$1
            ..shapeFill = r.nextBool()
            ..shapeFillColor = color()
            ..shapeGrid = r.nextBool()
            ..exportBackground = r.nextBool();
          t.pen
            ..color = color()
            ..width = 1 + r.nextInt(300) / 10
            ..opacity = r.nextInt(101) / 100;
          for (var i = 0; i < r.nextInt(10); i++) {
            t.pickColor(color());
          }
          for (var i = 0; i < 4; i++) {
            t.setFavorite(i, color());
          }
          final j = jsonEncode(t.toJson());
          final u = ToolState()..load(jsonDecode(j) as Map);
          expect(jsonEncode(u.toJson()), j, reason: 'it $it');
        }
      });
    }

    test('colores recientes: sin repetidos, el último elegido primero, nunca más de 7', () {
      final r = Random(2);
      final t = ToolState();
      for (var i = 0; i < 500; i++) {
        final c = '#${r.nextInt(12).toRadixString(16).padLeft(6, '0')}';
        t.pickColor(c);
        expect(t.recent.first, c);
        expect(t.recent.toSet().length, t.recent.length, reason: 'repetidos en ${t.recent}');
        expect(t.recent.length, lessThanOrEqualTo(7));
        expect(t.current.color, c);
      }
    });

    test('favoritos: fuera de rango no hace nada; guardar el mismo color dos veces dice que no cambió', () {
      final t = ToolState();
      final antes = List.of(t.penFav);
      t.setFavorite(-1, '#000000');
      t.setFavorite(4, '#000000');
      t.setFavorite(99, '#000000');
      expect(t.saveFavorite(-1), isFalse);
      expect(t.saveFavorite(4), isFalse);
      expect(t.penFav, antes);
      t.pickColor('#123456');
      expect(t.saveFavorite(2), isTrue);
      expect(t.saveFavorite(2), isFalse);
      expect(t.penFav[2], '#123456');
    });
  });

  group('UpdatePrefs y búsqueda de actualizaciones', () {
    test('valores de tipo equivocado en prefs.json no tiran', () {
      for (final v in [5, 'x', null, [], true, 1.5, {}]) {
        expect(() => UpdatePrefs.from({'updAuto': v, 'updLastCheck': v, 'updSkipped': v}), returnsNormally, reason: jsonEncode(v));
      }
    });
    test('due: apagada nunca; reloj atrasado cuenta como "ya pasó"; justo 24 h sí', () {
      final now = DateTime(2026, 11, 26, 12);
      final ms = now.millisecondsSinceEpoch;
      expect(UpdatePrefs(auto: false).due(now), isFalse);
      expect(UpdatePrefs(lastCheck: ms - const Duration(hours: 24).inMilliseconds).due(now), isTrue);
      expect(UpdatePrefs(lastCheck: ms - const Duration(hours: 24).inMilliseconds + 1).due(now), isFalse);
      expect(UpdatePrefs(lastCheck: ms + 1000).due(now), isTrue);
    });
  });

  group('enlaces', () {
    const trozos = ['a', 'b', '.', '/', ':', '@', ' ', '%', '?', '#', 'é', '😀', '\u0000', '\n', '\t', 'http', 'https', '://', 'localhost', 'mailto:', 'javascript:', 'com', 'x.com', '[', ']', '\\', '\u202e', '\u200b'];

    for (final seed in kSeeds) {
      test('normalizeUrl con texto al azar (semilla $seed): lo que acepta es una URL http(s) con dominio, sin espacios ni caracteres de control, y es estable', () {
        final r = Random(seed);
        for (var i = 0; i < 3000; i++) {
          final s = List.generate(1 + r.nextInt(8), (_) => trozos[r.nextInt(trozos.length)]).join();
          final u = normalizeUrl(s);
          if (u.isEmpty) continue;
          final p = parseLink(u);
          expect(p, isA<LinkWeb>(), reason: 'normalizeUrl(${jsonEncode(s)}) = ${jsonEncode(u)} no se puede abrir');
          final uri = (p! as LinkWeb).uri;
          expect(['http', 'https'], contains(uri.scheme));
          expect(uri.host, isNotEmpty);
          expect(u.runes.any((c) => c < 0x20 || c == 0x7f), isFalse, reason: 'caracteres de control en ${jsonEncode(u)} (de ${jsonEncode(s)})');
          expect(RegExp(r'\s').hasMatch(u), isFalse);
          expect(normalizeUrl(u), u, reason: 'no es estable: ${jsonEncode(u)}');
        }
      });
    }

    test('parseLink nunca tira, con cualquier texto', () {
      final r = Random(3);
      for (var i = 0; i < 3000; i++) {
        final s = List.generate(r.nextInt(8), (_) => ['sheet:', 'nb:', 'http', '://', 'a', ' ', '%', '\u0000', '😀', 'x.com'][r.nextInt(10)]).join();
        expect(() => parseLink(s), returnsNormally, reason: jsonEncode(s));
      }
    });

    test('un link a una hoja o cuaderno conserva el id tal cual (con espacios en los bordes recortados)', () {
      expect(parseLink('  sheet:h1  '), const LinkSheet('h1'));
      expect(parseLink('nb:n 1'), const LinkNotebook('n 1'));
    });
  });

  group('archivos elegidos', () {
    test('mediaExt: solo letras y números de hasta 8, de la extensión del NOMBRE; si no, el de reserva', () {
      expect(mediaExt('/a/b.c/foto', 'jpg'), 'jpg', reason: 'el punto es de una carpeta');
      expect(mediaExt('/a/foto.PNG', 'jpg'), 'png');
      expect(mediaExt(r'C:\a.b\foto.m4a', 'x'), 'm4a');
      expect(mediaExt('foto.', 'jpg'), 'jpg');
      expect(mediaExt('foto', 'jpg'), 'jpg');
      expect(mediaExt('foto.tar gz', 'jpg'), 'jpg');
      expect(mediaExt('foto.123456789', 'jpg'), 'jpg');
      expect(mediaExt('foto.ñandú', 'jpg'), 'jpg');
      expect(mediaExt('', 'jpg'), 'jpg');
    });

    test('mediaExt (azar): siempre cabe en un nombre de archivo de media/ (isSafeFileName)', () {
      final r = Random(4);
      const t = ['a', 'B', '.', '/', '\\', ' ', '1', 'ñ', '😀', '..', 'jpg', '\u0000', '-', '_'];
      for (var i = 0; i < 3000; i++) {
        final path = List.generate(r.nextInt(8), (_) => t[r.nextInt(t.length)]).join();
        final e = mediaExt(path, 'jpg');
        expect(isSafeFileName('x.$e'), isTrue, reason: 'mediaExt(${jsonEncode(path)}) = ${jsonEncode(e)}');
      }
    });

    test('nextAudioName: el mayor número + 1, aunque haya huecos, ceros delante, o números enormes', () {
      Item a(String n) => makeAudioItem('a.m4a', 0, name: n);
      expect(nextAudioName([a('Audio 007')]), 'Audio 8');
      expect(nextAudioName([a(' Audio 2 '), a('audio 9')]), 'Audio 3');
      expect(nextAudioName([a('Audio 99999999999999999999')]), isNotEmpty, reason: 'un número que no entra en un int no tira');
      expect(nextAudioName([a('Audio 5')], prefix: 'Grabación'), 'Grabación 1');
      expect(nextAudioName([a('Grabación (1) 5')], prefix: 'Grabación (1)'), 'Grabación (1) 6', reason: 'el prefijo se escapa, no es una expresión regular');
    });
  });

  group('coordenadas de PDF (propiedades)', () {
    test('un punto de la hoja pasa a puntos del PDF y vuelve; la esquina de arriba a la izquierda es (0, alto)', () {
      final r = Random(9);
      for (var i = 0; i < 2000; i++) {
        final it = Item('p', 'pdf', r.nextDouble() * 500, r.nextDouble() * 3000, 50 + r.nextDouble() * 900, 50 + r.nextDouble() * 1300, file: 'a.pdf');
        final page = Size(100 + r.nextDouble() * 900, 100 + r.nextDouble() * 900);
        final p = Offset(it.x + r.nextDouble() * it.w, it.y + r.nextDouble() * it.h);
        final q = pdfPointFor(it, p, page)!;
        expect(q.dx, inInclusiveRange(0, page.width));
        expect(q.dy, inInclusiveRange(0, page.height));
        final vuelta = Offset(it.x + q.dx / page.width * it.w, it.y + (page.height - q.dy) / page.height * it.h);
        expect((vuelta - p).distance, lessThan(1e-6));
        // afuera: null
        expect(pdfPointFor(it, Offset(it.x - 1, p.dy), page), isNull);
        expect(pdfPointFor(it, Offset(p.dx, it.y + it.h + 1), page), isNull);
        final arriba = pdfPointFor(it, Offset(it.x, it.y), page)!;
        expect((arriba - Offset(0, page.height)).distance, lessThan(1e-9));
      }
    });

    test('un rectángulo de la hoja pasa a puntos del PDF y vuelve (recortado al elemento)', () {
      final r = Random(10);
      for (var i = 0; i < 2000; i++) {
        final it = Item('p', 'pdf', r.nextDouble() * 500, r.nextDouble() * 3000, 50 + r.nextDouble() * 900, 50 + r.nextDouble() * 1300, file: 'a.pdf');
        final page = Size(100 + r.nextDouble() * 900, 100 + r.nextDouble() * 900);
        final a = Offset(it.x + r.nextDouble() * 1400 - 250, it.y + r.nextDouble() * 1800 - 250);
        final rect = Rect.fromPoints(a, a + Offset(1 + r.nextDouble() * 600, 1 + r.nextDouble() * 600));
        final res = pdfRectFor(it, rect, page);
        final clip = rect.intersect(it.rect);
        final hayInterseccion = clip.right > clip.left && clip.bottom > clip.top;
        expect(res != null, hayInterseccion, reason: 'it $i');
        if (res == null) continue;
        expect(res.left, lessThan(res.right));
        expect(res.top, greaterThan(res.bottom), reason: 'origen abajo: top >= bottom');
        expect(res.left, greaterThanOrEqualTo(-1e-6));
        expect(res.right, lessThanOrEqualTo(page.width + 1e-6));
        expect(res.bottom, greaterThanOrEqualTo(-1e-6));
        expect(res.top, lessThanOrEqualTo(page.height + 1e-6));
        final back = itemRectForPdfRect(it, res.left, res.top, res.right, res.bottom, page);
        expect((back.topLeft - clip.topLeft).distance, lessThan(1e-6), reason: 'it $i');
        expect((back.bottomRight - clip.bottomRight).distance, lessThan(1e-6), reason: 'it $i');
      }
    });

    test('un elemento sin tamaño no divide por cero', () {
      final it = Item('p', 'pdf', 0, 0, 0, 0, file: 'a.pdf');
      expect(pdfPointFor(it, Offset.zero, const Size(600, 800)), isNull);
      expect(pdfRectFor(it, const Rect.fromLTWH(0, 0, 10, 10), const Size(600, 800)), isNull);
    });
  });
}
