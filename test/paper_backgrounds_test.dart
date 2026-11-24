import 'dart:io';
import 'dart:ui' as ui;

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
      for (final bg in ['mm', 'axes', 'cornell', 'todo', 'staff', 'weekly', 'monthly']) {
        for (final sp in [...spacingsFor(bg), if (spacingsFor(bg).isEmpty) 8.0]) {
          final rec = ui.PictureRecorder();
          paintPaperPattern(ui.Canvas(rec), bg, sp, size: size, ruleWidth: 1, marginWidth: 1.2);
          rec.endRecording().dispose();
        }
      }
    }
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
