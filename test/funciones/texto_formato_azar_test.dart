import 'dart:convert';
import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Texto con formato (negrita, listas, títulos, Enter, Retroceso): secuencias de acciones al azar sobre un cuerpo de
/// texto, comparadas contra un modelo trivial (un String). Invariantes: el formato NUNCA cambia las letras; escribir
/// se comporta como `String.replaceRange`; el JSON da ida y vuelta; las posiciones siempre quedan acotadas.
void main() {
  const alfabeto = ['a', 'b', ' ', 'ñ', '日', '\n', '😀', 'Z', '\n\n', ''];

  String texto(Random r) => List.generate(r.nextInt(6), (_) => alfabeto[r.nextInt(alfabeto.length)]).join();

  RichBody inicial(Random r) {
    var b = RichBody.plain(texto(r) + texto(r));
    for (var i = 0; i < r.nextInt(6); i++) {
      b = _accion(r, b);
    }
    return b;
  }

  /// Posiciones dentro del texto y un poco fuera (la API las acota).
  int pos(Random r, RichBody b) => r.nextInt(b.length + 3) - 1;

  for (final seed in kSeeds) {
    test('formato al azar (semilla $seed): las letras no cambian y la selección queda toda con o toda sin formato', () {
      final r = Random(seed);
      for (var it = 0; it < 300; it++) {
        var b = inicial(r);
        final letras = b.plainText;
        for (var k = 0; k < 12; k++) {
          final s = pos(r, b), e = pos(r, b);
          final f = Fmt.values[r.nextInt(4)];
          final lo = min(s, e).clamp(0, b.length), hi = max(s, e).clamp(0, b.length);
          final nuevo = b.toggle(s, e, f);
          expect(nuevo.plainText, letras, reason: 'it $it: toggle no puede tocar las letras');
          // propiedad fuerte: tras alternar, el rango está TODO con el formato o NADA lo tiene (si hay letras en el rango)
          final conLetras = letras.substring(lo, hi).replaceAll('\n', '').isNotEmpty;
          if (lo < hi && conLetras) {
            final todo = nuevo.allHave(lo, hi, f);
            final nada = !_algunoTiene(nuevo, lo, hi, f);
            expect(todo || nada, isTrue, reason: 'it $it: [$lo,$hi) con $f quedó mezclado');
          }
          b = _accion(r, nuevo);
          expect(b.plainText, letras);
        }
      }
    });

    test('escribir se comporta como String.replaceRange (semilla $seed), con cualquier formato de por medio', () {
      final r = Random(seed);
      for (var it = 0; it < 400; it++) {
        var b = inicial(r);
        var modelo = b.plainText;
        for (var k = 0; k < 15; k++) {
          final s = pos(r, b), e = pos(r, b);
          final a = min(s, e).clamp(0, b.length), z = max(s, e).clamp(0, b.length);
          final t = texto(r);
          b = b.replaceRange(s, e, t);
          modelo = modelo.replaceRange(a, z, t);
          expect(b.plainText, modelo, reason: 'it $it paso $k');
          expect(b.length, modelo.length);
          expect(b.paras, isNotEmpty);
          b = _accion(r, b);
          expect(b.plainText, modelo);
        }
      }
    });

    test('Enter y Retroceso (semilla $seed): el caret queda dentro y Enter agrega exactamente un salto', () {
      final r = Random(seed);
      for (var it = 0; it < 400; it++) {
        var b = inicial(r);
        for (var k = 0; k < 15; k++) {
          final g = r.nextInt(b.length + 1);
          if (r.nextBool()) {
            final antes = b.plainText;
            final x = b.enter(g);
            expect(x.caret, inInclusiveRange(0, x.body.length), reason: 'it $it: caret fuera del texto');
            final p = b.paras[b.locate(g).para];
            if (p.isEmpty && p.list != ListKind.none) {
              expect(x.body.plainText, antes, reason: 'Enter en un renglón de lista vacío solo saca la lista');
            } else {
              expect(x.body.plainText, antes.replaceRange(g, g, '\n'));
              expect(x.caret, g + 1);
            }
            b = x.body;
          } else {
            final para = r.nextInt(b.paras.length);
            final antes = b.plainText;
            final x = b.backspaceAtStart(para);
            expect(x.caret, inInclusiveRange(0, x.body.length));
            expect(antes.length - x.body.plainText.length, inInclusiveRange(0, 1), reason: 'Retroceso borra a lo sumo el salto');
            b = x.body;
          }
          b = _accion(r, b);
        }
      }
    });

    test('JSON de ida y vuelta exacto, también pasando por jsonEncode (semilla $seed)', () {
      final r = Random(seed);
      for (var it = 0; it < 500; it++) {
        var b = inicial(r);
        for (var k = 0; k < 4; k++) {
          b = b.replaceRange(pos(r, b), pos(r, b), texto(r));
          b = _accion(r, b);
        }
        final j = jsonDecode(jsonEncode(b.toJson())) as List;
        final c = RichBody.fromJson(j);
        expect(c, b, reason: 'it $it');
        expect(jsonEncode(c.toJson()), jsonEncode(b.toJson()), reason: 'encode estable');
      }
    });

    test('posiciones y numeración (semilla $seed): globalOf y locate son inversas; los números siguen la regla', () {
      final r = Random(seed);
      for (var it = 0; it < 300; it++) {
        final b = inicial(r);
        for (var p = 0; p < b.paras.length; p++) {
          for (var off = 0; off <= b.paras[p].length; off++) {
            final l = b.locate(b.globalOf(p, off));
            expect((l.para, l.offset), (p, off));
          }
        }
        final n = b.numbering();
        expect(n.length, b.paras.length);
        for (var i = 0; i < n.length; i++) {
          if (b.paras[i].list != ListKind.numbered) {
            expect(n[i], 0);
          } else {
            expect(n[i], greaterThanOrEqualTo(1));
            if (i > 0 && b.paras[i - 1].list == ListKind.numbered && b.paras[i - 1].indent == b.paras[i].indent) {
              expect(n[i], n[i - 1] + 1);
            }
          }
        }
        expect(b.locate(-5).offset, 0);
        final fin = b.locate(b.length + 50);
        expect((fin.para, fin.offset), (b.paras.length - 1, b.paras.last.length));
      }
    });
  }

  test('unicode: darle formato a la mitad de un emoji no rompe el JSON ni la longitud', () {
    var b = RichBody.plain('a😀b');
    b = b.toggle(2, 3, Fmt.bold); // la mitad de un par sustituto
    expect(() => jsonDecode(jsonEncode(b.toJson())), returnsNormally);
    expect(b.plainText, 'a😀b');
    expect(b.length, 4);
  });

  test('cuerpo vacío: todas las acciones sobre el cuerpo vacío aguantan', () {
    final b = RichBody([]);
    expect(b.paras.length, 1);
    for (final f in Fmt.values) {
      expect(b.toggle(0, 10, f).plainText, '');
      expect(b.toggle(-5, 0, f).plainText, '');
    }
    expect(b.enter(0).body.plainText, '\n');
    expect(b.backspaceAtStart(0).body.plainText, '');
    expect(b.setList(0, 0, ListKind.numbered).paras.single.list, ListKind.numbered);
    expect(b.setList(0, 0, ListKind.numbered).setList(0, 0, ListKind.numbered).paras.single.list, ListKind.none,
        reason: 'alternar saca la lista');
    expect(b.replaceRange(5, -3, 'x').plainText, 'x');
  });

  test('la sangría nunca pasa de los límites aunque se la empuje 100 veces', () {
    var b = RichBody.plain('a\nb');
    for (var i = 0; i < 100; i++) {
      b = b.indent(0, b.length, 1);
    }
    expect(b.paras.every((p) => p.indent == Para.kMaxIndent), isTrue);
    for (var i = 0; i < 100; i++) {
      b = b.indent(0, b.length, -1);
    }
    expect(b.paras.every((p) => p.indent == 0), isTrue);
  });
}

