import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

RichBody b(String s) => RichBody.plain(s);

void main() {
  group('RichBody', () {
    test('texto plano: un párrafo por línea y vuelve igual', () {
      final r = b('uno\ndos\n\ntres');
      expect(r.paras.length, 4);
      expect(r.plainText, 'uno\ndos\n\ntres');
      expect(r.length, 'uno\ndos\n\ntres'.length);
      expect(r.isPlain, isTrue);
    });

    test('negrita sobre un rango que cruza párrafos, y se apaga al repetir', () {
      final r = b('hola\nmundo'); // h0 o1 l2 a3 \n4 m5 u6
      final x = r.toggle(2, 7, Fmt.bold);
      expect(x.paras[0].runs.map((e) => (e.text, e.style.bold)), [('ho', false), ('la', true)]);
      expect(x.paras[1].runs.map((e) => (e.text, e.style.bold)), [('mu', true), ('ndo', false)]);
      expect(x.plainText, 'hola\nmundo');
      expect(x.allHave(2, 7, Fmt.bold), isTrue);
      expect(x.toggle(2, 7, Fmt.bold), r);
    });

    test('si solo parte del rango es negrita, el toggle prende todo', () {
      final r = b('abcd').toggle(0, 2, Fmt.bold);
      expect(r.toggle(0, 4, Fmt.bold).allHave(0, 4, Fmt.bold), isTrue);
    });

    test('color y resaltado', () {
      final r = b('abc').setColor(1, 2, 0xFFFF0000).setHighlight(0, 3, 0xFFF7D22C);
      expect(r.paras[0].runs[1].style.color, 0xFFFF0000);
      expect(r.paras[0].runs.every((e) => e.style.highlight == 0xFFF7D22C), isTrue);
      expect(r.setColor(1, 2, null).paras[0].runs.length, 1);
    });

    test('insertar hereda el formato del carácter anterior', () {
      final r = b('ab').toggle(0, 2, Fmt.bold).replaceRange(2, 2, 'c');
      expect(r.paras[0].runs.length, 1);
      expect(r.paras[0].runs.single.style.bold, isTrue);
      final s = r.replaceRange(3, 3, 'd', style: RunStyle.plain);
      expect(s.paras[0].runs.map((e) => e.style.bold), [true, false]);
    });

    test('Enter parte el párrafo, hereda atributos y backspace los une', () {
      final r = b('abcd').setAlign(0, 0, ParaAlign.center);
      final e = r.enter(2);
      expect(e.body.plainText, 'ab\ncd');
      expect(e.body.paras[1].align, ParaAlign.center);
      expect(e.caret, 3);
      final m = e.body.backspaceAtStart(1);
      expect(m.body.plainText, 'abcd');
      expect(m.caret, 2);
    });

    test('Enter al final de un título crea un párrafo normal', () {
      final r = b('T').setParaStyle(0, 0, ParaStyle.title).enter(1).body;
      expect(r.paras[1].style, ParaStyle.normal);
      expect(r.paras[0].style, ParaStyle.title);
    });

    test('Enter en un renglón de lista vacío termina la lista', () {
      var r = b('a').setList(0, 0, ListKind.bullet).enter(1).body;
      expect(r.paras.length, 2);
      expect(r.paras[1].list, ListKind.bullet);
      r = r.enter(2).body;
      expect(r.paras.length, 2, reason: 'no parte');
      expect(r.paras[1].list, ListKind.none);
    });

    test('retroceso al principio de una lista saca la lista; después une', () {
      var r = b('a\nb').setList(2, 2, ListKind.numbered).indent(2, 2, 1);
      var x = r.backspaceAtStart(1);
      expect(x.body.paras[1].list, ListKind.none);
      expect(x.body.paras[1].indent, 0);
      expect(x.body.paras.length, 2);
      x = x.body.backspaceAtStart(1);
      expect(x.body.plainText, 'ab');
    });

    test('atributos de párrafo en la selección y sangría acotada', () {
      final r = b('a\nb\nc').setList(0, 3, ListKind.bullet);
      expect(r.paras.map((p) => p.list), [ListKind.bullet, ListKind.bullet, ListKind.none],
          reason: 'un rango que termina al principio de un párrafo no lo toca');
      expect(r.setList(0, 3, ListKind.bullet).paras[0].list, ListKind.none, reason: 'repetir la saca');
      expect(r.indent(0, 0, 9).paras[0].indent, 4);
      expect(r.indent(0, 0, -1).paras[0].indent, 0);
    });

    test('numeración: sigue, reinicia por nivel y la corta un párrafo común', () {
      var r = b('a\nb\nc\nd\ne\nf').setList(0, 11, ListKind.numbered);
      r = r.indent(4, 5, 1); // c (g4) en nivel 1 ... g4..5 = párrafo c
      expect(r.numbering(), [1, 2, 1, 3, 4, 5]);
      final cut = b('a\nb\nc\nd').setList(0, 1, ListKind.numbered).setList(4, 5, ListKind.numbered);
      expect(cut.numbering(), [1, 0, 1, 0].sublist(0, 4).asMap().entries.map((e) => e.value).toList());
    });

    test('pegar con saltos de línea', () {
      final r = b('ab').replaceRange(1, 1, 'X\nY\nZ');
      expect(r.plainText, 'aX\nY\nZb');
      expect(r.paras.length, 3);
    });

    test('borrar un rango que cruza párrafos los une', () {
      final r = b('hola\nmundo').replaceRange(2, 7, '');
      expect(r.plainText, 'hondo');
    });

    test('tareas: checked se guarda y se limpia al partir', () {
      var r = b('a').setList(0, 0, ListKind.checklist).setChecked(0, true);
      expect(r.paras[0].checked, isTrue);
      r = r.enter(1).body;
      expect(r.paras[1].checked, isFalse);
    });
  });

  group('JSON', () {
    test('ida y vuelta con todos los formatos', () {
      var r = b('hola\nmundo')
          .toggle(0, 3, Fmt.bold)
          .toggle(1, 2, Fmt.italic)
          .toggle(0, 4, Fmt.underline)
          .toggle(6, 8, Fmt.strike)
          .setColor(0, 2, 0xFF112233)
          .setHighlight(6, 9, 0xFFF7D22C)
          .setParaStyle(5, 5, ParaStyle.subtitle)
          .setList(5, 5, ListKind.checklist)
          .setChecked(1, true)
          .indent(5, 5, 2)
          .setAlign(0, 0, ParaAlign.justify);
      final back = RichBody.fromJson(r.toJson());
      expect(back, r);
      expect(back.paras[1].indent, 2);
    });

    test('TextBlock viejo con solo `text` se carga como párrafos normales', () {
      final t = TextBlock.fromJson({'id': 't', 'x': 1, 'y': 2, 'w': 300, 'text': 'uno\ndos'});
      expect(t.body.paras.length, 2);
      expect(t.text, 'uno\ndos');
      expect(t.body.isPlain, isTrue);
    });

    test('sin formato se guarda como antes; con formato agrega `rich`', () {
      final t = TextBlock('t', 0, 0, 100, 'hola');
      expect(t.toJson().containsKey('rich'), isFalse);
      t.body = t.body.toggle(0, 2, Fmt.bold);
      final j = t.toJson();
      expect(j['text'], 'hola');
      final back = TextBlock.fromJson(j);
      expect(back.body, t.body);
    });

    test('JSON tolera enums desconocidos', () {
      final p = Para.fromJson({'style': 'raro', 'list': 'x', 'runs': [{'t': 'a'}]});
      expect(p.style, ParaStyle.normal);
      expect(p.list, ListKind.none);
    });
  });

  group('tamaño de letra', () {
    test('setSize sobre una selección parcial parte los tramos y conserva lo demás', () {
      final r = b('hola mundo').toggle(0, 4, Fmt.bold).setSize(2, 7, 24);
      expect([for (final x in r.paras[0].runs) x.text], ['ho', 'la', ' mu', 'ndo']);
      expect([for (final x in r.paras[0].runs) x.style.size], [null, 24, 24, null]);
      expect(r.paras[0].runs[1].style.bold, isTrue, reason: 'el tamaño conserva la negrita');
      expect(r.paras[0].runs[2].style.bold, isFalse);
      expect(r.setColor(0, 10, 0xFF112233).paras[0].runs[1].style.size, 24, reason: 'los demás with* conservan size');
      expect(r.setSize(2, 7, null), b('hola mundo').toggle(0, 4, Fmt.bold), reason: 'null vuelve a automático');
    });

    test('setSize entre párrafos y commonSize', () {
      final r = b('uno\ndos').setSize(1, 6, 18);
      expect(r.paras[0].runs.last.style.size, 18);
      expect(r.paras[1].runs.first.style.size, 18);
      expect(r.commonSize(1, 6), 18);
      expect(r.commonSize(0, 6), isNull, reason: 'mezcla de automático y 18');
      expect(r.commonSize(0, 1), isNull, reason: 'automático');
    });

    test('JSON con y sin size; los viejos cargan null', () {
      final r = b('hola').setSize(0, 2, 24).setSize(2, 4, 10.5);
      final j = r.toJson();
      expect(j[0]['runs'][0]['size'], 24);
      expect(RichBody.fromJson(j), r);
      expect(RichBody.fromJson(j).paras[0].runs[1].style.size, 10.5);
      expect(b('hola').toJson()[0]['runs'][0].containsKey('size'), isFalse);
      expect(Run.fromJson({'t': 'x', 'b': 1}).style.size, isNull);
      expect(r.isPlain, isFalse);
    });

    test('puntos y unidades: 12 pt son 4,23 mm reales', () {
      expect(unitsToMm(ptToUnits(12)), closeTo(4.233, .001));
      expect(ptToUnits(12) * 210 / 1000, closeTo(4.233, .001));
      expect(autoPt(textLine('lined', 8)), closeTo(12, .5));
    });
  });
}
