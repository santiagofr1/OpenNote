import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Escritura a mano sintética: renglones de "letras" (curvas suaves con un poco de ruido del
/// digitalizador y presión que sube y baja), con puntos cada ~1,5 unidades como un S Pen.
SheetContent syntheticSheet({int lines = 30, int lettersPerLine = 28, int seed = 7}) {
  final rnd = Random(seed);
  final strokes = <Stroke>[];
  for (var l = 0; l < lines; l++) {
    final y0 = 60.0 + l * 44;
    var x = 80.0;
    for (var w = 0; w < lettersPerLine; w++) {
      final n = 18 + rnd.nextInt(22); // puntos de la letra
      final width = 14 + rnd.nextDouble() * 16, height = 10 + rnd.nextDouble() * 22;
      final phase = rnd.nextDouble() * pi;
      final pts = <double>[];
      for (var i = 0; i < n; i++) {
        final t = i / (n - 1);
        final px = x + width * t + 4 * sin(2 * pi * t + phase) + (rnd.nextDouble() - .5) * .25;
        final py = y0 - height * sin(pi * t) * (0.6 + 0.4 * cos(3 * t + phase)) + (rnd.nextDouble() - .5) * .25;
        final pr = (0.2 + 0.7 * sin(pi * t)).clamp(0.0, 1.0) + (rnd.nextDouble() - .5) * .04;
        pts.addAll([(px * 10).round() / 10, (py * 10).round() / 10, (pr * 100).round() / 100]);
      }
      strokes.add(Stroke('s${l}_$w', 'pen', '#22211e', 2.6, pts));
      x += width + 6 + rnd.nextDouble() * 6;
      if (x > 900) break;
    }
  }
  return SheetContent(
    strokes: strokes,
    texts: [TextBlock('t1', 90, 44, 800, 'Ley de Ohm: V = I·R')],
    items: [Item('i1', 'sticky', 600, 900, 300, 200, text: 'repasar', color: '#fde68a')],
  );
}

void expectSame(SheetContent a, SheetContent b) {
  expect(b.strokes.length, a.strokes.length);
  for (var i = 0; i < a.strokes.length; i++) {
    final s = a.strokes[i], r = b.strokes[i];
    expect([r.id, r.k, r.c, r.w, r.o], [s.id, s.k, s.c, s.w, s.o]);
    expect(r.pts.length, s.pts.length);
    for (var j = 0; j < s.pts.length; j++) {
      // x, y a 0,05; presión a 1/255
      expect(r.pts[j], closeTo(s.pts[j], j % 3 == 2 ? 1 / 255 : .05), reason: 'trazo ${s.id} valor $j');
    }
  }
  expect(b.texts.map((t) => t.toJson()), a.texts.map((t) => t.toJson()));
  expect(b.items.map((t) => t.toJson()), a.items.map((t) => t.toJson()));
}

void main() {
  test('ida y vuelta de una hoja con trazos, textos y elementos', () {
    final c = SheetContent(
      strokes: [
        Stroke('a', 'pen', '#22211e', 2.6, [10.04, 20.06, .333, 30, 40, 1, -5.5, 3000.1, 0], .5),
        Stroke('b', 'hl', '#f7d22c', 22, [1, 2, .5]),
      ],
      texts: [TextBlock('t1', 90, 44, 800, 'Ñandú ✓ 日本')],
      items: [
        Item('i1', 'sticky', 100, 200, 320, 240, text: 'nota', color: '#fde68a'),
        Item('i2', 'audio', 0, 300, 360, 64, file: 'm1.m4a', dur: 4200),
        Item('i3', 'image', 0, 500, 560, 420, file: 'm2.png'),
      ],
    );
    final back = decodeSheet(encodeSheet(c));
    expectSame(c, back);
    expect(back.strokes[0].o, .5);
    expect(back.strokes[1].o, 1);
  });

  test('hoja vacía', () {
    final bytes = encodeSheet(SheetContent());
    expect(bytes.length, lessThan(60));
    expect(decodeSheet(bytes).isEmpty, isTrue);
  });

  test('trazo sin puntos y trazo de un solo punto', () {
    final c = SheetContent(strokes: [Stroke('e', 'pen', '#000000', 2, []), Stroke('p', 'pen', '#000000', 2, [5, 6, .5])]);
    final back = decodeSheet(encodeSheet(c));
    expect(back.strokes[0].n, 0);
    expect(back.strokes[1].pts[0], 5);
  });

  test('trazo enorme: 200.000 puntos', () {
    final rnd = Random(1);
    var x = 0.0, y = 500.0;
    final pts = <double>[];
    for (var i = 0; i < 200000; i++) {
      x += .5 + rnd.nextDouble() * .1;
      y += (rnd.nextDouble() - .5) * .8;
      pts.addAll([(x * 10).round() / 10, (y * 10).round() / 10, (rnd.nextInt(256)) / 255]);
    }
    final c = SheetContent(strokes: [Stroke('big', 'pen', '#000000', 2, pts)]);
    final bytes = encodeSheet(c);
    expectSame(c, decodeSheet(bytes));
  });

  test('coordenadas fuera de la hoja (negativas, enormes) y saltos grandes', () {
    final c = SheetContent(strokes: [
      Stroke('x', 'pen', '#000000', 2, [-100000, 99999.9, 0, 100000, -99999.9, 1, 0, 0, .5, 1e6, 1e6, .5])
    ]);
    expectSame(c, decodeSheet(encodeSheet(c)));
  });

  test('presión fuera de 0..1 se recorta', () {
    final c = SheetContent(strokes: [Stroke('x', 'pen', '#000000', 2, [1, 1, 1.5, 2, 2, -.2])]);
    final p = decodeSheet(encodeSheet(c)).strokes.single.pts;
    expect([p[2], p[5]], [1, 0]);
  });

  group('archivo roto: error claro, nunca un crash', () {
    final good = encodeSheet(syntheticSheet(lines: 3));

    void expectBroken(Uint8List b) => expect(() => decodeSheet(b), throwsA(isA<SheetFormatException>()));

    test('vacío, corto o sin "ONS"', () {
      expectBroken(Uint8List(0));
      expectBroken(Uint8List.fromList([0x4F, 0x4E]));
      expectBroken(Uint8List.fromList(utf8.encode('{"esto":"es json"}')));
    });

    test('versión que no conocemos', () {
      final b = Uint8List.fromList(good)..[3] = 99;
      expectBroken(b);
    });

    test('cortado a la mitad', () {
      expectBroken(Uint8List.sublistView(good, 0, good.length ~/ 2));
    });

    test('bytes pisados en el medio', () {
      final b = Uint8List.fromList(good);
      for (var i = good.length ~/ 2; i < good.length ~/ 2 + 20; i++) {
        b[i] ^= 0xFF;
      }
      expectBroken(b);
    });

    test('cuerpo bien comprimido pero con la cantidad de puntos inventada', () {
      // se arma a mano: JSON dice 1 trazo de 1.000.000 puntos pero no hay datos
      final json = utf8.encode(jsonEncode({
        'strokes': [
          {'id': 's', 'k': 'pen', 'c': '#000000', 'w': 2, 'n': 1000000}
        ]
      }));
      final body = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, json.length, Endian.little)).buffer.asUint8List())
        ..add(json);
      final file = BytesBuilder()
        ..add([0x4F, 0x4E, 0x53, 1])
        ..add(ZLibCodec().encode(body.takeBytes()));
      expectBroken(file.takeBytes());
    });

    test('golpes al azar en distintos bytes: siempre SheetFormatException o una hoja válida', () {
      final rnd = Random(3);
      for (var n = 0; n < 200; n++) {
        final b = Uint8List.fromList(good);
        b[rnd.nextInt(b.length)] ^= 1 << rnd.nextInt(8);
        try {
          decodeSheet(b);
        } on SheetFormatException {
          // bien
        }
      }
    });
  });

  test('tamaño: bytes por punto de una hoja realista, comparado con el JSON viejo', () {
    final c = syntheticSheet();
    final points = c.strokes.fold<int>(0, (n, s) => n + s.n);
    final bin = encodeSheet(c);
    final json = utf8.encode(jsonEncode({
      'strokes': {for (final s in c.strokes) s.id: s.toJson()},
      'texts': {for (final t in c.texts) t.id: t.toJson()},
      'items': {for (final i in c.items) i.id: i.toJson()},
    }));
    final jsonGz = gzip.encode(json);
    // ignore: avoid_print
    print('hoja sintética: ${c.strokes.length} trazos, $points puntos\n'
        '  JSON viejo:       ${json.length} bytes (${(json.length / points).toStringAsFixed(2)} B/punto)\n'
        '  JSON + gzip:      ${jsonGz.length} bytes (${(jsonGz.length / points).toStringAsFixed(2)} B/punto)\n'
        '  .sheet binario:   ${bin.length} bytes (${(bin.length / points).toStringAsFixed(2)} B/punto)\n'
        '  → ${(json.length / bin.length).toStringAsFixed(1)} veces más chico que el JSON');
    expect(bin.length / points, lessThan(3.5));
    expect(bin.length, lessThan(json.length ~/ 4));
    expectSame(c, decodeSheet(bin));
  });

  test('es determinista: la misma hoja da los mismos bytes (se compara para guardar solo lo que cambió)', () {
    final c = syntheticSheet(lines: 5);
    expect(encodeSheet(c), encodeSheet(decodeSheet(encodeSheet(c))), reason: 'releer y reescribir no cambia nada');
  });
}