bool _algunoTiene(RichBody b, int s, int e, Fmt f) {
  for (var g = s; g < e; g++) {
    final l = b.locate(g);
    final p = b.paras[l.para];
    if (l.offset < p.length && p.styleAt(l.offset + 1).has(f)) return true;
  }
  return false;
}

/// Acción de formato al azar: cambia atributos, nunca las letras.
RichBody _accion(Random r, RichBody b) {
  final s = r.nextInt(b.length + 2), e = r.nextInt(b.length + 2);
  switch (r.nextInt(9)) {
    case 0:
      return b.toggle(s, e, Fmt.values[r.nextInt(4)]);
    case 1:
      return b.setColor(s, e, r.nextBool() ? null : 0xFF000000 | r.nextInt(1 << 24));
    case 2:
      return b.setHighlight(s, e, r.nextBool() ? null : 0xFF000000 | r.nextInt(1 << 24));
    case 3:
      return b.setSize(s, e, r.nextBool() ? null : 6.0 + r.nextInt(60));
    case 4:
      return b.setParaStyle(s, e, ParaStyle.values[r.nextInt(3)]);
    case 5:
      return b.setAlign(s, e, ParaAlign.values[r.nextInt(4)]);
    case 6:
      return b.setList(s, e, ListKind.values[r.nextInt(4)]);
    case 7:
      return b.indent(s, e, r.nextInt(5) - 2);
    default:
      return b.setChecked(r.nextInt(b.paras.length), r.nextBool());
  }
}
