import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/export_raster.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import '../helpers/export_check.dart';

/// El PDF del cuaderno: la página i tiene que ser la hoja i (ni otra, ni repetida, ni vacía), en cualquier estado del
/// documento (hojas sin cargar en huecos, sucias sin guardar, movidas, duplicadas, de varias secciones...).
/// Cada hoja lleva una marca única ([Marks]); del PDF se sacan las imágenes de cada página con `pdfimages`.
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_export_pdf');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  final skip = hasPdfImages ? null : 'falta pdfimages (poppler-utils): no se pueden mirar las imágenes del PDF';

  /// Un cuaderno de [n] hojas guardado en disco, la hoja k con la marca k (y las que pida [extra]).
  Future<NotebookDoc> saved(int n, {String bg = 'blank', String paper = '#ffffff'}) async {
    final nb = Notebook.create('Marcas')
      ..bg = bg
      ..paper = paper;
    nb.sheets.clear();
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      Marks.add(d, k, k);
    }
    await store.saveNotebook(d);
    return d;
  }

  /// Abre de nuevo [ref] desde disco, perezoso.
  Future<NotebookDoc> reopen(NotebookDoc ref, {int around = 0, int radius = 1000}) async {
    final nb = Notebook(ref.id, ref.nb.name);
    return store.openNotebook(nb, around: around, radius: radius);
  }

  // todo el cuerpo corre con reloj real (hay disco, isolates y la GPU de por medio)
  Future<R> real<R>(WidgetTester t, Future<R> Function() f) => f();
  void rt(String name, Future<void> Function(WidgetTester t) body, {bool skip = false}) =>
      testWidgets(name, (t) async => t.runAsync(() => body(t)), skip: skip);

  /// La página i del PDF [pages] tiene exactamente las marcas [want] de entre [all].
  void expectMarks(List<im.Image> pages, List<int> want, {Iterable<int>? all, String? why}) {
    expect(pages.length, want.length, reason: 'cantidad de páginas ${why ?? ''}');
    final every = all ?? {...want};
    for (var i = 0; i < want.length; i++) {
      expect(Marks.found(pages[i], every), [want[i]], reason: 'la página ${i + 1} ${why ?? ''}');
    }
  }

  group('orden y contenido', () {
    rt('cada página es su hoja, con y sin fondo', (t) async {
      final doc = await saved(7, bg: 'grid');
      for (final bg in [true, false]) {
        final pdf = await real(t, () => buildNotebookPdf(store, doc, background: bg));
        expect(pdfPageCount(pdf), 7);
        expectMarks(await real(t, () => pdfPageImages(pdf)), [0, 1, 2, 3, 4, 5, 6], why: 'con fondo=$bg');
      }
    }, skip: skip != null);

    rt('con fondo se ve el patrón del papel y sin fondo no (en píxeles)', (t) async {
      for (final bgName in ['lined', 'grid', 'dots', 'mm', 'axes', 'cornell', 'todo', 'staff', 'weekly', 'monthly']) {
        final nb = Notebook.create('F-$bgName')..bg = bgName;
        nb.sheets
          ..clear()
          ..add(nb.newSheet());
        final doc = NotebookDoc(nb);
        final pdfs = {
          for (final bg in [true, false]) bg: await real(t, () => buildNotebookPdf(store, doc, background: bg)),
        };
        final withBg = (await real(t, () => pdfPageImages(pdfs[true]!))).single;
        final noBg = (await real(t, () => pdfPageImages(pdfs[false]!))).single;
        int nonPaper(im.Image p, int r, int g, int b) {
          var n = 0;
          for (final px in p) {
            if ((px.r - r).abs() > 8 || (px.g - g).abs() > 8 || (px.b - b).abs() > 8) n++;
          }
          return n;
        }

        final paper = parseColor(doc.sheets[0].paper);
        // el borde de abajo y de la derecha puede quedar a medio cubrir: se compara contra el papel, que lo cubre igual
        expect(nonPaper(noBg, 255, 255, 255), lessThan(3000), reason: 'sin fondo $bgName: papel liso y blanco');
        expect(nonPaper(withBg, (paper.r * 255).round(), (paper.g * 255).round(), (paper.b * 255).round()), greaterThan(2000),
            reason: 'con fondo $bgName: se ven las líneas del papel');
      }
    }, skip: skip != null);

    rt('el papel de color sale con fondo y blanco sin fondo', (t) async {
      final doc = await saved(2, paper: '#fde68a');
      final w = (await real(t, () async => pdfPageImages(await buildNotebookPdf(store, doc)))).first;
      final n = (await real(t, () async => pdfPageImages(await buildNotebookPdf(store, doc, background: false)))).first;
      expect(w.getPixel(900, 2200).r.round(), 0xfd);
      expect(w.getPixel(900, 2200).b.round(), 0x8a);
      expect(n.getPixel(900, 2200).r.round(), 255);
      expect(n.getPixel(900, 2200).b.round(), 255);
    }, skip: skip != null);

    rt('tamaños de hoja mezclados: cada página con su MediaBox y su contenido', (t) async {
      final doc = await saved(5);
      const sizes = ['a4', 'a3', 'a5', 'a4', 'a3'];
      for (var k = 0; k < 5; k++) {
        doc.sheets[k].size = sizes[k];
      }
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      final boxes = pdfMediaBoxes(pdf);
      expect(boxes.length, 5);
      for (var k = 0; k < 5; k++) {
        expect(boxes[k].$1, closeTo(paperWidthMm(sizes[k]) / 25.4 * 72, .6), reason: 'ancho de la página ${k + 1}');
        expect(boxes[k].$2, closeTo(paperHeightMm(sizes[k]) / 25.4 * 72, .6), reason: 'alto de la página ${k + 1}');
      }
      expectMarks(await real(t, () => pdfPageImages(pdf)), [0, 1, 2, 3, 4]);
    }, skip: skip != null);
  });

  group('documento perezoso', () {
    for (final seed in [1, 2, 3, 4, 5, 6]) {
      rt('hojas cargadas y sin cargar en huecos (semilla $seed)', (t) async {
        final r = Random(seed);
        final n = 9 + r.nextInt(5);
        final ref = await saved(n);
        final doc = await reopen(ref);
        // se sueltan hojas al azar, como al scrollear
        for (var k = 0; k < n; k++) {
          if (r.nextDouble() < .55) doc.detachSheet(doc.sheets[k].id);
        }
        final pattern = [for (var k = 0; k < n; k++) doc.isLoadedAt(k) ? 'X' : '.'].join();
        final pdf = await real(t, () => buildNotebookPdf(store, doc));
        expectMarks(await real(t, () => pdfPageImages(pdf)), [for (var k = 0; k < n; k++) k], why: 'con las hojas $pattern');
        // el export no cambia lo que está cargado
        expect([for (var k = 0; k < n; k++) doc.isLoadedAt(k) ? 'X' : '.'].join(), pattern);
      }, skip: skip != null);
    }

    rt('abierto alrededor de cada hoja (around/radius): todas salen bien', (t) async {
      final ref = await saved(6);
      for (final around in [0, 3, 5]) {
        for (final radius in [0, 1, 2]) {
          final doc = await reopen(ref, around: around, radius: radius);
          final pdf = await real(t, () => buildNotebookPdf(store, doc));
          expectMarks(await real(t, () => pdfPageImages(pdf)), [0, 1, 2, 3, 4, 5], why: 'around $around radio $radius');
        }
      }
    }, skip: skip != null);

    rt('una hoja cargada con cambios sin guardar sale como se ve, y las vecinas sin cargar también', (t) async {
      final ref = await saved(6);
      final doc = await reopen(ref, radius: 0);
      await store.loadSheets(doc, [doc.sheets[3].id]);
      Marks.add(doc, 3, 20); // sin guardar
      expect(doc.isSheetDirty(doc.sheets[3].id), isTrue);
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      final pages = await real(t, () => pdfPageImages(pdf));
      expectMarks(pages, [0, 1, 2, 3, 4, 5], all: [0, 1, 2, 3, 4, 5], why: '(sin la marca nueva)');
      expect(Marks.has(pages[3], 20), isTrue, reason: 'la marca sin guardar de la hoja 4');
      expect(Marks.has(pages[4], 20), isFalse);
      expect(doc.isSheetDirty(doc.sheets[3].id), isTrue, reason: 'exportar no guarda ni limpia nada');
    }, skip: skip != null);

    rt('un trazo que cruza de una hoja a la siguiente se ve en las dos, esté cargada o no', (t) async {
      final ref = await saved(4);
      // vertical de x=700 desde abajo de la hoja 1 hasta arriba de la hoja 2 (cruza el hueco entre hojas)
      final cross = Stroke('cruza', 'pen', '#aa0000', 40, [700, 1 * kSheetStep + 1300, .5, 700, 1 * kSheetStep + 1380, .5, 700, 2 * kSheetStep + 40, .5, 700, 2 * kSheetStep + 120, .5]);
      for (final pattern in ['XXXX', 'XX..', '.X.X', '....', 'X..X']) {
        final doc = await reopen(ref);
        doc.strokes[cross.id] = cross.moved(Offset.zero)..z = doc.nextZ();
        doc.markDirtyElement(doc.strokes['cruza']!);
        for (var k = 0; k < 4; k++) {
          if (pattern[k] == '.') {
            // sin cargar: hay que guardar antes para poder soltarla
            await store.saveNotebook(doc);
            await store.unloadSheets(doc, [doc.sheets[k].id]);
          }
        }
        final pdf = await real(t, () => buildNotebookPdf(store, doc));
        final pages = await real(t, () => pdfPageImages(pdf));
        for (final (k, y) in [(1, 1340.0), (2, 80.0)]) {
          final p = pages[k].getPixel((700 * 1654 / kW).round(), (y * 1654 / kW).round());
          expect(p.r.round(), 0xaa, reason: 'hoja ${k + 1} (cargadas $pattern)');
          expect(p.g.round(), 0, reason: 'hoja ${k + 1} (cargadas $pattern)');
        }
        // las marcas siguen en su lugar
        for (var k = 0; k < 4; k++) {
          expect(Marks.has(pages[k], k), isTrue, reason: 'marca de la hoja ${k + 1} (cargadas $pattern)');
        }
      }
    }, skip: skip != null);
  });

  group('operaciones de la sesión', () {
    rt('agregar, duplicar, mover y borrar hojas: el PDF sigue el orden de la tira', (t) async {
      final ref = await saved(5);
      final doc = await reopen(ref); // todo cargado
      final expected = <int>[0, 1, 2, 3, 4];
      doc.addSheet();
      expected.add(-1);
      Marks.add(doc, 5, 10);
      expected[5] = 10;
      doc.duplicateSheet(1);
      expected.insert(2, 1);
      doc.moveSheet(0, 4);
      expected.insert(4, expected.removeAt(0));
      doc.deleteSheet(1);
      expected.removeAt(1);
      doc.insertSheet(2);
      expected.insert(2, -1); // vacía
      Marks.add(doc, 2, 11);
      expected[2] = 11;
      doc.moveSheet(5, 0);
      expected.insert(0, expected.removeAt(5));
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      expect(pdfPageCount(pdf), expected.length);
      final pages = await real(t, () => pdfPageImages(pdf));
      for (var i = 0; i < expected.length; i++) {
        expect(Marks.found(pages[i], [0, 1, 2, 3, 4, 10, 11]), [expected[i]], reason: 'página ${i + 1}, orden esperado $expected');
      }
    }, skip: skip != null);

    rt('las mismas operaciones sobre un documento con huecos sin cargar', (t) async {
      final ref = await saved(8);
      final doc = await reopen(ref, radius: 1);
      // se cargan las que se tocan
      await store.loadSheets(doc, [doc.sheets[2].id, doc.sheets[6].id]);
      final expected = [0, 1, 2, 3, 4, 5, 6, 7];
      doc.duplicateSheet(2);
      expected.insert(3, 2);
      doc.deleteSheet(0);
      expected.removeAt(0);
      doc.moveSheet(5, 1);
      expected.insert(1, expected.removeAt(5));
      doc.addSheet();
      expected.add(-1);
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      final pages = await real(t, () => pdfPageImages(pdf));
      expect(pages.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(Marks.found(pages[i], [0, 1, 2, 3, 4, 5, 6, 7]), expected[i] < 0 ? isEmpty : [expected[i]], reason: 'página ${i + 1}, orden esperado $expected');
      }
    }, skip: skip != null);
  });

  group('secciones y selección', () {
    /// Un cuaderno de 3 secciones (3, 2 y 4 hojas) guardado: marcas 0-2, 10-11 y 20-23.
    Future<Notebook> threeSections() async {
      final nb = Notebook.create('Secciones');
      final a = nb.activeSection;
      final b = nb.addSection('Dos'), c = nb.addSection('Tres');
      nb.otherSheets.clear();
      while (nb.sheets.length < 3) {
        nb.sheets.add(nb.newSheet());
      }
      for (var i = 0; i < 2; i++) {
        nb.otherSheets.add(nb.newSheet(section: b.id));
      }
      for (var i = 0; i < 4; i++) {
        nb.otherSheets.add(nb.newSheet(section: c.id));
      }
      final d = NotebookDoc(nb);
      for (var k = 0; k < 3; k++) {
        Marks.add(d, k, k);
      }
      await store.saveNotebook(d);
      // las hojas de las otras secciones se escriben abriéndolas una por una
      for (final (sec, base, n) in [(b, 10, 2), (c, 20, 4)]) {
        nb.activate(sec.id);
        final nd = NotebookDoc(nb);
        for (var k = 0; k < n; k++) {
          Marks.add(nd, k, base + k);
        }
        await store.saveNotebook(nd);
      }
      nb.activate(a.id);
      return nb;
    }

    rt('todas las secciones, en su orden; las elegidas; solo una; y la sección abierta puede ser otra', (t) async {
      final nb = await threeSections();
      final all = [0, 1, 2, 10, 11, 20, 21, 22, 23];
      for (final active in [0, 1, 2]) {
        nb.activate(nb.sections[active].id);
        final doc = await store.openNotebook(nb, radius: 1000);
        final pdf = await real(t, () => buildNotebookPdf(store, doc));
        expectMarks(await real(t, () => pdfPageImages(pdf)), all, all: all, why: '(abierta la sección $active)');
        final two = await real(t, () => buildNotebookPdf(store, doc, sections: {nb.sections[2].id, nb.sections[0].id}));
        expectMarks(await real(t, () => pdfPageImages(two)), [0, 1, 2, 20, 21, 22, 23], all: all, why: '(secciones 0 y 2, abierta $active)');
        final one = await real(t, () => buildNotebookPdf(store, doc, sections: {nb.sections[1].id}));
        expectMarks(await real(t, () => pdfPageImages(one)), [10, 11], all: all, why: '(sección 1, abierta $active)');
      }
    }, skip: skip != null);

    rt('only: las hojas pedidas de la sección abierta, en el orden de la tira', (t) async {
      final nb = await threeSections();
      nb.activate(nb.sections[2].id);
      final doc = await store.openNotebook(nb, radius: 0);
      final all = [20, 21, 22, 23];
      final pdf = await real(t, () => buildNotebookPdf(store, doc, only: [3, 1]));
      expectMarks(await real(t, () => pdfPageImages(pdf)), [21, 23], all: all);
      final one = await real(t, () => buildNotebookPdf(store, doc, only: [2]));
      expectMarks(await real(t, () => pdfPageImages(one)), [22], all: all);
    }, skip: skip != null);
  });

  group('lienzo infinito', () {
    rt('una página por cada celda con algo, en orden de filas', (t) async {
      final nb = Notebook.create('Lienzo', canvas: true);
      while (nb.sheets.length < 5) {
        nb.sheets.add(nb.newSheet());
      }
      final d = NotebookDoc(nb);
      // marcas en las filas 0, 2 y 4 (la 1 y la 3 quedan vacías: no tienen página)
      for (final (row, m) in [(0, 0), (2, 1), (4, 2)]) {
        final s = Marks.stroke('m$m', m, row * kSheetStep)..z = d.nextZ();
        d.strokes[s.id] = s;
      }
      final pdf = await real(t, () => buildNotebookPdf(store, d));
      expect(pdfPageCount(pdf), 3);
      expectMarks(await real(t, () => pdfPageImages(pdf)), [0, 1, 2]);
    }, skip: skip != null);
  });

  group('links', () {
    rt('el link a una hoja va a la página de esa hoja', (t) async {
      final doc = await saved(4);
      doc.items['l'] = Item('l', 'link', 100, 900, 300, 60, text: 'sheet:${doc.sheets[3].id}');
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      final s = String.fromCharCodes(pdf);
      // la página 4 es la que tiene el ancla de la hoja 4, y la anotación apunta a esa ancla
      expect(s, contains('sheet-${doc.sheets[3].id}'));
      expect(RegExp(r'/Subtype\s*/Link').allMatches(s).length, 1);
      for (var k = 0; k < 3; k++) {
        expect(RegExp('sheet-${doc.sheets[k].id}').allMatches(s).length, greaterThanOrEqualTo(1));
      }
    });
  });

  group('lecturas inestables del motor gráfico', () {
    // Android + Impeller/Vulkan (Flutter 3.50, flutter/flutter#196627 y #196980): la primera lectura de píxeles de una
    // imagen recién dibujada a veces devuelve la imagen ANTERIOR o píxeles transparentes; una segunda lectura sale bien.
    final original = rasterReader;
    tearDown(() => rasterReader = original);

    rt('si la primera lectura de cada hoja es la de la hoja anterior (o transparente), el PDF igual sale bien', (t) async {
      final doc = await saved(6);
      ByteData? prev;
      ui.Image? last;
      rasterReader = (img) async {
        final good = await original(img);
        final copy = ByteData.sublistView(Uint8List.fromList(good!.buffer.asUint8List()));
        final first = !identical(last, img);
        last = img;
        if (!first) return copy;
        final bad = prev ?? ByteData(copy.lengthInBytes); // la 1ª vez, todo transparente
        prev = copy;
        return bad;
      };
      final before = rasterRetries;
      final pdf = await real(t, () => buildNotebookPdf(store, doc));
      expectMarks(await real(t, () => pdfPageImages(pdf)), [0, 1, 2, 3, 4, 5]);
      expect(rasterRetries, greaterThan(before), reason: 'el test no ejercitó el reintento');
    }, skip: skip != null);

    rt('control: creyendo la primera lectura (como antes) el mismo motor da páginas que no son su hoja', (t) async {
      final doc = await saved(4);
      ByteData? prev;
      ui.Image? last;
      rasterStableReads = 1;
      addTearDown(() => rasterStableReads = 2);
      rasterReader = (img) async {
        final good = await original(img);
        final copy = ByteData.sublistView(Uint8List.fromList(good!.buffer.asUint8List()));
        final first = !identical(last, img);
        last = img;
        if (!first) return copy;
        final bad = prev ?? copy;
        prev = copy;
        return bad; // la hoja anterior
      };
      final pdf = await buildNotebookPdf(store, doc);
      final pages = await pdfPageImages(pdf);
      expect([for (final p in pages) Marks.found(p, [0, 1, 2, 3]).single], [0, 0, 1, 2], reason: 'cada página muestra la hoja anterior');
    }, skip: skip != null);

    rt('si el motor SIEMPRE devuelve basura, el export falla con un error claro en vez de dar páginas rotas', (t) async {
      final doc = await saved(2);
      var n = 0;
      rasterReader = (img) async => ByteData(1654 * 2339 * 4)..setUint8(0, n++ % 250); // nunca opaca ni dos veces igual
      await expectLater(buildNotebookPdf(store, doc), throwsA(isA<StateError>()));
    });
  });
}
