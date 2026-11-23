import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Item pdf: ida y vuelta con la página, y la copia la conserva', () {
    final it = Item('p1', 'pdf', 10, 20, 700, 990, file: 'abc.pdf', page: 7);
    final j = it.toJson();
    expect(j['pg'], 7);
    final back = Item.fromJson(j);
    expect([back.type, back.file, back.page], ['pdf', 'abc.pdf', 7]);
    expect(back.copy().page, 7);
    expect(Item('p2', 'pdf', 0, 0, 1, 1, file: 'a.pdf').toJson()['pg'], 0, reason: 'la página 0 también se guarda');
  });

  test('Item que no es pdf no guarda página', () {
    expect(Item('i', 'image', 0, 0, 1, 1, file: 'a.png').toJson().containsKey('pg'), isFalse);
    expect(Item.fromJson({'id': 'i', 'type': 'image', 'x': 0, 'y': 0, 'w': 1, 'h': 1}).page, 0);
  });

  group('mostVisibleSheetFor', () {
    test('gana la hoja con más área visible, de los dos lados del hueco', () {
      expect(mostVisibleSheetFor(700, 1500, 3), 0); // 714 de la 0 contra 20 de la 1
      expect(mostVisibleSheetFor(1100, 1900, 3), 1); // 314 contra 420
      expect(mostVisibleSheetFor(0, 800, 3), 0);
      expect(mostVisibleSheetFor(2 * kSheetStep, 2 * kSheetStep + 800, 3), 2);
    });

    test('empate: la de arriba', () {
      expect(mostVisibleSheetFor(kSheetH - 400, kSheetStep + 400, 3), 0);
    });

    test('el borde de una hoja al 40 % de la vista: gana la de abajo', () {
      // vista de 1000: la hoja 0 ocupa el 40 % de arriba, el hueco 6,6 % y la hoja 1 el resto
      expect(mostVisibleSheetFor(kSheetH - 400, kSheetH + 600, 3), 1);
    });

    test('vista en el hueco o fuera del documento', () {
      expect(mostVisibleSheetFor(kSheetH + 10, kSheetH + 50, 3), anyOf(0, 1));
      expect(mostVisibleSheetFor(-500, -100, 3), 0);
      expect(mostVisibleSheetFor(99999, 100500, 3), 2);
      expect(mostVisibleSheetFor(0, 800, 1), 0);
    });
  });
}
