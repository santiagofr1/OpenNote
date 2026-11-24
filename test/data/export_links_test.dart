import 'dart:io';

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los links de OpenNote siguen andando en el PDF exportado.
void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_pdf_links');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  NotebookDoc sample() {
    final nb = Notebook.create('Con links');
    while (nb.sheets.length < 3) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    d.items['web'] = Item('web', 'link', 100, 100, 300, 60, text: 'https://ejemplo.com/uno');
    d.items['hoja'] = Item('hoja', 'link', 100, 300, 300, 60, text: 'sheet:${nb.sheets[2].id}');
    d.items['fuera'] = Item('fuera', 'link', 100, 500, 300, 60, text: 'sheet:no-esta');
    d.items['otro'] = Item('otro', 'link', 100, 700, 300, 60, text: 'nb:n1');
    return d;
  }

  String text(List<int> b) => String.fromCharCodes(b);

  testWidgets('el PDF tiene la anotación /URI y el link a la hoja; el de otro cuaderno no se exporta', (t) async {
    final doc = sample();
    final bytes = (await t.runAsync(() => buildNotebookPdf(store, doc)))!;
    final s = text(bytes);
    expect(RegExp(r'/Type\s*/Page\b(?!s)').allMatches(s).length, 3);
    expect(s, contains('/URI'));
    expect(s, contains('https://ejemplo.com/uno'));
    // una hoja de este cuaderno: un destino con nombre (anchor) por hoja y un link a la tercera
    expect(s, contains('sheet-${doc.sheets[2].id}'));
    expect(RegExp(r'/Subtype\s*/Link').allMatches(s).length, 2, reason: 'web y hoja; ni la que ya no está ni la de otro cuaderno');
    expect(s, isNot(contains('no-esta')));
  });

  testWidgets('sin links el PDF sale igual de bien', (t) async {
    final doc = NotebookDoc(Notebook.create('Sin links'))..texts['t'] = TextBlock('t', 90, 44, 800, 'Hola');
    final bytes = (await t.runAsync(() => buildNotebookPdf(store, doc)))!;
    final s = text(bytes);
    expect(s, isNot(contains('/URI')));
    expect(RegExp(r'/Subtype\s*/Link').hasMatch(s), isFalse);
  });

  testWidgets('exportando solo una hoja, el link a una hoja que no va no se exporta', (t) async {
    final doc = sample();
    final bytes = (await t.runAsync(() => buildNotebookPdf(store, doc, only: [0])))!;
    final s = text(bytes);
    expect(s, contains('https://ejemplo.com/uno'));
    expect(RegExp(r'/Subtype\s*/Link').allMatches(s).length, 1);
  });
}
