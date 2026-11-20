import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/rendering/sheet_render.dart';
import 'package:apuntes/screens/notebook/notebook_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga perezosa con la UI de verdad: un cuaderno de 30 hojas del que solo se leen las cercanas.
void main() {
  late Directory root;
  const sheets = 30;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_lazy_ui');
  });
  tearDown(() async {
    Storage.useIsolates = true;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester t, bool Function() ok, {int max = 150}) async {
    for (var i = 0; i < max && !ok(); i++) {
      await settle(t, 100);
    }
  }

  /// Un cuaderno de 30 hojas en disco, con un texto en cada una.
  Future<Notebook> seed() async {
    final nb = Notebook.create('Largo');
    while (nb.sheets.length < sheets) {
      nb.sheets.add(nb.newSheet());
    }
    nb.sheets[20].title = 'Veinte';
    final d = NotebookDoc(nb);
    for (var k = 0; k < sheets; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
    }
    d.strokes['s7'] = Stroke('s7', 'pen', '#22211e', 2.6, [100, 7 * kSheetStep + 300, .5, 200, 7 * kSheetStep + 340, .5, 300, 7 * kSheetStep + 300, .5]);
    await Future(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveNotebook(d);
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
    return nb;
  }

  Future<PageEditorState> open(WidgetTester t, {Size size = const Size(1600, 1000)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(seed);
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, () => find.byKey(const Key('nb-Largo')).evaluate().isNotEmpty);
    await t.tap(find.byKey(const Key('nb-Largo')));
    await until(t, () => find.byType(PageEditor).evaluate().isNotEmpty);
    await settle(t, 400);
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  /// Lo que hay en disco, leído con otra Storage y todo cargado.
  Future<NotebookDoc> fromDisk(WidgetTester t) async => (await t.runAsync(() async {
        final s = Storage(root: root);
        await s.init();
        final nb = (await s.loadIndex()).notebooks.single;
        return s.loadNotebook(nb);
      }))!;

  Map<String, List<int>> sheetBytes() => {
        for (final f in Directory('${root.path}/notebooks').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.sheet')) f.uri.pathSegments.last: f.readAsBytesSync()
      };

  testWidgets('abrir carga solo lo cercano; scrollear al final carga esas hojas y suelta las del principio; nada se pierde', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    expect(doc.sheetCount, sheets);
    expect(doc.loadedSheets.length, lessThan(8), reason: 'no se leyó todo el cuaderno');
    expect(doc.isLoadedAt(0), isTrue);
    expect(doc.isLoadedAt(sheets - 1), isFalse);
    final seeded = sheetBytes();
    expect(seeded.length, sheets);

    // al final: se cargan las últimas y se sueltan las primeras
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent);
    await until(t, () => doc.isLoadedAt(sheets - 1) && !doc.isLoadedAt(0));
    await settle(t, 300);
    expect(doc.isLoadedAt(sheets - 1), isTrue);
    expect(doc.isLoadedAt(sheets - 2), isTrue);
    expect(doc.isLoadedAt(0), isFalse, reason: 'la hoja 1 quedó lejos: se soltó');
    expect(doc.texts.containsKey('t0'), isFalse);
    expect(doc.texts['t${sheets - 1}']!.text, 'hoja ${sheets - 1}');
    expect(doc.loadedSheets.length, lessThan(14), reason: 'no se acumulan las hojas cargadas');

    // escribir ahí: una nota en el centro de lo que se ve
    ed.insertItem(Item(newId('i'), 'sticky', 0, 0, 300, 200, text: 'apunte final'));
    await settle(t, 1500); // se guarda solo (600 ms después del cambio)
    final noteId = doc.items.keys.single;

    // volver arriba: se carga la hoja 1 de nuevo y vuelve a verse lo que había
    ed.scroll.jumpTo(0);
    await until(t, () => doc.isLoadedAt(0));
    await settle(t, 300);
    expect(doc.texts['t0']!.text, 'hoja 0');
    expect(doc.isLoadedAt(sheets - 1), isTrue, reason: 'la hoja de la nota está en el historial de deshacer: no se suelta');

    // en disco: todo está; las hojas que nadie tocó quedaron byte por byte como estaban
    final disk = await fromDisk(t);
    expect(disk.texts.length, sheets);
    for (var k = 0; k < sheets; k++) {
      expect(disk.texts['t$k']!.text, 'hoja $k');
    }
    expect(disk.items[noteId]!.text, 'apunte final');
    expect(disk.strokes.keys, ['s7']);
    final after = sheetBytes();
    expect(after.length, sheets + 1, reason: 'la nota cerca del final hizo crecer el cuaderno una hoja');
    var changed = 0;
    for (final e in seeded.entries) {
      if (after[e.key].toString() != e.value.toString()) changed++;
    }
    expect(changed, 1, reason: 'de las hojas que ya estaban, solo se reescribió la de la nota');
  });

  testWidgets('deshacer funciona aunque se haya scrolleado lejos (las hojas del historial siguen en memoria)', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent);
    await until(t, () => doc.isLoadedAt(sheets - 1));
    ed.insertItem(Item(newId('i'), 'sticky', 0, 0, 300, 200, text: 'nota'));
    await settle(t, 1200);
    expect(doc.items.length, 1);
    ed.scroll.jumpTo(0);
    await settle(t, 3500); // tiempo de sobra para soltar hojas lejanas
    expect(doc.isLoadedAt(sheets - 1), isTrue, reason: 'fijada por el historial');
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 800);
    expect(doc.items, isEmpty);
    await settle(t, 3500); // ya sin historial que la fije y con el cambio guardado, se puede soltar
    final disk = await fromDisk(t);
    expect(disk.items, isEmpty, reason: 'el deshacer también se guardó');
    expect(disk.texts.length, sheets);
  });

  testWidgets('dibujar con el lápiz sobre una hoja que todavía no cargó no hace nada; al cargar sí', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    // el cuaderno abre en la hoja 1; se salta a una hoja sin cargar y, sin esperar, se dibuja encima
    ed.scroll.jumpTo(15 * kSheetStep * ed.scale);
    await t.pump();
    final c = t.getCenter(find.byType(PageEditor));
    if (!doc.isLoadedAt(15)) {
      final g = await t.startGesture(c, kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(c + Offset(i * 12.0, 0));
        await t.pump();
      }
      await g.up();
      await t.pump();
      expect(doc.strokes.keys.where((id) => id != 's7'), isEmpty, reason: 'el trazo sobre una hoja sin cargar se ignora');
    }
    await until(t, () => doc.isLoadedAt(15));
    await settle(t, 300);
    final g = await t.startGesture(c, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(c + Offset(i * 12.0, 0));
      await t.pump();
    }
    await g.up();
    await t.pump();
    expect(doc.strokes.keys.where((id) => id != 's7').length, 1, reason: 'ya cargada, se escribe');
    await settle(t, 1000); // el guardado automático
  });

  testWidgets('la búsqueda encuentra un texto de una hoja sin cargar y al tocarlo la carga y va ahí', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    expect(doc.isLoadedAt(20), isFalse);
    final s = t.state<NotebookScreenState>(find.byType(NotebookScreen));
    await s.runMore('search');
    await t.pump();
    await t.enterText(find.byKey(const Key('searchField')), 'hoja 20');
    await until(t, () => find.byKey(const Key('hit-t20')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('hit-t20')), findsOneWidget);
    expect(doc.isLoadedAt(20), isFalse, reason: 'buscar no deja hojas cargadas');
    // y por título de hoja
    await t.enterText(find.byKey(const Key('searchField')), 'veinte');
    await until(t, () => find.byKey(Key('hit-${doc.sheets[20].id}')).evaluate().isNotEmpty);
    expect(find.byKey(Key('hit-${doc.sheets[20].id}')), findsOneWidget);
    await t.enterText(find.byKey(const Key('searchField')), 'hoja 20');
    await until(t, () => find.byKey(const Key('hit-t20')).evaluate().isNotEmpty);
    await t.tap(find.byKey(const Key('hit-t20')));
    await until(t, () => doc.isLoadedAt(20) && ed.sel.texts.contains('t20'));
    await settle(t, 600);
    expect(ed.sel.texts, {'t20'});
    expect(ed.visibleSheet, 20);
  });

  testWidgets('el panel muestra la miniatura de una hoja que no está cargada (leída de disco)', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    final s = t.state<NotebookScreenState>(find.byType(NotebookScreen));
    expect(doc.isLoadedAt(6), isFalse);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 800);
    expect(find.byKey(const Key('thumb-7')), findsOneWidget);
    await until(t, () => s.thumbs.length > 0);
    // dibuja la hoja de disco (con su texto), no una hoja en blanco
    SheetThumbPainter? painter() {
      for (final w in t.widgetList<CustomPaint>(find.descendant(of: find.byKey(const Key('thumb-8')), matching: find.byType(CustomPaint)))) {
        final p = w.painter;
        if (p is SheetThumbPainter) return p;
      }
      return null;
    }

    await until(t, () => (painter()?.doc.texts.length ?? 0) > 0);
    expect(painter()!.doc.texts.values.single.text, 'hoja 7');
    expect(painter()!.doc.strokes.length, 1, reason: 'la hoja 8 (índice 7) tiene el trazo');
    expect(doc.isLoadedAt(7), isFalse, reason: 'la miniatura no carga la hoja');
  });

  testWidgets('exportar a PDF un cuaderno con pocas hojas cargadas da todas las hojas', (t) async {
    final ed = await open(t);
    final doc = ed.doc;
    expect(doc.loadedSheets.length, lessThan(sheets));
    // una hoja cargada con un cambio sin guardar: se exporta lo de memoria
    ed.doc.texts['t0']!.text = 'hoja 0 editada';
    doc.markDirtyElement(doc.texts['t0']!);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final progress = <int>[];
    final bytes = await t.runAsync(() => buildNotebookPdf(store, doc, onProgress: (a, b) => progress.add(a)));
    expect(progress.length, sheets);
    final text = String.fromCharCodes(bytes!);
    expect(RegExp(r'/Type\s*/Page\b(?!s)').allMatches(text).length, sheets, reason: 'una página por hoja');
    expect([for (final k in [7, 15, 20, 28]) doc.isLoadedAt(k)], everyElement(isFalse), reason: 'exportar no deja hojas cargadas');
    // y una hoja sin cargar se dibuja con su contenido de disco
    final (src, i) = (await t.runAsync(() => sheetSource(store, doc, 7)))!;
    expect(src.texts.values.any((x) => x.text == 'hoja 7'), isTrue);
    expect(src.strokes.length, 1);
    expect(src.sheets[i].id, doc.sheets[7].id);
    expect(decodeSheet(File('${root.path}/notebooks/${doc.id}/sheets/${doc.sheets[7].id}.sheet').readAsBytesSync()).texts.length, 1);
  });
}
