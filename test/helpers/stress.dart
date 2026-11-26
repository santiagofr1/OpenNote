// Utilidades de los tests de estrés (test/stress/): generadores con semilla fija (fuzzing reproducible, sin librerías
// de property-based testing) y una "foto" exacta de un documento para comparar estados.
//
// Todos los generadores usan valores que sobreviven al formato de disco SIN perder nada (coordenadas en décimas,
// presión en 1/255): así los tests pueden pedir igualdad EXACTA en vez de "más o menos".

import 'dart:convert';
import 'dart:math';

import 'package:apuntes/domain/domain.dart';

/// Semillas fijas de cada test: si uno falla, el nombre del test dice con cuál (y `reason` dice la iteración).
const kSeeds = [1, 2, 3, 5, 8, 13, 21, 34];

Object? _r6(Object? v) => switch (v) {
      double d => d.isFinite ? (d * 1e6).round() / 1e6 : d.toString(),
      Map m => {for (final e in m.entries) e.key: _r6(e.value)},
      List l => [for (final e in l) _r6(e)],
      _ => v,
    };

/// Foto completa y ordenada del documento: hojas (con sus datos), y todos los elementos con su z y sus valores crudos
/// (redondeados a 1e-6 para tolerar el ruido de sumar y restar `kSheetStep`).
String snapshotDoc(NotebookDoc d) {
  final strokes = d.strokes.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final texts = d.texts.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final items = d.items.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode(_r6({
    'sheets': [for (final m in d.sheets) m.toJson()],
    'strokes': [
      for (final s in strokes) {'id': s.id, 'k': s.k, 'c': s.c, 'w': s.w, 'o': s.o, 'pts': s.pts, 'z': s.z}
    ],
    'texts': [for (final t in texts) {...t.toJson(), 'z': t.z}],
    'items': [for (final i in items) {...i.toJson(), 'z': i.z}],
  }));
}

/// Como [snapshotDoc] pero SIN los z absolutos: en su lugar, por hoja, la lista de ids en orden de dibujo. Restaurar una
/// hoja borrada renumera sus z arriba de todo (solo importa el orden relativo dentro de la hoja).
String snapshotDocLoose(NotebookDoc d) {
  final base = jsonDecode(snapshotDoc(d)) as Map;
  for (final k in ['strokes', 'texts', 'items']) {
    for (final e in base[k] as List) {
      (e as Map).remove('z');
    }
  }
  base['order'] = [
    for (var k = 0; k < d.sheetCount; k++)
      [
        for (final e in d.drawOrder())
          if (d.sheetOfElement(e) == k) e.id
      ]
  ];
  return jsonEncode(base);
}

/// Un número "difícil" pero representable en el disco: en décimas exactas.
double tenth(Random r, {double span = 3000}) {
  final big = r.nextInt(20) == 0;
  final k = big ? r.nextInt(2000000000) - 1000000000 : (r.nextDouble() * span * 10).round() - (span * 5).round();
  return k / 10;
}

/// Trazo con [n] puntos (0, 1, 2 y tamaños raros incluidos), presión en 1/255, coordenadas en décimas.
Stroke randomStroke(Random r, String id, {int? n, double yBase = 0, double span = 900, bool jumps = true}) {
  n ??= switch (r.nextInt(10)) { 0 => 0, 1 => 1, 2 => 2, 3 => 3, _ => 4 + r.nextInt(120) };
  final pts = <double>[];
  var x = (jumps ? tenth(r, span: span) : r.nextInt(5000) / 10).abs(), y = yBase + (jumps ? tenth(r, span: span) : r.nextInt(3000) / 10).abs();
  for (var i = 0; i < n; i++) {
    // a veces un salto enorme (el delta de delta tiene que aguantarlo)
    if (jumps && r.nextInt(25) == 0) {
      x = tenth(r);
      y = yBase + tenth(r);
    } else {
      x += (r.nextInt(41) - 20) / 10;
      y += (r.nextInt(41) - 20) / 10;
    }
    pts.addAll([x, y, r.nextInt(256) / 255]);
  }
  final kinds = ['pen', 'fountain', 'pencil', 'fine', 'calli', 'hl'];
  return Stroke(id, kinds[r.nextInt(kinds.length)], '#22211e', 1 + r.nextInt(40) / 10, pts, r.nextInt(4) == 0 ? .5 : 1);
}

/// Contenido de una hoja al azar con z únicos 0..n-1 (el formato guarda el lugar dentro de la hoja).
SheetContent randomSheet(Random r, {int maxStrokes = 12, String prefix = 'e'}) {
  final c = SheetContent();
  for (var i = 0; i < r.nextInt(maxStrokes + 1); i++) {
    c.strokes.add(randomStroke(r, '${prefix}s$i'));
  }
  for (var i = 0; i < r.nextInt(4); i++) {
    c.texts.add(TextBlock('${prefix}t$i', tenth(r).abs(), tenth(r).abs(), 800, _texto(r)));
  }
  for (var i = 0; i < r.nextInt(3); i++) {
    c.items.add(Item('${prefix}i$i', 'sticky', tenth(r).abs(), tenth(r).abs(), 100.0 + r.nextInt(300), 100.0 + r.nextInt(300), text: _texto(r)));
  }
  final all = <Layered>[...c.strokes, ...c.texts, ...c.items];
  final z = List.generate(all.length, (i) => i)..shuffle(r);
  for (var i = 0; i < all.length; i++) {
    all[i].z = z[i];
  }
  return c;
}

const _raros = ['', 'a', 'ñandú', '日本語', '😀🧑‍💻', 'a/b', '..', 'x\ny', '\u0000', 'a‮b', '"comillas"', r'back\slash'];
String _texto(Random r) => _raros[r.nextInt(_raros.length)] + (r.nextInt(8) == 0 ? 'z' * r.nextInt(3000) : '');

/// Nombres de archivo / cuaderno hostiles.
final kNombresRaros = <String>[
  '',
  ' ',
  '.',
  '..',
  '../..',
  'a/b',
  r'a\b',
  'con\nsalto',
  'nul\u0000byte',
  '😀🧑‍💻🏳️‍🌈',
  'ñandú año',
  'مرحبا',
  'x' * 255,
  'x' * 300,
  'é' * 200, // 400 bytes en UTF-8
  'CON',
  'a.vynote',
  '  con espacios  ',
];
