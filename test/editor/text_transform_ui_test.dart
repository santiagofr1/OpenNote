import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El texto con teclado como entidad (issue #12), con el editor de verdad: elegir, escalar, rotar, deshacer y enderezar.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_selhandles'));
  tearDown(() => root.deleteSync(recursive: true));


  Future<({PageEditorState ed, Offset Function(double, double) at})> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final tools = ToolState()..tool = Tool.select;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (ed: ed, at: (double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale));
  }

  Future<void> stylus(WidgetTester t, Offset a, Offset b) async {
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 8)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

  /// Arrastra la manija [name] hasta [to] (pantalla); [during] se mira con el dedo todavía apoyado.
  Future<void> dragHandle(WidgetTester t, String name, Offset to, {void Function()? during}) async {
    final from = t.getCenter(find.byKey(ValueKey('selHandle-$name')));
    final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump();
    }
    during?.call();
    await g.up();
    await t.pump();
  }

  NotebookDoc armado() {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.texts['t'] = TextBlock('t', 200, doc.snapTextY(400), 400, 'hola mundo');
    return doc;
  }

  testWidgets('un texto elegido muestra la manija de rotar; escalar y rotar son un paso de deshacer cada uno; Enderezar vuelve', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    final overflow = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) overflow?.call(d);
    };
    addTearDown(() => FlutterError.onError = overflow);
    await stylus(t, h.at(100, 300), h.at(800, 520));
    expect(h.ed.sel.texts, {'t'});
    expect(find.byKey(const ValueKey('selHandle-rotate')), findsOneWidget, reason: 'con solo textos también se puede rotar');
    expect(find.text('Enderezar'), findsNothing);

    final y0 = doc.texts['t']!.y;
    final tl = t.getCenter(find.byKey(const ValueKey('selHandle-tl'))), br = t.getCenter(find.byKey(const ValueKey('selHandle-br')));
    await dragHandle(t, 'br', tl + (br - tl) * 1.6);
    final tb = doc.texts['t']!;
    expect(tb.scale, closeTo(1.6, .1));
    expect(tb.angle, 0);

    final rot = t.getCenter(find.byKey(const ValueKey('selHandle-rotate')));
    final c = (t.getCenter(find.byKey(const ValueKey('selHandle-tl'))) + t.getCenter(find.byKey(const ValueKey('selHandle-br')))) / 2;
    await dragHandle(t, 'rotate', c + Offset((rot - c).distance, 0));
    expect(tb.angle, closeTo(pi / 2, .15), reason: 'giró ~90° (con imán)');
    expect(find.text('Enderezar'), findsOneWidget);

    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.texts['t']!.angle, 0);
    expect(doc.texts['t']!.scale, closeTo(1.6, .1), reason: 'deshacer el giro deja la escala');
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.texts['t']!.scale, 1);
    expect(doc.texts['t']!.y, closeTo(y0, 1e-6));
    await t.tap(find.byTooltip('Rehacer'));
    await t.tap(find.byTooltip('Rehacer'));
    await t.pump();
    expect(doc.texts['t']!.angle, closeTo(pi / 2, .15));

    await stylus(t, h.at(20, 200), h.at(980, 800)); // deshacer / rehacer sueltan la selección
    expect(h.ed.sel.texts, {'t'});
    await t.tap(find.text('Enderezar'));
    await t.pump();
    expect(doc.texts['t']!.scale, 1);
    expect(doc.texts['t']!.angle, 0);
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.texts['t']!.angle, closeTo(pi / 2, .15), reason: 'Enderezar se deshace');
  });
}
