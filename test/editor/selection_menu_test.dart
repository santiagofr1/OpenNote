import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/selection_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el menú Orden ofrece las cuatro acciones y avisa cuál se eligió', (t) async {
    final got = <ZMove>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SelectionMenu(
            onCopy: () {},
            onCut: () {},
            onDuplicate: () {},
            onDelete: () {},
            onClose: () {},
            onOrder: got.add,
          ),
        ),
      ),
    ));
    final wanted = {
      'Traer al frente': ZMove.front,
      'Subir uno': ZMove.up,
      'Bajar uno': ZMove.down,
      'Enviar al fondo': ZMove.back,
    };
    for (final e in wanted.entries) {
      await t.tap(find.text('Orden'));
      await t.pumpAndSettle();
      for (final label in wanted.keys) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text(e.key));
      await t.pumpAndSettle();
    }
    expect(got, wanted.values.toList());
  });

  testWidgets('los filtros se ven con texto y avisan; sin filtros no aparecen', (t) async {
    var hl = 0, noHl = 0;
    Widget menu({bool filters = true}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: FittedBox(child: SelectionMenu(
                onCopy: () {},
                onCut: () {},
                onDuplicate: () {},
                onDelete: () {},
                onClose: () {},
                onOrder: (_) {},
                onOnlyHl: filters ? () => hl++ : null,
                onOnlyInk: filters ? () => noHl++ : null,
              )),
            ),
          ),
        );
    await t.pumpWidget(menu());
    expect(find.text('Solo resaltador'), findsOneWidget);
    expect(find.text('Sin resaltador'), findsOneWidget);
    await t.tap(find.text('Solo resaltador'));
    await t.tap(find.text('Sin resaltador'));
    expect([hl, noHl], [1, 1]);
    await t.pumpWidget(menu(filters: false));
    expect(find.text('Solo resaltador'), findsNothing);
    expect(find.text('Sin resaltador'), findsNothing);
    // ancho chico: no desborda
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(menu());
    expect(t.takeException(), isNull);
  });
}
