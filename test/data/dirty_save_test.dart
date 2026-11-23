import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/history.dart';
import 'package:apuntes/editor/items_layer.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/text_blocks.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Red de seguridad del guardado incremental: después de cada operación, lo que quedó en disco tiene que
/// ser IGUAL a codificar el documento entero en memoria. Si alguna operación cambia una hoja y no la marca
/// sucia, la hoja vieja queda en el disco y estos tests fallan (pérdida de datos silenciosa).
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('apuntes_dirty');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.deleteSync(recursive: true));

  String md5of(List<int> b) => md5.convert(b).toString();

  /// Lo que hay en disco == codificar todo el documento (hoja por hoja, y notebook.json).
  void verify(NotebookDoc doc, String ctx) {
    final nb = doc.nb;
    final full = doc.splitBySheet();
    for (var k = 0; k < nb.sheets.length; k++) {
      final f = store.sheetFile(nb.id, nb.sheets[k].id);
      expect(f.existsSync(), isTrue, reason: '$ctx: falta el archivo de la hoja $k');
      expect(md5of(f.readAsBytesSync()), md5of(encodeSheet(full[k])),
          reason: '$ctx: la hoja $k en disco no es igual a la de memoria (¿no se marcó sucia?)');
    }
    final files = Directory('${store.nbDir(nb.id).path}/sheets')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toSet();
    expect(files, {for (final m in nb.sheets) '${m.id}.sheet'}, reason: '$ctx: sobran o faltan archivos de hojas');
    final j = jsonDecode(File('${store.nbDir(nb.id).path}/notebook.json').readAsStringSync()) as Map;
    expect(jsonEncode(j), jsonEncode(nb.sheetsJson()), reason: '$ctx: notebook.json distinto');
  }

  Future<void> saveAndVerify(NotebookDoc doc, String ctx) async {
    await store.saveNotebook(doc);
    verify(doc, ctx);
  }

  group('guardado de hojas sucias (solo documento)', () {
    NotebookDoc armado(int sheets) {
      final nb = Notebook.create('T');
      while (nb.sheets.length < sheets) {
        nb.sheets.add(nb.newSheet());
      }
      return NotebookDoc(nb);
    }

    Stroke trazo(Random r, {double? y}) {
      final x0 = 50 + r.nextDouble() * 600, y0 = y ?? r.nextDouble() * 4000;
      final pts = <double>[];
      for (var i = 0; i < 6; i++) {
        pts.addAll([x0 + i * 12, y0 + r.nextDouble() * 90, .5]);
      }
      return Stroke(newId('s'), 'pen', '#22211e', 2.6, pts);
    }

    test('después de cargar no hay nada sucio, y un guardado sin cambios no escribe', () async {
      final doc = armado(4);
      doc.strokes['a'] = trazo(Random(1), y: 100);
      await saveAndVerify(doc, 'primero');
      final loaded = await store.loadNotebook(Notebook(doc.id, 'T'));
      expect(loaded.hasDirty, isFalse);
      final dir = Directory('${store.nbDir(doc.id).path}/sheets');
      final before = {for (final f in dir.listSync().whereType<File>()) f.path: f.statSync().modified};
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.saveNotebook(loaded);
      for (final f in dir.listSync().whereType<File>()) {
        expect(f.statSync().modified, before[f.path], reason: 'no se tocó nada: no se reescribe');
      }
    });

    test('un trazo nuevo reescribe solo su hoja', () async {
      final doc = armado(5);
      for (var k = 0; k < 5; k++) {
        doc.strokes['s$k'] = Stroke('s$k', 'pen', '#000000', 2, [10, k * kSheetStep + 100, .5, 90, k * kSheetStep + 140, .5]);
      }
      await saveAndVerify(doc, 'base');
      final revs = [for (final m in doc.sheets) m.rev];
      doc.strokes['nuevo'] = Stroke('nuevo', 'pen', '#000000', 2, [10, 2 * kSheetStep + 300, .5, 90, 2 * kSheetStep + 340, .5]);
      await saveAndVerify(doc, 'un trazo');
      expect([for (final m in doc.sheets) m.rev], [for (var k = 0; k < 5; k++) k == 2 ? revs[k] + 1 : revs[k]]);
    });

    test('lo que se marca sucio mientras se guarda queda para el próximo guardado', () async {
      final doc = armado(3);
      doc.strokes['a'] = trazo(Random(2), y: 100);
      await saveAndVerify(doc, 'base');
      doc.strokes['b'] = trazo(Random(3), y: 100);
      final guardando = store.saveNotebook(doc); // toma lo sucio ya
      doc.strokes['c'] = trazo(Random(4), y: 2 * kSheetStep + 100); // se edita mientras se guarda
      doc.strokes['d'] = trazo(Random(5), y: 100);
      await guardando;
      await store.saveNotebook(doc); // el que pide el editor después de editar
      verify(doc, 'edición durante el guardado');
    });

    test('si el guardado falla, las hojas vuelven a sucias y el próximo guardado las escribe', () async {
      if (Platform.isWindows) return;
      final doc = armado(3);
      doc.strokes['a'] = trazo(Random(6), y: 100);
      await saveAndVerify(doc, 'base');
      doc.strokes['b'] = trazo(Random(7), y: 100);
      final dir = Directory('${store.nbDir(doc.id).path}/sheets');
      Process.runSync('chmod', ['500', dir.path]); // sin permiso de escritura: el guardado falla
      try {
        await expectLater(store.saveNotebook(doc), throwsA(anything));
      } finally {
        Process.runSync('chmod', ['700', dir.path]);
      }
      expect(doc.hasDirty, isTrue);
      await saveAndVerify(doc, 'reintento');
    });

    test('operaciones de hojas y z: mover, duplicar, borrar, insertar, reordenar', () async {
      final doc = armado(3);
      final r = Random(8);
      for (var k = 0; k < 3; k++) {
        doc.strokes['s$k'] = trazo(r, y: k * kSheetStep + 100);
        doc.texts['t$k'] = TextBlock('t$k', 90, doc.snapTextY(k * kSheetStep + 300), 800, 'hoja $k');
        doc.items['i$k'] = Item('i$k', 'sticky', 100, k * kSheetStep + 500, 200, 200, text: 'nota $k');
      }
      await saveAndVerify(doc, 'base');
      doc.moveSheet(0, 2);
      await saveAndVerify(doc, 'mover');
      doc.duplicateSheet(1);
      await saveAndVerify(doc, 'duplicar');
      doc.insertSheet(0);
      await saveAndVerify(doc, 'insertar al principio');
      doc.deleteSheet(2);
      await saveAndVerify(doc, 'borrar');
      doc.addSheet();
      await saveAndVerify(doc, 'agregar');
      doc.reorder({'s0', 't1'}, ZMove.front, (e) => const Rect.fromLTWH(0, 0, 10, 10));
      await saveAndVerify(doc, 'reordenar');
    });

    test('un trazo que pasa del final cae en la hoja nueva que lo contiene', () async {
      final doc = armado(1);
      await saveAndVerify(doc, 'base');
      // más abajo del final de la única hoja: queda en ella (se limita a la última)...
      final s = trazo(Random(9), y: kSheetStep + 200);
      doc.strokes[s.id] = s;
      await saveAndVerify(doc, 'pasado del final');
      // ...y al crecer el cuaderno pasa a la hoja nueva
      doc.growFor(s.bounds.bottom);
      expect(doc.sheetOfElement(s), 1);
      await saveAndVerify(doc, 'creció');
    });

    // Secuencias largas con operaciones del documento y deshacer / rehacer reales (EditAction).
    for (final seed in [11, 12, 13]) {
      test('secuencia aleatoria de 200 operaciones (semilla $seed)', () async {
        final r = Random(seed);
        final doc = armado(3);
        final undo = <EditAction>[], redo = <EditAction>[];

        String? pick(Iterable<String> ids) => ids.isEmpty ? null : ids.elementAt(r.nextInt(ids.length));
        double anyY() => r.nextDouble() * (doc.sheetCount * kSheetStep - 100);

        for (var step = 0; step < 200; step++) {
          final op = r.nextInt(15);
          var name = 'op$op';
          switch (op) {
            case 0 || 1: // trazo nuevo (a veces a caballo entre dos hojas)
              name = 'trazo';
              final s = trazo(r, y: anyY());
              s.z = doc.nextZ();
              doc.strokes[s.id] = s;
              undo.add(EditAction(added: [s]));
              redo.clear();
              doc.growFor(s.bounds.bottom);
            case 2: // goma
              name = 'goma';
              final id = pick(doc.strokes.keys);
              if (id == null) continue;
              final s = doc.strokes.remove(id)!;
              undo.add(EditAction(removed: [s]));
              redo.clear();
            case 3: // mover trazos a otra hoja (como soltar una selección)
              name = 'mover trazos';
              final ids = doc.strokes.keys.where((_) => r.nextInt(3) == 0).toList();
              if (ids.isEmpty) continue;
              final d = Offset(r.nextDouble() * 100, (r.nextDouble() - .4) * 3000);
              final removed = <Stroke>[], added = <Stroke>[];
              for (final id in ids) {
                final s = doc.strokes.remove(id)!;
                final m = s.moved(d);
                removed.add(s);
                added.add(m);
                doc.strokes[id] = m;
              }
              undo.add(EditAction(removed: removed, added: added));
              redo.clear();
              for (final s in added) {
                doc.growFor(s.bounds.bottom);
              }
            case 4: // texto nuevo
              name = 'texto nuevo';
              final t = TextBlock(newId('t'), 40 + r.nextDouble() * 400, doc.snapTextY(anyY()), 500, 'texto ${r.nextInt(99)}')
                ..z = doc.nextZ();
              doc.texts[t.id] = t;
              undo.add(EditAction(textBefore: {t.id: null}, textAfter: {t.id: t.copy()}));
              redo.clear();
            case 5: // editar un texto en el lugar (como al tipear)
              name = 'editar texto';
              final id = pick(doc.texts.keys);
              if (id == null) continue;
              final t = doc.texts[id]!;
              t.text = '${t.text} ${r.nextInt(99)}';
              doc.markDirtyElement(t);
            case 6: // mover un texto en el lugar (arrastre)
              name = 'mover texto';
              final id = pick(doc.texts.keys);
              if (id == null) continue;
              final t = doc.texts[id]!;
              doc.markDirtyElement(t);
              t.y = max(0.0, doc.snapTextY(t.y + (r.nextDouble() - .5) * 3000));
              doc.markDirtyElement(t);
            case 7: // nota / imagen
              name = 'item';
              final it = Item(newId('i'), r.nextBool() ? 'sticky' : 'image', 100, anyY(), 200, 150, text: 'n${r.nextInt(9)}', file: 'x.png')
                ..z = doc.nextZ();
              doc.items[it.id] = it;
              undo.add(EditAction(itemBefore: {it.id: null}, itemAfter: {it.id: it.copy()}));
              redo.clear();
            case 8: // redimensionar / editar una nota en el lugar
              name = 'redimensionar';
              final id = pick(doc.items.keys);
              if (id == null) continue;
              final it = doc.items[id]!;
              doc.markDirtyElement(it);
              it.w += 20;
              it.text = '${it.text}!';
              doc.markDirtyElement(it);
            case 9: // duplicar lo seleccionado (copias arriba de todo)
              name = 'duplicar';
              final ids = doc.strokes.keys.where((_) => r.nextInt(4) == 0).toList();
              if (ids.isEmpty) continue;
              final d = Offset(30, 30 + r.nextDouble() * 2000);
              final copias = [for (final id in ids) doc.strokes[id]!.moved(d, id: newId('s'))];
              doc.stackOnTop(copias);
              for (final s in copias) {
                doc.strokes[s.id] = s;
              }
              undo.add(EditAction(added: copias));
              redo.clear();
              for (final s in copias) {
                doc.growFor(s.bounds.bottom);
              }
            case 10: // orden de dibujo
              name = 'orden';
              final ids = {
                for (final id in [...doc.strokes.keys, ...doc.texts.keys, ...doc.items.keys])
                  if (r.nextInt(5) == 0) id
              };
              final ch = doc.reorder(ids, ZMove.values[r.nextInt(4)], (e) => switch (e) {
                    Stroke s => s.bounds,
                    Item i => i.rect,
                    _ => Rect.fromLTWH((e as TextBlock).x, e.y, 100, 40),
                  });
              if (ch != null) {
                undo.add(EditAction(zBefore: ch.before, zAfter: ch.after));
                redo.clear();
              }
            case 11 || 12: // deshacer / rehacer
              name = 'deshacer/rehacer';
              final from = op == 11 ? undo : redo, to = op == 11 ? redo : undo;
              if (from.isEmpty) continue;
              final a = from.removeLast();
              to.add(a);
              a.apply(doc, undo: op == 11, putText: (id, t) {
                if (t == null) {
                  doc.texts.remove(id);
                } else {
                  doc.texts[id] = t;
                }
              });
            case 13: // operaciones de hojas
              name = 'hojas';
              switch (r.nextInt(5)) {
                case 0:
                  doc.insertSheet(r.nextInt(doc.sheetCount + 1));
                case 1:
                  doc.duplicateSheet(r.nextInt(doc.sheetCount));
                case 2:
                  doc.moveSheet(r.nextInt(doc.sheetCount), r.nextInt(doc.sheetCount));
                case 3:
                  if (doc.sheetCount > 2) doc.deleteSheet(r.nextInt(doc.sheetCount));
                case 4:
                  doc.addSheet();
              }
              undo.clear(); // como el editor: las operaciones de hojas no se deshacen
              redo.clear();
            case 14: // estilo y datos de la hoja (van en notebook.json)
              name = 'estilo';
              final m = doc.sheets[r.nextInt(doc.sheetCount)];
              r.nextBool() ? m.setBg(const ['grid', 'dots', 'lined', 'blank'][r.nextInt(4)]) : m.title = 'h${r.nextInt(9)}';
          }
          // a veces se juntan varias operaciones en un solo guardado
          if (r.nextInt(4) != 0) await saveAndVerify(doc, 'semilla $seed, paso $step ($name)');
        }
        await saveAndVerify(doc, 'semilla $seed, final');
      });
    }
  });

  group('guardado de hojas sucias (con el editor de verdad)', () {
    NotebookDoc armado() {
      final nb = Notebook.create('T');
      while (nb.sheets.length < 3) {
        nb.sheets.add(nb.newSheet());
      }
      return NotebookDoc(nb);
    }

    // Visor alto: se ven las tres hojas a la vez (escala 1,1: cada hoja mide ~1630 px con su hueco)
    Future<PageEditorState> open(WidgetTester t, NotebookDoc doc) async {
      t.view.physicalSize = const Size(1600, 5300);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final tools = ToolState()..tool = Tool.pen;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {}),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      return t.state<PageEditorState>(find.byType(PageEditor));
    }

    Offset Function(Offset) mapper(PageEditorState ed) {
      final layers = find
          .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
          .evaluate()
          .map((e) => e.renderObject as RenderBox)
          .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
      return (Offset p) => layers.localToGlobal(p * ed.scale);
    }

    Future<void> save(WidgetTester t, NotebookDoc doc, String ctx) async {
      await t.pump(const Duration(milliseconds: 400)); // los temporizadores de "guardar al dejar de escribir"
      await t.runAsync(() => store.saveNotebook(doc));
      verify(doc, ctx);
    }

    Future<void> stylus(WidgetTester t, List<Offset> pts, {int buttons = 0}) async {
      final g = await t.startGesture(pts.first, kind: PointerDeviceKind.stylus, buttons: buttons);
      for (final p in pts.skip(1)) {
        await g.moveTo(p);
        await t.pump();
      }
      await g.up();
      await t.pump();
    }

    Future<void> tool(WidgetTester t, PageEditorState ed, Tool want) async {
      if (ed.ts.tool == want) return;
      final tip = switch (want) {
        Tool.pen => 'Lápiz · tocá de nuevo para opciones',
        Tool.hl => 'Resaltador · tocá de nuevo para opciones',
        Tool.paint => 'Decorador · tocá de nuevo para opciones',
        Tool.text => 'Texto con teclado',
        Tool.select => 'Seleccionar',
        Tool.title => 'Título para el índice',
      };
      await t.tap(find.byTooltip(tip));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('mover un texto con la agarradera a otra hoja; guardar en medio del arrastre', (t) async {
      final doc = armado();
      doc.texts['t'] = TextBlock('t', 100, doc.snapTextY(300), 600, 'hola');
      final ed = await open(t, doc);
      await t.runAsync(() => store.saveNotebook(doc));
      await tool(t, ed, Tool.text);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 100));
      final view = t.widget<TextBlockView>(find.byType(TextBlockView).first);
      view.onHandleDrag(Offset(0, (kSheetStep + 200) * ed.scale)); // a la segunda hoja
      await t.pump();
      await t.runAsync(() => store.saveNotebook(doc)); // se guarda a mitad del arrastre
      view.onHandleDrag(Offset(0, (kSheetStep + 200) * ed.scale)); // sigue: a la tercera
      await t.pump();
      view.onHandleDragEnd();
      await t.pump();
      expect(doc.sheetOfElement(doc.texts['t']!), 2);
      await save(t, doc, 'agarradera');
    });

    testWidgets('arrastrar un texto seleccionado dos hojas más abajo, guardando a mitad; deshacer y rehacer', (t) async {
      final doc = armado();
      doc.texts['t'] = TextBlock('t', 100, doc.snapTextY(300), 600, 'hola');
      doc.items['i'] = Item('i', 'sticky', 500, 2 * kSheetStep + 600, 200, 150, text: 'nota');
      final ed = await open(t, doc);
      await t.runAsync(() => store.saveNotebook(doc));
      final map = mapper(ed);
      await tool(t, ed, Tool.select);
      await stylus(t, [map(const Offset(20, 200)), map(const Offset(900, 900))]);
      expect(ed.sel.texts, {'t'});
      expect(ed.sel.items, isEmpty);
      final c = map(ed.sel.bounds(doc)!.center);
      final to = c + Offset(0, 2 * kSheetStep * ed.scale);
      final g = await t.startGesture(c, kind: PointerDeviceKind.stylus);
      await g.moveTo(Offset.lerp(c, to, .5)!);
      await t.pump();
      expect(doc.sheetOfElement(doc.texts['t']!), 1);
      await t.runAsync(() => store.saveNotebook(doc)); // a mitad del arrastre
      await g.moveTo(to);
      await t.pump();
      await g.up();
      await t.pump();
      expect(doc.sheetOfElement(doc.texts['t']!), 2);
      await save(t, doc, 'soltar');
      await t.tap(find.byTooltip('Deshacer'));
      await t.pump();
      expect(doc.sheetOfElement(doc.texts['t']!), 0);
      await save(t, doc, 'deshacer');
      await t.tap(find.byTooltip('Rehacer'));
      await t.pump();
      await save(t, doc, 'rehacer');
    });

    testWidgets('redimensionar y escribir en una nota; mover la selección de una hoja a otra', (t) async {
      final doc = armado();
      doc.strokes['a'] = Stroke('a', 'pen', '#000000', 2, [200, 300, .5, 260, 330, .5, 320, 360, .5]);
      final ed = await open(t, doc);
      await save(t, doc, 'base');
      ed.insertItem(Item(newId('i'), 'sticky', 0, 0, 300, 200));
      await t.pump(const Duration(milliseconds: 200));
      await save(t, doc, 'nota');
      final it = doc.items.values.single;
      final w = it.w;
      await t.drag(find.byKey(const ValueKey('selHandle-br')), const Offset(50, 40));
      await t.pump();
      expect(it.w, isNot(w), reason: 'la agarradera tiene que haber cambiado el tamaño');
      await save(t, doc, 'redimensionar');
      await t.enterText(find.descendant(of: find.byType(StickyField), matching: find.byType(TextField)), 'apunte');
      await t.pump();
      expect(it.text, 'apunte');
      await save(t, doc, 'escribir en la nota');
      // seleccionar todo y llevarlo a la hoja de abajo
      final map = mapper(ed);
      await tool(t, ed, Tool.select);
      await stylus(t, [map(const Offset(5, 5)), map(const Offset(990, 900))]);
      expect(ed.sel.isEmpty, isFalse);
      final c = map(ed.sel.bounds(doc)!.center);
      await stylus(t, [c, c + Offset(0, (kSheetStep + 100) * ed.scale)]);
      await save(t, doc, 'mover selección a otra hoja');
      expect(doc.sheetOfElement(it), 1);
    });

    for (final seed in [21, 22, 23, 24]) {
      testWidgets('secuencia aleatoria con el editor (semilla $seed)', (t) async {
        final r = Random(seed);
        final doc = armado();
        final ed = await open(t, doc);
        await save(t, doc, 'semilla $seed, base');

        Offset pt(Offset Function(Offset) map) => map(Offset(60 + r.nextDouble() * 880, r.nextDouble() * 3 * kSheetStep * .92));
        Future<void> pump() => t.pump(const Duration(milliseconds: 150));
        Future<void> unfocus() async {
          FocusManager.instance.primaryFocus?.unfocus();
          await pump();
        }

        for (var step = 0; step < 50; step++) {
          final op = r.nextInt(16);
          var name = 'op$op';
          final map = mapper(ed);
          switch (op) {
            case 0 || 1 || 2: // dibujar
              name = 'dibujar';
              await unfocus();
              await tool(t, ed, Tool.pen);
              final a = pt(map);
              await stylus(t, [for (var i = 0; i < 6; i++) a + Offset(i * 25, r.nextDouble() * 120)]);
            case 3: // borrar con goma sobre un trazo
              name = 'goma';
              if (doc.strokes.isEmpty) continue;
              await unfocus();
              await tool(t, ed, Tool.pen);
              final s = doc.strokes.values.elementAt(r.nextInt(doc.strokes.length));
              final i = r.nextInt(s.n);
              final c = map(Offset(s.pts[i * 3], s.pts[i * 3 + 1]));
              await stylus(t, [c, c + const Offset(3, 3), c - const Offset(3, 3)], buttons: kSecondaryStylusButton);
            case 4 || 5: // seleccionar un rectángulo (ventana o captura)
              name = 'seleccionar';
              await unfocus();
              await tool(t, ed, Tool.select);
              final a = Offset(60 + r.nextDouble() * 700, r.nextDouble() * 2.6 * kSheetStep);
              final b = a + Offset((r.nextBool() ? 1 : -1) * (150 + r.nextDouble() * 500), 150 + r.nextDouble() * 1200);
              await stylus(t, [map(a), map(b)]);
            case 6 || 7: // mover lo seleccionado (a veces a otra hoja)
              name = 'mover selección';
              if (ed.sel.isEmpty) continue;
              final rect = ed.sel.bounds(doc)!;
              final c = map(rect.center);
              final dy = (r.nextDouble() - .3) * 2200;
              final to = Offset(c.dx + (r.nextDouble() - .5) * 400, c.dy + dy * ed.scale);
              if (to.dy < 120 || to.dy > 5000) continue;
              await stylus(t, [c, Offset.lerp(c, to, .3)!, Offset.lerp(c, to, .7)!, to]);
            case 8: // menú de la selección
              name = 'menú de la selección';
              if (ed.sel.isEmpty) continue;
              final accion = r.nextInt(5);
              if (accion == 4) {
                await t.tap(find.byKey(const Key('selOrder')), warnIfMissed: false);
                await t.pump(const Duration(milliseconds: 300));
                final f = find.text(const ['Traer al frente', 'Subir uno', 'Bajar uno', 'Enviar al fondo'][r.nextInt(4)]);
                if (f.evaluate().isEmpty) continue;
                await t.tap(f);
              } else {
                final f = find.text(const ['Copiar', 'Cortar', 'Duplicar', 'Eliminar'][accion]);
                if (f.evaluate().isEmpty) continue;
                name = 'menú: ${const ['copiar', 'cortar', 'duplicar', 'eliminar'][accion]}';
                await t.tap(f, warnIfMissed: false);
              }
              await pump();
            case 9: // pegar
              name = 'pegar';
              if (ed.ts.clipboard.isEmpty) continue;
              await unfocus();
              final f = find.byTooltip('Pegar');
              if (f.evaluate().isEmpty) continue;
              await t.tap(f);
              await pump();
            case 10 || 11: // deshacer / rehacer
              name = 'deshacer/rehacer';
              await unfocus();
              final undo = op == 10;
              if (!(undo ? ed.history.canUndo : ed.history.canRedo)) continue;
              await t.tap(find.byTooltip(undo ? 'Deshacer' : 'Rehacer'));
              await pump();
            case 12: // texto nuevo y tipearlo
              name = 'texto';
              await unfocus();
              await tool(t, ed, Tool.select);
              final antes = doc.texts.keys.toSet();
              await tool(t, ed, Tool.text);
              final nuevo = doc.texts.keys.toSet().difference(antes);
              if (nuevo.isEmpty) continue;
              final id = nuevo.single;
              await t.enterText(find.byKey(Key('para-$id-0')), 'uno ${r.nextInt(99)}');
              await t.pump();
              if (r.nextBool()) {
                await t.enterText(find.byKey(Key('para-$id-0')), 'uno\n');
                await t.pump(const Duration(milliseconds: 100));
                await t.enterText(find.byKey(Key('para-$id-1')), 'dos');
                await t.pump();
              }
            case 13: // editar un texto que ya estaba
              name = 'editar texto';
              if (doc.texts.isEmpty) continue;
              final id = doc.texts.keys.elementAt(r.nextInt(doc.texts.length));
              await unfocus();
              await tool(t, ed, Tool.text);
              final f = find.byKey(Key('para-$id-0'));
              if (f.evaluate().isEmpty) continue;
              await t.enterText(f, 'editado ${r.nextInt(99)}');
              await t.pump();
            case 14: // nota
              name = 'nota';
              await unfocus();
              ed.insertItem(Item(newId('i'), 'sticky', 0, 0, 260, 180, text: 'n${r.nextInt(9)}'));
              await pump();
            case 15: // operaciones de hojas (como las hace la pantalla del cuaderno)
              name = 'hojas';
              await unfocus();
              if (r.nextInt(3) == 0) {
                doc.sheets[r.nextInt(doc.sheetCount)].setBg(const ['grid', 'dots', 'blank'][r.nextInt(3)]);
              } else {
                switch (r.nextInt(5)) {
                  case 0:
                    doc.insertSheet(r.nextInt(doc.sheetCount + 1));
                  case 1:
                    doc.duplicateSheet(r.nextInt(doc.sheetCount));
                  case 2:
                    doc.moveSheet(r.nextInt(doc.sheetCount), r.nextInt(doc.sheetCount));
                  case 3:
                    if (doc.sheetCount > 3) doc.deleteSheet(r.nextInt(doc.sheetCount));
                  case 4:
                    doc.addSheet();
                }
                ed.sheetsChanged();
              }
              await pump();
          }
          // un guardado cada tanto junta varias operaciones
          if (r.nextInt(4) != 0) await save(t, doc, 'semilla $seed, paso $step ($name)');
        }
        await unfocus();
        await save(t, doc, 'semilla $seed, final');
        expect(doc.strokes.length + doc.texts.length + doc.items.length, greaterThan(0));
      });
    }
  });
}
