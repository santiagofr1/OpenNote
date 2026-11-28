import 'dart:typed_data';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/mind_map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// El mapa conceptual se pinta a un PNG del tamaño esperado (issue #17).
void main() {
  MindNode tree(int count, {int sections = 1}) {
    final nb = Notebook.create('Mapa');
    final secs = [nb.sections.single, for (var i = 1; i < sections; i++) nb.addSection('S$i')];
    final list = [
      for (var i = 0; i < count; i++)
        OutlineEntry(
            sectionId: secs[i % secs.length].id,
            headingId: 'h$i',
            sheetId: 's',
            sheet: 0,
            y: 0,
            level: 1 + i % 3 == 0 ? 1 : 2,
            number: '1',
            title: i % 7 == 0 ? 'Un título larguísimo ' * 12 : 'Título $i')
    ];
    return buildMindTree(nb, list, 'Sin título');
  }

  (int, int) size(Uint8List png) {
    final b = ByteData.sublistView(png);
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    return (b.getUint32(16), b.getUint32(20));
  }

  for (final c in [(0, 1), (1, 1), (200, 4)]) {
    testWidgets('pinta ${c.$1} títulos y el PNG mide lo esperado', (t) async {
      await t.runAsync(() async {
        final root = tree(c.$1, sections: c.$2);
        final map = layoutMindMapForPaint(root);
        final png = await renderMindMapPng(root, pixelRatio: 2);
        final r = mindMapRaster(map.bounds, 2);
        expect(size(png), (r.w, r.h));
        expect(r.w, greaterThan(100));
      });
    });
  }

  testWidgets('con un mapa enorme baja la escala para no pasar del tope', (t) async {
    await t.runAsync(() async {
      final root = tree(200, sections: 4);
      final map = layoutMindMapForPaint(root);
      final r = mindMapRaster(map.bounds, 3, maxSide: 1500);
      expect(r.ratio, lessThan(3));
      expect(r.w <= 1500 && r.h <= 1500, isTrue);
      final png = await renderMindMapPng(root, pixelRatio: 3, maxSide: 1500);
      expect(size(png), (r.w, r.h));
    });
  });
}
