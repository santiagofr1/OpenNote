import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/screens/library/library_drag.dart';
import 'package:apuntes/widgets/auto_scroller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Inicio ─ A ─ B ─ C ; Inicio ─ D ; cuaderno n en B
  final a = Folder('a', 'A'), b = Folder('b', 'B', parent: 'a'), c = Folder('c', 'C', parent: 'b'), d = Folder('d', 'D');
  final nb = Notebook('n', 'N', folder: 'b');
  final idx = NotesIndex(notebooks: [nb], folders: [a, b, c, d]);

  test('un cuaderno se puede soltar en cualquier carpeta menos donde ya está', () {
    final x = LibraryDrag.notebook(nb);
    expect(x.canDropOn(idx, 'b'), isFalse);
    expect(x.canDropOn(idx, 'c'), isTrue);
    expect(x.canDropOn(idx, 'd'), isTrue);
    expect(x.canDropOn(idx, null), isTrue, reason: 'Inicio');
  });

  test('una carpeta no se suelta adentro de sí misma ni de una descendiente', () {
    final x = LibraryDrag.folder(a);
    expect(x.canDropOn(idx, 'a'), isFalse);
    expect(x.canDropOn(idx, 'b'), isFalse);
    expect(x.canDropOn(idx, 'c'), isFalse);
    expect(x.canDropOn(idx, 'd'), isTrue);
    expect(x.canDropOn(idx, null), isFalse, reason: 'ya está en el inicio');
    final y = LibraryDrag.folder(c);
    expect(y.canDropOn(idx, null), isTrue);
    expect(y.canDropOn(idx, 'a'), isTrue);
    expect(y.canDropOn(idx, 'b'), isFalse, reason: 'ya está en B');
  });

  test('velocidad del scroll automático: cero en el medio, sube arriba, baja abajo', () {
    expect(AutoScroller.speedFor(500, 1000), 0);
    expect(AutoScroller.speedFor(0, 1000), -AutoScroller.maxSpeed);
    expect(AutoScroller.speedFor(-30, 1000), -AutoScroller.maxSpeed, reason: 'fuera de la lista también');
    expect(AutoScroller.speedFor(1000, 1000), AutoScroller.maxSpeed);
    expect(AutoScroller.speedFor(AutoScroller.edge / 2, 1000), closeTo(-AutoScroller.maxSpeed / 2, 1e-9));
    expect(AutoScroller.speedFor(1000 - AutoScroller.edge / 2, 1000).abs(), lessThanOrEqualTo(AutoScroller.maxSpeed));
    expect(min(AutoScroller.edge, 1), 1);
  });
}
