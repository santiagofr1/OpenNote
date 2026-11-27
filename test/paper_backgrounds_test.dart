import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/templates.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/paper.dart';
import 'package:apuntes/rendering/sheet_render.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('milimetrado', () {
    test('mmYs: una línea por mm, pesos 0/1/2 desde el origen', () {
      final ys = mmYs(size: 'a4'), u = unitsPerMm('a4');
      // origen 3,5 mm: primera línea en 0,5 mm; última <= 297 mm
      expect(ys.first.$1, closeTo(0.5 * u, 1e-9));
      expect(ys.length, 297);
      final o = gridOriginMm('mm', 10);
      for (final (y, w) in ys) {
        final n = (y / u - o).round();
        expect(y, closeTo((o + n) * u, 1e-9));
        expect(w, n % 10 == 0 ? 2 : (n % 5 == 0 ? 1 : 0));
      }
      expect(ys.where((e) => e.$2 == 2).length, 30);
    });
    test('mmXs: sin bordes, peso 2 cada 10 mm desde el borde izquierdo', () {
      final xs = mmXs(size: 'a4'), u = unitsPerMm('a4');
      expect(xs.length, 209);
      expect(xs.first.$1, closeTo(u, 1e-9));
      expect(xs[9].$2, 2);
      expect(xs[4].$2, 1);
      expect(xs[0].$2, 0);
      expect(xs[19].$1, 20 * u); // multiplicado, no sumado
    });
    test('axesOrigin cae sobre la cuadrícula, cerca del centro', () {
      for (final sp in [5.0, 7.0]) {
        final (x, y) = axesOrigin(sp);
        expect(gridXs(sp).any((v) => (v - x).abs() < 1e-9), isTrue);
        expect(gridYs(sp).any((v) => (v - y).abs() < 1e-9), isTrue);
        expect((x - kW / 2).abs(), lessThan(sp * unitsPerMm('a4')));
        expect((y - kSheetH / 2).abs(), lessThan(sp * unitsPerMm('a4')));
      }
    });
    test('espaciados y renglón de los fondos nuevos', () {
      expect(spacingsFor('axes'), kGridSpacings);
      expect(spacingsFor('mm'), isEmpty);
      expect(defaultSpacing('axes'), 5);
      expect(spacingsFor('cornell'), kLinedSpacings);
      expect(spacingsFor('todo'), kLinedSpacings);
      for (final b in ['staff', 'weekly', 'monthly', 'image']) {
        expect(spacingsFor(b), isEmpty);
        expect(textLineMm(b, 8), 8);
      }
      expect(defaultSpacing('cornell'), 8);
      expect(textLineMm('mm', 8), 10);
      expect(textLineMm('cornell', 7), 7);
      expect(textLineMm('todo', 10), 10);
      expect(textLineMm('axes', 5), 10);
      expect(gridOriginMm('mm', 8), closeTo(3.5, 1e-9));
      expect(gridOriginMm('axes', 5), gridOriginMm('grid', 5));
    });
  });

  test('containRect: imagen ancha y alta, centrada y sin deformar', () {
    final wide = containRect(2000, 500);
    expect(wide.width, closeTo(kW, 1e-9));
    expect(wide.width / wide.height, closeTo(4, 1e-9));
    expect(wide.center.dy, closeTo(kSheetH / 2, 1e-9));
    final tall = containRect(300, 4000);
    expect(tall.height, closeTo(kSheetH, 1e-9));
    expect(tall.width / tall.height, closeTo(300 / 4000, 1e-9));
    expect(tall.center.dx, closeTo(kW / 2, 1e-9));
  });

  test('SheetMeta: image en el json y setBg la limpia', () {
    final m = SheetMeta('h1', bg: 'image', image: 'm_1.png');
    final j = m.toJson();
    expect(j['image'], 'm_1.png');
    expect(SheetMeta.fromJson(j).image, 'm_1.png');
    expect(m.copy().image, 'm_1.png');
    expect(SheetMeta('h2').toJson().containsKey('image'), isFalse);
    m.setBg('grid');
    expect(m.image, isNull);
    final nb = Notebook('n', 'x', bg: 'image')..image = 'a.png';
    expect(Notebook.fromJson(nb.toJson()).image, 'a.png');
    expect(nb.newSheet().image, 'a.png');
  });

  test('paintPaperPattern no tira con ningún fondo nuevo', () {
    for (final size in ['a5', 'a4', 'a3']) {
      for (final bg in ['mm', 'axes', 'cornell', 'todo', 'staff', 'weekly', 'monthly', 'iso', 'hex', 'polar', 'semilog', 'calli', 'storyboard', 'guitartab', 'daily']) {
        for (final sp in [...spacingsFor(bg), if (spacingsFor(bg).isEmpty) 8.0]) {
          final rec = ui.PictureRecorder();
          paintPaperPattern(ui.Canvas(rec), bg, sp, size: size, ruleWidth: 1, marginWidth: 1.2);
          rec.endRecording().dispose();
        }
      }
    }
  });

  group('fondos de red, polar, semilog y plantillas de guías (issue #25)', () {
    const sizes = ['a5', 'a4', 'a3'];
    test('espaciados, valor por defecto y renglón de texto', () {
      for (final b in ['iso', 'hex']) {
        expect(spacingsFor(b), kGridSpacings);
        expect(defaultSpacing(b), 5);
        expect(validSpacing(b, 7), 7);
        expect(validSpacing(b, 8), 5);
        expect(textLineMm(b, 5), kBlankLineMm);
        expect(gridOriginMm(b, 5), 0);
      }
      for (final b in ['polar', 'semilog', 'calli', 'storyboard', 'guitartab', 'daily']) {
        expect(spacingsFor(b), isEmpty);
        expect(textLineMm(b, 8), kBlankLineMm);
      }
    });
    test('no pegan las formas a la cuadrícula', () {
      const p = Offset(123.4, 567.8);
      for (final b in ['iso', 'hex', 'polar', 'semilog', 'calli', 'storyboard', 'guitartab', 'daily']) {
        expect(snapToGrid(p, b, 5, 'a4'), p);
      }
    });
    test('isométrico: triángulos equiláteros que cubren la hoja', () {
      for (final sp in kGridSpacings) {
        expect(isoRowMm(sp), closeTo(sp * sqrt(3) / 2, 1e-9));
        final ys = isoYsMm(sp), h = paperHeightMm('a4');
        expect(ys.first, 0);
        expect(ys.last, greaterThanOrEqualTo(h - isoRowMm(sp)));
        final xs = isoDiagonalXsMm(sp);
        expect(xs.first, lessThanOrEqualTo(-h / sqrt(3) + 1e-9));
        expect(xs.last, greaterThanOrEqualTo(paperWidthMm('a4') + h / sqrt(3) - 1e-9));
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], closeTo(sp, 1e-9));
        }
      }
    });
    test('hexagonal: centros separados 1,5 lado en x y raíz de 3 lados en y, y todos tocan la hoja', () {
      for (final size in sizes) {
        final w = paperWidthMm(size), h = paperHeightMm(size), cs = hexCentersMm(5, size: size);
        expect(cs, isNotEmpty);
        for (final c in cs) {
          expect(c.dx - 5 <= w && c.dx + 5 >= 0, isTrue);
          expect(c.dy - 5 * sqrt(3) / 2 <= h && c.dy + 5 * sqrt(3) / 2 >= 0, isTrue);
        }
        expect(cs.any((c) => c.dy < 5 * sqrt(3) / 2), isTrue); // cubre el borde de arriba
        expect(cs.any((c) => c.dy > h - 5 * sqrt(3) / 2), isTrue);
      }
      final xs = {for (final c in hexCentersMm(7)) c.dx}.toList()..sort();
      expect(xs[1] - xs[0], closeTo(10.5, 1e-9));
    });
    test('polar: el círculo mayor y sus rótulos entran en la hoja', () {
      expect(polarMaxRadiusMm('a4'), 90);
      for (final size in sizes) {
        final r = polarMaxRadiusMm(size);
        expect(r % kPolarRingMm, 0);
        expect(r, greaterThan(0));
        expect(r + 8, lessThanOrEqualTo(paperWidthMm(size) / 2));
        expect(r + 8, lessThanOrEqualTo(paperHeightMm(size) / 2));
      }
    });
    test('semilog: eje x cada 5 mm, 3 décadas dentro de los márgenes de 12 mm', () {
      for (final size in sizes) {
        final a = semilogAreaMm(size), xs = semilogXsMm(size), ys = semilogYsMm(size);
        expect(a.left, 12);
        expect(a.top, 12);
        expect(a.bottom, closeTo(paperHeightMm(size) - 12, 1e-9));
        expect(a.right, lessThanOrEqualTo(paperWidthMm(size) - 12 + 1e-9));
        expect(a.width % 5, 0);
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i].$1 - xs[i - 1].$1, closeTo(5, 1e-9));
        }
        expect([for (final (_, w) in xs) w].take(3), [1, 0, 1]);
        expect(ys.length, 1 + 9 * kSemilogDecades);
        expect(ys.where((e) => e.$2 == 1).length, kSemilogDecades + 1);
        for (final (y, _) in ys) {
          expect(y, inInclusiveRange(a.top - 1e-9, a.bottom + 1e-9));
        }
        for (var i = 1; i < ys.length; i++) {
          expect(ys[i].$1, greaterThan(ys[i - 1].$1));
        }
        // dentro de una década las separaciones siguen log10: de la base (1) al 2 hay log10(2) de la década
        final dh = a.height / kSemilogDecades, n = ys.length;
        expect(ys[n - 1].$1 - ys[n - 2].$1, closeTo(dh * log(2) / ln10, 1e-9));
        expect(ys[n - 2].$1 - ys[n - 3].$1, closeTo(dh * (log(3) - log(2)) / ln10, 1e-9));
      }
    });
    test('caligrafía y tablatura: grupos que entran en la hoja, uno debajo del otro', () {
      for (final size in sizes) {
        final h = paperHeightMm(size);
        final cs = calliTopsMm(size), ts = tabTopsMm(size);
        expect(cs.length, greaterThan(2));
        expect(ts.length, greaterThan(2));
        expect(cs.last + 3 * kCalliStepMm, lessThanOrEqualTo(h - 15 + 1e-9));
        expect(ts.last + 5 * kTabStepMm, lessThanOrEqualTo(h - 15 + 1e-9));
        for (var i = 1; i < cs.length; i++) {
          expect(cs[i] - cs[i - 1], kCalliPitchMm);
        }
      }
      expect(kTabStepMm, 3);
      expect(kCalliSlantDeg, 55);
    });
    test('storyboard: 6 recuadros 16:9 dentro de la hoja y sin superponerse, con sus 3 renglones', () {
      for (final size in sizes) {
        final fs = storyboardFramesMm(size), w = paperWidthMm(size), h = paperHeightMm(size);
        expect(fs.length, 6);
        for (final f in fs) {
          expect(f.width / f.height, closeTo(16 / 9, 1e-9));
          expect(f.left, greaterThanOrEqualTo(kStoryMarginMm - 1e-9));
          expect(f.right, lessThanOrEqualTo(w - kStoryMarginMm + 1e-9));
          expect(f.bottom + 3 * kStoryLineMm, lessThanOrEqualTo(h - 12 + 1e-9));
        }
        for (var i = 0; i < fs.length; i++) {
          for (var j = i + 1; j < fs.length; j++) {
            expect(fs[i].overlaps(fs[j]), isFalse);
          }
        }
      }
    });
    test('planificador diario: 16 horas, columna a la izquierda (~2/3) y cajas a la derecha sin pisarse', () {
      expect(kDailyLastHour - kDailyFirstHour + 1, 16);
      for (final size in sizes) {
        final l = dailyLayoutMm(size), w = paperWidthMm(size), h = paperHeightMm(size);
        final sheet = Rect.fromLTWH(0, 0, w, h);
        for (final r in [l.hours, l.priorities, l.notes]) {
          expect(sheet.contains(r.topLeft) && sheet.contains(r.bottomRight), isTrue);
        }
        expect(l.hours.width / (w - 24), closeTo(2 / 3, 0.03));
        expect(l.hours.overlaps(l.priorities), isFalse);
        expect(l.hours.overlaps(l.notes), isFalse);
        expect(l.priorities.overlaps(l.notes), isFalse);
        expect(l.hourH * 16, closeTo(l.hours.height, 1e-9));
        expect(l.hourH / 2, greaterThan(5)); // un renglón por media hora con lugar para escribir
      }
    });
  });

  group('sync de plantillas', () {
    test('syncKind de templates/', () {
      expect(syncKind('templates/abc.json'), SyncKind.template);
      expect(syncKind('templates/../x.json'), isNull);
      expect(syncKind('templates/a/b.json'), isNull);
      expect(syncKind('templates/x.txt'), isNull);
      expect(syncKind('templates/.json'), isNull);
      expect(notebookIdOf('templates/abc.json'), isNull);
    });

    final dirs = <Directory>[];
    tearDownAll(() {
      for (final d in dirs) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });
    Future<Storage> device() async {
      final d = await Directory.systemTemp.createTemp('apuntes_tpl');
      dirs.add(d);
      final s = Storage(root: d);
      await s.init();
      return s;
    }

    test('una plantilla creada en un dispositivo aparece en el otro y el borrado también', () async {
      Storage.useIsolates = false;
      final a = await device(), b = await device(), r = FakeRemoteStore();
      expect(await readTemplates(a), isEmpty);
      final file = await a.addMedia([1, 2, 3], 'png');
      await a.writeSyncFile(templatePath('t1'), '{"id":"t1","name":"Mia","file":"$file","created":5}'.codeUnits);
      await a.writeSyncFile(templatePath('t2'), '{"id":"otro","name":"x","file":"$file"}'.codeUnits); // id distinto: se ignora
      expect([for (final t in await readTemplates(a)) t.id], ['t1']);
      await SyncEngine(a, r, account: 'a@b.c').sync();
      await SyncEngine(b, r, account: 'a@b.c').sync();
      final got = await readTemplates(b);
      expect(got.single.name, 'Mia');
      expect(await b.media(got.single.file).exists(), isTrue);
      await deleteTemplate(b, 't1');
      await SyncEngine(b, r, account: 'a@b.c').sync();
      await SyncEngine(a, r, account: 'a@b.c').sync();
      expect(await readTemplates(a), isEmpty);
    });
  });
}
