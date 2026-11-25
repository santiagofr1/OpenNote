import 'package:apuntes/editor/link_dialog.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sheets = [(id: 'h1', label: 'Hoja 1'), (id: 'h2', label: 'Hoja 2 · Óptica'), (id: 'h3', label: 'Hoja 3')];
  final notebooks = [(id: 'n1', label: 'Física')];

  Future<Future<String?>> open(WidgetTester t, {String initial = ''}) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final r = showLinkDialog(ctx, initial: initial, sheets: sheets, notebooks: notebooks);
    await t.pumpAndSettle();
    return r;
  }

  bool okEnabled(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('linkOk'))).onPressed != null;

  testWidgets('web: una dirección inválida deshabilita Crear; una válida devuelve https', (t) async {
    final r = await open(t);
    expect(okEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('linkUrl')), 'hola');
    await t.pump();
    expect(okEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('linkUrl')), ' ejemplo.com ');
    await t.pump();
    expect(okEnabled(t), isTrue);
    await t.tap(find.byKey(const Key('linkOk')));
    await t.pumpAndSettle();
    expect(await r, 'https://ejemplo.com');
  });

  testWidgets('hoja: elegir una devuelve sheet:<id>', (t) async {
    final r = await open(t);
    await t.tap(find.byKey(const Key('linkKindSheet')));
    await t.pumpAndSettle();
    expect(okEnabled(t), isFalse);
    await t.tap(find.byKey(const Key('linkSheet-h3')));
    await t.pump();
    expect(okEnabled(t), isTrue);
    await t.tap(find.byKey(const Key('linkOk')));
    await t.pumpAndSettle();
    expect(await r, 'sheet:h3');
  });

  testWidgets('cuaderno: elegir uno devuelve nb:<id>', (t) async {
    final r = await open(t);
    await t.tap(find.byKey(const Key('linkKindNb')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('linkNb-n1')));
    await t.pump();
    await t.tap(find.byKey(const Key('linkOk')));
    await t.pumpAndSettle();
    expect(await r, 'nb:n1');
  });

  testWidgets('al editar arranca con el destino actual; Cancelar devuelve null', (t) async {
    final r = await open(t, initial: 'sheet:h2');
    expect(find.byIcon(Icons.check), findsOneWidget); // la hoja 2 ya viene elegida
    expect(okEnabled(t), isTrue);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(await r, isNull);
  });
}
