import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/domain.dart';

// Formato binario de una hoja (`.sheet`). Dart puro: se puede correr en un isolate.
//
//   "ONS" + u8 versión (1) + zlib( cuerpo )
//   cuerpo = u32 largo + JSON (textos, elementos y atributos de cada trazo, SIN los puntos)
//            + los puntos de todos los trazos, en orden
//   puntos de un trazo (n puntos) = x de los n | y de los n | presión de los n
//     x, y: enteros en décimas de unidad lógica; el primero va tal cual y los demás
//           como delta de delta, todos en zigzag-varint (una curva suave da casi todo 0)
//     presión: un byte (0..255)
//
// Orden de dibujo: cada elemento lleva 'z' (su lugar dentro de la hoja, 0..n-1, de abajo hacia arriba;
// ver [Layered]). Los archivos viejos no lo tienen y se leen con z = 0 para todo: el desempate por
// tipo da imágenes/notas/audio, tinta y textos, igual que se veían. Es una clave opcional del JSON, por
// eso la versión del formato sigue siendo 1 (una app vieja lee estos archivos y solo ignora el orden).
//
// Idea tomada de ISF (OneNote): coordenadas enteras + delta de delta + compresión.

const _magic = [0x4F, 0x4E, 0x53]; // "ONS"
const kSheetVersion = 1;

/// El archivo está roto o no es una hoja.
class SheetFormatException implements Exception {
  final String message;
  SheetFormatException(this.message);
  @override
  String toString() => 'SheetFormatException: $message';
}

// ---------------- escritura ----------------
void _writeVarint(BytesBuilder b, int v) {
  while (v >= 0x80) {
    b.addByte((v & 0x7F) | 0x80);
    v >>>= 7;
  }
  b.addByte(v);
}

int _zigzag(int v) => (v << 1) ^ (v >> 63);
int _unzigzag(int v) => (v >>> 1) ^ -(v & 1);

void _writePlane(BytesBuilder b, List<double> pts, int off, int n) {
  var prev = 0, prevDelta = 0;
  for (var i = 0; i < n; i++) {
    final v = (pts[i * 3 + off] * 10).round();
    if (i == 0) {
      _writeVarint(b, _zigzag(v));
    } else {
      final d = v - prev;
      _writeVarint(b, _zigzag(d - prevDelta));
      prevDelta = d;
    }
    prev = v;
  }
}

/// Hoja → bytes. Los puntos se redondean a décimas y la presión a 1/255.
Uint8List encodeSheet(SheetContent c) {
  // se guarda el lugar dentro de la hoja (no el z global): el archivo no cambia si otra hoja se reordena
  final rank = <String, int>{};
  for (final e in sortByZ([...c.items, ...c.strokes, ...c.texts])) {
    rank[e.id] = rank.length;
  }
  final meta = jsonEncode({
    'texts': [for (final t in c.texts) {...t.toJson(), 'z': rank[t.id]}],
    'items': [for (final i in c.items) {...i.toJson(), 'z': rank[i.id]}],
    'strokes': [
      for (final s in c.strokes)
        {'id': s.id, 'k': s.k, 'c': s.c, 'w': s.w, if (s.o < 1) 'o': round2(s.o), if (s.pp != null) 'pp': s.pp!.toJson(), if (s.fill != null) 'f': s.fill, 'n': s.n, 'z': rank[s.id]}
    ],
  });
  final json = utf8.encode(meta);
  final body = BytesBuilder(copy: false);
  body.add((ByteData(4)..setUint32(0, json.length, Endian.little)).buffer.asUint8List());
  body.add(json);
  for (final s in c.strokes) {
    _writePlane(body, s.pts, 0, s.n);
    _writePlane(body, s.pts, 1, s.n);
    for (var i = 0; i < s.n; i++) {
      body.addByte((s.pts[i * 3 + 2] * 255).round().clamp(0, 255));
    }
  }
  final z = ZLibCodec(level: 9).encode(body.takeBytes());
  final out = BytesBuilder(copy: false)
    ..add(_magic)
    ..addByte(kSheetVersion)
    ..add(z);
  return out.takeBytes();
}

// ---------------- lectura ----------------
class _Reader {
  final Uint8List b;
  int pos;
  _Reader(this.b, this.pos);

  int get left => b.length - pos;

  int varint() {
    var shift = 0, v = 0;
    while (true) {
      if (pos >= b.length) throw SheetFormatException('se terminó el archivo');
      final x = b[pos++];
      if (shift > 63) throw SheetFormatException('número demasiado largo');
      v |= (x & 0x7F) << shift;
      if (x < 0x80) return v;
      shift += 7;
    }
  }

