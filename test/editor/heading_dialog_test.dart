// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:apuntes/editor/heading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({String title, int level})? result;
  var closed = false;

  Future<void> open(WidgetTester t, {String title = '', int level = 1, Future<String?>? recognizing, bool downloading = false}) async {
    result = null;
    closed = false;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showHeadingDialog(c,
                  initialTitle: title, initialLevel: level, recognizing: recognizing, downloading: downloading);
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    // con el spinner girando no hay "settle"
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  bool okEnabled(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('headingOk'))).onPressed != null;
  String fieldText(WidgetTester t) => t.widget<TextField>(find.byKey(const Key('headingName'))).controller!.text;

  testWidgets('nivel: sube y baja con límites 1 y 9', (t) async {
    await open(t, level: 2);
    String lvl() => t.widget<Text>(find.byKey(const Key('headingLevel'))).data!;
    expect(lvl(), '2');
    await t.tap(find.byKey(const Key('headingLevelDown')));
    await t.pump();
    expect(lvl(), '1');
    await t.tap(find.byKey(const Key('headingLevelDown')));
    await t.pump();
    expect(lvl(), '1');
    for (var i = 0; i < 12; i++) {
      await t.tap(find.byKey(const Key('headingLevelUp')), warnIfMissed: false);
      await t.pump();
    }
    expect(lvl(), '9');
  });

  testWidgets('Agregar está deshabilitado con el nombre vacío y devuelve nombre y nivel', (t) async {
    await open(t);
    expect(okEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('headingName')), '   ');
    await t.pump();
    expect(okEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('headingName')), '  Objetivos ');
    await t.pump();
    expect(okEnabled(t), isTrue);
    await t.tap(find.byKey(const Key('headingLevelUp')));
    await t.pump();
    await t.tap(find.byKey(const Key('headingOk')));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, (title: 'Objetivos', level: 2));
  });

  testWidgets('Cancelar devuelve null', (t) async {
    await open(t, title: 'algo');
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('el reconocimiento completa el campo si está vacío', (t) async {
    final c = Completer<String?>();
    await open(t, recognizing: c.future);
    expect(find.text('Leyendo la letra… (podés escribir el nombre mientras tanto)'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    c.complete('Introducción');
    await t.pumpAndSettle();
    expect(fieldText(t), 'Introducción');
    expect(find.text('Leyendo la letra… (podés escribir el nombre mientras tanto)'), findsNothing);
    expect(okEnabled(t), isTrue);
  });

  testWidgets('el reconocimiento NO pisa lo que escribió el usuario', (t) async {
    final c = Completer<String?>();
    await open(t, recognizing: c.future);
    await t.enterText(find.byKey(const Key('headingName')), 'Mi título');
    await t.pump();
    c.complete('Introducción');
    await t.pumpAndSettle();
    expect(fieldText(t), 'Mi título');
  });

  testWidgets('si no se pudo leer avisa; mientras baja el modelo lo dice', (t) async {
    final c = Completer<String?>();
    await open(t, recognizing: c.future, downloading: true);
    expect(find.text('Bajando el reconocimiento de letra, solo la primera vez (podés escribir el nombre mientras tanto)…'), findsOneWidget);
    c.complete(null);
    await t.pumpAndSettle();
    expect(fieldText(t), '');
    expect(find.text('No se pudo leer: escribí el nombre'), findsOneWidget);
  });

  testWidgets('mientras lee, el campo es editable y Agregar anda con lo escrito (la lectura tardía se ignora)', (t) async {
    final c = Completer<String?>();
    await open(t, recognizing: c.future);
    expect(t.widget<TextField>(find.byKey(const Key('headingName'))).enabled, isNot(false));
    expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar')).onPressed, isNotNull);
    await t.enterText(find.byKey(const Key('headingName')), 'Escrito');
    await t.pump();
    expect(fieldText(t), 'Escrito');
    expect(okEnabled(t), isTrue);
    await t.tap(find.byKey(const Key('headingOk')));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, (title: 'Escrito', level: 1));
    c.complete('Tarde'); // llega con el diálogo cerrado: no rompe nada
    await t.pump();
  });
}
