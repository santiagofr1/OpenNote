import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada párrafo ocupa al menos un renglón, también títulos y listas', () {
    final t = TextBlock('t', 0, 0, 600, 'a\nb\nc');
    expect(textRect(t, 40).height, 120);
    t.body = t.body.setParaStyle(0, 0, ParaStyle.title).setList(2, 2, ListKind.bullet).indent(4, 4, 2);
    expect(textRect(t, 40).height, 120, reason: 'el título no rompe la grilla del renglón');
  });

  test('la sangría y el marcador corren el texto', () {
    final t = TextBlock('t', 0, 0, 600, 'hola');
    final plain = textRect(t, 40).width;
    t.body = t.body.setList(0, 0, ListKind.bullet).indent(0, 0, 1);
    expect(textRect(t, 40).width, greaterThan(plain + 40));
  });

  test('alineado al centro ocupa todo el ancho', () {
    final t = TextBlock('t', 0, 0, 600, 'hola');
    t.body = t.body.setAlign(0, 0, ParaAlign.center);
    expect(textRect(t, 40).width, 600);
  });

  test('el mismo bloque con y sin formato mide igual de alto', () {
    final a = TextBlock('t', 0, 0, 600, 'hola mundo');
    final b = TextBlock('t', 0, 0, 600, 'hola mundo');
    b.body = b.body.toggle(0, 4, Fmt.bold).toggle(0, 10, Fmt.italic);
    expect(textRect(b, 40).height, textRect(a, 40).height);
  });
}
