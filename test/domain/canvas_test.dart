import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/viewport.dart';
import 'package:apuntes/sync/sync_merge.dart';
import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke dot(String id, double x, double y) => Stroke(id, 'pen', '#000000', 2, [x, y, .5, x + 20, y + 20, .5]);

NotebookDoc canvasDoc({int sheets = 1, double w = 2000}) {
  final nb = Notebook.create('Mapa', canvas: true)..canvasW = w;
  while (nb.sheets.length < sheets) {
    nb.sheets.add(nb.newSheet());
  }
  return NotebookDoc(nb);
}

void main() {
  group('SheetLayout con lienzo', () {
    test('más ancho que el visor: pegado a la izquierda y se scrollea', () {
      final l = SheetLayout(800, 1, units: 3000);
      final base = SheetLayout(800, 1);
      expect(l.scale, base.scale);
      expect(l.sheetWidth, closeTo(3000 * l.scale, 1e-9));
      expect(l.sheetLeft, 24);
      expect(l.contentWidth, closeTo(l.sheetWidth + 48, 1e-9));
    });

    test('más angosto que el visor: centrado como una hoja', () {
      final l = SheetLayout(1600, 1, units: 1000);
      final base = SheetLayout(1600, 1);
      expect(l.sheetLeft, base.sheetLeft);
      expect(l.contentWidth, base.contentWidth);
    });

    test('toPage y scrollFor son inversas', () {
      final l = SheetLayout(800, 1.5, units: 4000);
      const scroll = Offset(500, 300), vp = Offset(120, 90);
      final p = l.toPage(vp, scroll);
      final back = l.scrollFor(p, vp);
      expect(back.dx, closeTo(scroll.dx, 1e-6));
      expect(back.dy, closeTo(scroll.dy, 1e-6));
    });
  });

  group('NotebookDoc.width / bandRect', () {
    test('hojas: igual que antes', () {
      final d = NotebookDoc(Notebook.create('t'))..addSheet();
      expect(d.width, kW);
      expect(d.bandRect(1), const Rect.fromLTWH(0, kSheetStep, kW, kSheetH));
    });

    test('lienzo: franja ancha que incluye el hueco', () {
      final d = canvasDoc();
      expect(d.width, 2000);
      expect(d.bandRect(2), const Rect.fromLTWH(0, 2 * kSheetStep, 2000, kSheetStep));
      expect(d.sheets.every((m) => m.bg == 'blank'), isTrue);
    });

    test('un trazo en el hueco entre franjas queda en una franja', () {
      final d = canvasDoc(sheets: 2);
      final s = dot('a', 100, kSheetH + 10); // dentro del hueco de la franja 0
      d.strokes[s.id] = s;
      final k = d.sheetOfY(s.bounds.top);
      expect(k, 0);
      expect(s.bounds.overlaps(d.bandRect(k)), isTrue);
    });
  });

  test('grownCanvasW', () {
    expect(grownCanvasW(2000, 1500), 2000);
    expect(grownCanvasW(2000, 1700), 2500);
    expect(grownCanvasW(2000, 2400), 3500);
    expect(grownCanvasW(3000, 100), 3000);
  });

  group('Notebook canvas en JSON', () {
    test('ida y vuelta', () {
      final nb = Notebook.create('M', canvas: true)..canvasW = 3500;
      final back = Notebook.fromJson(jsonDecode(jsonEncode(nb.toJson())) as Map);
      expect(back.canvas, isTrue);
      expect(back.canvasW, 3500);
    });

    test('uno viejo (sin las claves) es de hojas', () {
      final nb = Notebook.fromJson({'id': 'n', 'name': 'x'});
      expect(nb.canvas, isFalse);
      expect(Notebook.create('h').toJson().containsKey('canvas'), isFalse);
    });
  });

  test('la fusión de la sync deja el mayor canvasW', () {
    String idx(double w) => jsonEncode({
          'format': 3,
          'rev': 1,
          'notebooks': [
            {'id': 'n', 'name': 'M', 'updated': w.toInt(), 'canvas': true, 'canvasW': w}
          ]
        });
    for (final (l, r) in [(2500.0, 4000.0), (4000.0, 2500.0)]) {
      final m = jsonDecode(mergeIndexJson(idx(2000), idx(l), idx(r))) as Map;
      final n = (m['notebooks'] as List).single as Map;
      expect(n['canvas'], true);
      expect(n['canvasW'], 4000);
    }
  });

  group('exportar un lienzo', () {
    test('canvasPages: solo las páginas con contenido', () {
      final d = canvasDoc(sheets: 3, w: 3500);
      d.strokes['a'] = dot('a', 2500, 100); // columna 2, fila 0
      d.strokes['b'] = dot('b', 100, 3000); // columna 0, fila 2
      final p = canvasPages(d);
      expect(p, [
        const Rect.fromLTWH(2 * kW, 0, kW, kSheetStep),
        const Rect.fromLTWH(0, 2 * kSheetStep, kW, kSheetStep),
      ]);
    });

    test('vacío: una página', () {
      expect(canvasPages(canvasDoc()), [const Rect.fromLTWH(0, 0, kW, kSheetStep)]);
    });

    testWidgets('los PNG salen uno por página con contenido', (t) async {
      final root = (await t.runAsync(() => Directory.systemTemp.createTemp('apuntes_canvas')))!;
      addTearDown(() => root.delete(recursive: true));
      final store = Storage(root: root);
      await t.runAsync(store.init);
      final d = canvasDoc(sheets: 3, w: 3500);
      d.texts['a'] = TextBlock('a', 2500, 100, 400, 'Hola');
      d.texts['b'] = TextBlock('b', 100, 3000, 400, 'Chau');
      final pngs = await t.runAsync(() => buildNotebookPngs(store, d));
      expect(pngs!.zip, isTrue);
      final names = ZipDecoder().decodeBytes(pngs.bytes).map((f) => f.name).toList();
      expect(names, ['Mapa - página 01.png', 'Mapa - página 02.png']);
    });

    testWidgets('el PDF de un lienzo con una página con contenido', (t) async {
      final root = (await t.runAsync(() => Directory.systemTemp.createTemp('apuntes_canvas')))!;
      addTearDown(() => root.delete(recursive: true));
      final store = Storage(root: root);
      await t.runAsync(store.init);
      final d = canvasDoc(sheets: 2, w: 3500);
      d.texts['a'] = TextBlock('a', 2500, 100, 400, 'Hola');
      final pdf = await t.runAsync(() => buildNotebookPdf(store, d));
      expect(String.fromCharCodes(pdf!.take(5)), '%PDF-');
    });
  });
}
