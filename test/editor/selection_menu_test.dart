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
}