  List<int> plane(int n) {
    final out = List.filled(n, 0);
    var prev = 0, prevDelta = 0;
    for (var i = 0; i < n; i++) {
      final z = _unzigzag(varint());
      if (i == 0) {
        prev = z;
      } else {
        prevDelta += z;
        prev += prevDelta;
      }
      out[i] = prev;
    }
    return out;
  }
}

/// Bytes → hoja. Lanza [SheetFormatException] si el archivo está roto (nunca otra cosa).
SheetContent decodeSheet(Uint8List bytes) {
  try {
    if (bytes.length < 4 || bytes[0] != _magic[0] || bytes[1] != _magic[1] || bytes[2] != _magic[2]) {
      throw SheetFormatException('no es una hoja (falta "ONS")');
    }
    if (bytes[3] != kSheetVersion) throw SheetFormatException('versión ${bytes[3]} no soportada');
    final body = Uint8List.fromList(ZLibCodec().decode(Uint8List.sublistView(bytes, 4)));
    if (body.length < 4) throw SheetFormatException('cuerpo vacío');
    final len = ByteData.sublistView(body).getUint32(0, Endian.little);
    if (len > body.length - 4) throw SheetFormatException('largo del JSON inválido');
    final j = jsonDecode(utf8.decode(Uint8List.sublistView(body, 4, 4 + len))) as Map;
    final r = _Reader(body, 4 + len);
    final strokes = <Stroke>[];
    for (final s in (j['strokes'] as List? ?? [])) {
      s as Map;
      final n = s['n'] as int;
      // cada punto ocupa al menos 3 bytes: evita reservar memoria por un n inventado
      if (n < 0 || n * 3 > r.left) throw SheetFormatException('cantidad de puntos inválida');
      final xs = r.plane(n), ys = r.plane(n);
      if (r.left < n) throw SheetFormatException('faltan presiones');
      final pts = List<double>.filled(n * 3, 0);
      for (var i = 0; i < n; i++) {
        pts[i * 3] = xs[i] / 10;
        pts[i * 3 + 1] = ys[i] / 10;
        pts[i * 3 + 2] = r.b[r.pos++] / 255;
      }
      strokes.add(Stroke(s['id'] as String, (s['k'] ?? 'pen') as String, (s['c'] ?? '#22211e') as String,
          jsonDouble(s['w'], 2), pts, jsonDouble(s['o'], 1), s['pp'] is Map ? PaintParams.fromJson(s['pp'] as Map) : null, s['f'] is String ? s['f'] as String : null)
        ..z = (s['z'] as num? ?? 0).toInt());
    }
    return SheetContent(
      strokes: strokes,
      texts: [for (final t in (j['texts'] as List? ?? [])) TextBlock.fromJson(t as Map)],
      items: [for (final i in (j['items'] as List? ?? [])) Item.fromJson(i as Map)],
    );
  } on SheetFormatException {
    rethrow;
  } catch (e) {
    // zlib roto, JSON roto, tipos que no son: todo es "archivo roto"
    throw SheetFormatException('$e');
  }
}

// ---------------- huella del contenido ----------------
Object? _round6(Object? v) => switch (v) {
      double d => (d * 1e6).round() / 1e6,
      Map m => {for (final e in m.entries) e.key: _round6(e.value)},
      List l => [for (final e in l) _round6(e)],
      _ => v,
    };

/// Huella del CONTENIDO de una hoja (todo lo que se guarda en su archivo: elementos, orden de dibujo, puntos en
/// décimas, presión en 1/255), insensible al ruido de 1e-13 que dejan las sumas y restas de `kSheetStep` al cargar y
/// partir las hojas. Dos contenidos con la misma huella se guardan igual. La carga perezosa la usa para comprobar que
/// lo que hay en memoria es lo que hay en disco antes de soltar una hoja.
String sheetDigest(SheetContent c) {
  final b = StringBuffer();
  for (final e in sortByZ([...c.items, ...c.strokes, ...c.texts])) {
    switch (e) {
      case Stroke s:
        b.write('S|${s.id}|${s.k}|${s.c}|${s.w}|${s.o < 1 ? round2(s.o) : 1}|${s.pp == null ? '' : jsonEncode(s.pp!.toJson())}${s.fill == null ? '' : '|f${s.fill}'}|${s.n}|');
        for (var i = 0; i < s.pts.length; i++) {
          b
            ..write(i % 3 == 2 ? (s.pts[i] * 255).round().clamp(0, 255) : (s.pts[i] * 10).round())
            ..write(',');
        }
      case TextBlock t:
        b.write('T|${jsonEncode(_round6(t.toJson()..remove('z')))}');
      case Item i:
        b.write('I|${jsonEncode(_round6(i.toJson()..remove('z')))}');
      default:
    }
    b.write('\n');
  }
  return md5.convert(utf8.encode(b.toString())).toString();
}
