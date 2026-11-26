import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Ataques al formato binario de hoja (.sheet): propiedades sobre todo el dominio (ida y vuelta EXACTA, idempotencia,
/// determinismo), valores no finitos, archivos truncados / con bits pisados / con el JSON mal tipado.
void main() {
  /// Arma un `.sheet` a mano: [json] como cuerpo de metadatos y [tail] como bytes de puntos.
  Uint8List fileWith(Object json, {List<int> tail = const []}) {
    final j = utf8.encode(jsonEncode(json));
    final body = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, j.length, Endian.little)).buffer.asUint8List())
      ..add(j)
      ..add(tail);
    return Uint8List.fromList([0x4F, 0x4E, 0x53, 1, ...ZLibCodec().encode(body.takeBytes())]);
  }

  String sig(SheetContent c) => jsonEncode({
        'strokes': [for (final s in c.strokes) [s.id, s.k, s.c, s.w, s.o, s.z, s.pts]],
        'texts': [for (final t in c.texts) {...t.toJson(), 'z': t.z}],
        'items': [for (final i in c.items) {...i.toJson(), 'z': i.z}],
      });

  group('propiedades (semilla fija)', () {
    for (final seed in kSeeds) {
      test('decode(encode(x)) == x EXACTO, con el mismo z, y encode es estable (semilla $seed)', () {
        final r = Random(seed);
        var conPuntos = 0;
        for (var it = 0; it < 40; it++) {
          final c = randomSheet(r);
          final bytes = encodeSheet(c);
          final back = decodeSheet(bytes);
          conPuntos += c.strokes.where((s) => s.n > 1).length;
          // los generadores usan décimas y 1/255: el formato no tiene por qué perder NADA
          expect(sig(back), sig(c), reason: 'semilla $seed iteración $it');
          // idempotencia / determinismo: reescribir lo leído da los mismos bytes (el guardado compara hashes de bytes)
          expect(encodeSheet(back), bytes, reason: 'semilla $seed iteración $it: no es estable');
          expect(encodeSheet(c), bytes, reason: 'semilla $seed iteración $it: no es determinista');
        }
        expect(conPuntos, greaterThan(20), reason: 'el generador no tiene que ser vacío');
      });
    }

    test('el orden de dibujo sobrevive aunque los z originales sean enormes o negativos', () {
      final r = Random(77);
      for (var it = 0; it < 30; it++) {
        final c = randomSheet(r);
        final all = <Layered>[...c.strokes, ...c.texts, ...c.items];
        for (final e in all) {
          e.z = r.nextInt(2000000) - 1000000;
        }
        final order = [for (final e in sortByZ(all)) e.id];
        final back = decodeSheet(encodeSheet(c));
        final order2 = [for (final e in sortByZ([...back.strokes, ...back.texts, ...back.items])) e.id];
        // con z repetidos el desempate (tipo y orden de carga) puede variar: solo se exige cuando no hay repetidos
        if (all.map((e) => e.z).toSet().length == all.length) expect(order2, order, reason: 'iteración $it');
      }
    });
  });

  group('valores no finitos o gigantes en los trazos', () {
    // Un NaN / Infinity en un trazo (presión de un driver roto, una transformación con 0/0) NO tiene que impedir guardar:
    // `double.round()` tira UnsupportedError con NaN e Infinity, y el guardado se repite igual en cada intento.
    final malos = <String, List<double>>{
      'x NaN': [double.nan, 1, .5],
      'y NaN': [1, double.nan, .5],
      'presión NaN': [1, 1, double.nan],
      'x +Infinity': [double.infinity, 1, .5],
      'y -Infinity': [1, double.negativeInfinity, .5],
      'presión Infinity': [1, 1, double.infinity],
    };
    malos.forEach((nombre, pts) {
      test('$nombre: encodeSheet no explota y lo que se lee es finito', () {
        final c = SheetContent(strokes: [
          Stroke('sano', 'pen', '#000000', 2, [1, 2, .5, 3, 4, .5]),
          Stroke('malo', 'pen', '#000000', 2, [...pts, 5, 5, .5]),
        ]);
        late Uint8List bytes;
        expect(() => bytes = encodeSheet(c), returnsNormally, reason: 'un solo punto malo no puede romper todo el guardado');
        final back = decodeSheet(bytes);
        expect(back.strokes.firstWhere((s) => s.id == 'sano').pts, [1, 2, 128 / 255, 3, 4, 128 / 255]);
        for (final s in back.strokes) {
          expect(s.pts.every((v) => v.isFinite), isTrue, reason: '${s.id} salió con valores no finitos');
        }
      });
    });

    test('coordenadas absurdas (1e15, 1e19, 1e300, -1e300): no explota y lo que vuelve es finito', () {
      for (final v in [1e15, 1e17, 1e19, 1e300, -1e15, -1e19, -1e300, 4.9e-324, double.maxFinite]) {
        final c = SheetContent(strokes: [
          Stroke('s', 'pen', '#000000', 2, [0, 0, .5, v, v, .5, 1, 1, .5])
        ]);
        late SheetContent back;
        expect(() => back = decodeSheet(encodeSheet(c)), returnsNormally, reason: 'valor $v');
        expect(back.strokes.single.n, 3, reason: 'valor $v');
        expect(back.strokes.single.pts.every((x) => x.isFinite), isTrue, reason: 'valor $v');
        // lo que está al lado del valor absurdo no puede salir corrido (el delta de delta se desbordaría)
        expect(back.strokes.single.pts.sublist(6, 8), [1, 1], reason: 'valor $v: el tercer punto salió corrido');
      }
    });

    test('ancho y opacidad no finitos en el trazo no rompen la hoja (el JSON no admite NaN)', () {
      final c = SheetContent(strokes: [Stroke('s', 'pen', '#000000', double.nan, [1, 1, .5], double.infinity)]);
      expect(() => decodeSheet(encodeSheet(c)), returnsNormally);
    });
  });

  group('archivo roto: SIEMPRE SheetFormatException, nunca otra cosa ni un archivo "válido" con otro contenido', () {
    final c = randomSheet(Random(4), maxStrokes: 12);
    final good = encodeSheet(c);

    test('cortado en CADA largo posible', () {
      expect(good.length, greaterThan(40));
      for (var len = 0; len < good.length; len++) {
        try {
          // sin los 4 bytes del checksum final de zlib el cuerpo está completo y se lee igual: está bien SI es idéntico
          final back = decodeSheet(Uint8List.sublistView(good, 0, len));
          expect(len, greaterThanOrEqualTo(good.length - 4), reason: 'cortado a $len de ${good.length} bytes se leyó como válido (pérdida silenciosa)');
          expect(sig(back), sig(c), reason: 'cortado a $len bytes: leyó OTRO contenido sin avisar');
        } on SheetFormatException {
          // bien
        }
      }
    });

    test('un bit cambiado en cada posición: o error claro, o exactamente la misma hoja', () {
      var errores = 0;
      for (var pos = 0; pos < good.length; pos++) {
        final b = Uint8List.fromList(good)..[pos] ^= 1 << (pos % 8);
        try {
          final back = decodeSheet(b);
          // zlib tiene checksum: si decodifica tiene que ser porque el bit no cambió nada (ej. bits de relleno)
          expect(sig(back), sig(c), reason: 'bit en $pos: leyó OTRO contenido sin avisar');
        } on SheetFormatException {
          errores++;
        }
      }
      expect(errores, greaterThan(good.length ~/ 2), reason: 'casi todo bit pisado tendría que detectarse');
    });

    test('bytes basura detrás del flujo zlib: o error o la misma hoja, nunca otra', () {
      final b = Uint8List.fromList([...good, 1, 2, 3, 4, 5]);
      try {
        expect(sig(decodeSheet(b)), sig(c));
      } on SheetFormatException {
        // bien
      }
    });

    final tipos = <String, Object>{
      'strokes no es lista': {'strokes': 5},
      'texts es un mapa': {'texts': {}},
      'n fraccionario': {
        'strokes': [
          {'id': 's', 'n': 2.5}
        ]
      },
      'n es texto': {
        'strokes': [
          {'id': 's', 'n': '3'}
        ]
      },
      'n negativo': {
        'strokes': [
          {'id': 's', 'n': -1}
        ]
      },
      'n gigante (2^62)': {
        'strokes': [
          {'id': 's', 'n': 1 << 62}
        ]
      },
      'id nulo': {
        'strokes': [
          {'id': null, 'n': 0}
        ]
      },
      'trazo no es mapa': {
        'strokes': [1, 2]
      },
      'texto sin id': {
        'texts': [
          {'x': 1}
        ]
      },
      'item sin tipo': {
        'items': [
          {'id': 'i'}
        ]
      },
      'color malformado en un trazo': {
        'strokes': [
          {'id': 's', 'n': 0, 'c': 'rojo'}
        ]
      },
    };
    tipos.forEach((nombre, json) {
      test('JSON mal tipado ($nombre): SheetFormatException', () {
        try {
          final back = decodeSheet(fileWith(json));
          // si lo acepta, no puede dejar una bomba para después: tocar lo que usa el dibujo
          for (final s in back.strokes) {
            s.bounds;
          }
        } on SheetFormatException {
          // bien
        }
      });
    });

    test('el color mal escrito de un trazo no tiene que romper el dibujo de la hoja entera', () {
      // `Stroke.color` es `late final` y hace `int.parse` recién al dibujar: un 'c' roto que el decodificador acepta
      // reventaría el painter de toda la hoja. Tiene que rechazarse al leer o caer a un color por defecto.
      SheetContent? back;
      try {
        back = decodeSheet(fileWith({
          'strokes': [
            {'id': 's', 'n': 0, 'c': 'rojo'}
          ]
        }));
      } on SheetFormatException {
        return;
      }
      expect(() => back!.strokes.single.color, returnsNormally);
    });

    test('mil trazos de un punto y mil de cero puntos: ida y vuelta', () {
      final cc = SheetContent(strokes: [
        for (var i = 0; i < 1000; i++) Stroke('p$i', 'pen', '#000000', 2, [i / 10, 0, 128 / 255])..z = i,
        for (var i = 0; i < 1000; i++) Stroke('v$i', 'pen', '#000000', 2, [])..z = 1000 + i,
      ]);
      expect(sig(decodeSheet(encodeSheet(cc))), sig(cc));
    });
  });
}
