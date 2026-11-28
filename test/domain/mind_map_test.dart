import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mapa conceptual del índice (issue #17): árbol, acomodo y archivo FreeMind.
void main() {
  var n = 0;
  OutlineEntry e(Section s, int level, String title) => OutlineEntry(
      sectionId: s.id, headingId: 'h${n++}', sheetId: 'x', sheet: 0, y: 0, level: level, number: '1', title: title);

  // cada letra mide 8 de ancho; el alto sube con la profundidad
  Size measure(String t, int d) => Size(20.0 + 8 * t.length, d == 0 ? 40 : 22.0 + d);

  Iterable<String> dump(MindNode x) sync* {
    yield '${' ' * x.depth}${x.text}';
    for (final c in x.children) {
      yield* dump(c);
    }
  }

  test('una sola sección: los títulos cuelgan de la raíz y bajan según el nivel', () {
    final nb = Notebook.create('Física');
    final s = nb.sections.single;
    final root = buildMindTree(nb, [e(s, 1, 'A'), e(s, 2, 'A1'), e(s, 3, 'A1a'), e(s, 2, 'A2'), e(s, 1, 'B')], 'Sin título');
    expect(dump(root).toList(), ['Física', ' A', '  A1', '   A1a', '  A2', ' B']);
    expect(root.children.map((c) => c.kind).toSet(), {MindKind.heading});
  });

  test('varias secciones: cada una con títulos es una rama; las vacías no aparecen', () {
    final nb = Notebook.create('Cuaderno');
    final a = nb.sections.single, b = nb.addSection('Segunda'), c = nb.addSection('Vacía'), d = nb.addSection('Tercera');
    final root = buildMindTree(nb, [e(a, 1, 'x'), e(b, 1, 'y'), e(b, 2, 'z'), e(d, 1, 'w')], 'Sin título');
    expect([for (final k in root.children) k.text], ['General', 'Segunda', 'Tercera']);
    expect(c.name, 'Vacía');
    expect(root.children.every((k) => k.kind == MindKind.section), isTrue);
    expect(dump(root.children[1]).toList(), [' Segunda', '  y', '   z']);
    expect([for (final k in root.children) k.branch], [0, 1, 2]);
    expect(root.children[1].children.single.children.single.branch, 1);
  });

  test('un nivel que salta se cuelga del anterior más cercano; y al empezar una sección también', () {
    final nb = Notebook.create('C');
    final a = nb.sections.single, b = nb.addSection('S2');
    final root = buildMindTree(nb, [e(a, 1, 'a'), e(a, 4, 'salto'), e(a, 2, 'b'), e(b, 3, 'arranca alto')], 'Sin título');
    expect(dump(root.children[0]).toList(), [' General', '  a', '   salto', '   b']);
    expect(dump(root.children[1]).toList(), [' S2', '  arranca alto']);
  });

  test('títulos vacíos usan el texto de reemplazo', () {
    final nb = Notebook.create('  ');
    final s = nb.sections.single;
    final root = buildMindTree(nb, [e(s, 1, ''), e(s, 1, '   ')], 'Sin título');
    expect(root.text, 'Sin título');
    expect(root.children.map((c) => c.text), ['Sin título', 'Sin título']);
  });

  MindNode wide(int sections, int perSection, {int depth3 = 0}) {
    final nb = Notebook.create('Grande');
    final secs = [nb.sections.single, for (var i = 1; i < sections; i++) nb.addSection('Sec $i')];
    final list = <OutlineEntry>[];
    for (final s in secs) {
      for (var i = 0; i < perSection; i++) {
        list.add(e(s, 1, 'Título ${s.name} $i'));
        for (var j = 0; j < depth3; j++) {
          list.add(e(s, 2, 'Sub $j de $i con un texto bastante largo'));
          list.add(e(s, 3, 'Sub-sub $j'));
        }
      }
    }
    return buildMindTree(nb, list, 'Sin título');
  }

  test('acomodo: nada se superpone, ni dentro de un lado ni entre lados', () {
    for (final root in [wide(1, 12, depth3: 2), wide(3, 5, depth3: 3), wide(5, 1), wide(2, 0)]) {
      final m = layoutMindMap(root, measure);
      for (var i = 0; i < m.nodes.length; i++) {
        for (var j = i + 1; j < m.nodes.length; j++) {
          expect(m.nodes[i].rect.overlaps(m.nodes[j].rect), isFalse, reason: '${m.nodes[i].text} / ${m.nodes[j].text}');
        }
        expect(m.bounds.expandToInclude(m.nodes[i].rect), m.bounds);
      }
      expect(m.edges.length, m.nodes.length - 1);
    }
  });

  test('acomodo: el padre queda centrado respecto de sus hijos y del mismo lado que ellos', () {
    final m = layoutMindMap(wide(2, 4, depth3: 2), measure);
    for (final p in m.nodes) {
      if (p.children.isEmpty) continue;
      final mid = (p.children.first.rect.top + p.children.last.rect.bottom) / 2;
      expect(p.rect.center.dy, closeTo(mid, 1e-9), reason: p.text);
      for (final c in p.children) {
        if (p.kind == MindKind.root) continue;
        expect(c.side, p.side);
        expect(p.side > 0 ? c.rect.left > p.rect.right : c.rect.right < p.rect.left, isTrue, reason: c.text);
      }
    }
    expect(m.root.rect.center, Offset.zero);
  });

  test('acomodo: las ramas se reparten entre derecha e izquierda por cantidad de hojas', () {
    final nb = Notebook.create('Rep');
    final s = nb.sections.single;
    // hojas por rama: 4, 1, 1, 1, 1 -> la primera sola (4) frente a las otras cuatro (4)
    final root = buildMindTree(nb, [
      e(s, 1, 'a'), e(s, 2, 'a1'), e(s, 2, 'a2'), e(s, 2, 'a3'), e(s, 2, 'a4'),
      e(s, 1, 'b'), e(s, 1, 'c'), e(s, 1, 'd'), e(s, 1, 'e'),
    ], 'x');
    final sides = splitSides(root);
    expect(sides.right.map((x) => x.text), ['a']);
    expect(sides.left.map((x) => x.text), ['b', 'c', 'd', 'e']);
    int leaves(List<MindNode> l) => l.fold(0, (a, x) => a + x.leaves);
    expect(leaves(sides.right), leaves(sides.left));
    final m = layoutMindMap(root, measure);
    expect(m.nodes.where((x) => x.side > 0).every((x) => x.rect.left > m.root.rect.right), isTrue);
    expect(m.nodes.where((x) => x.side < 0).every((x) => x.rect.right < m.root.rect.left), isTrue);
    // con 2 ramas o más, los dos lados tienen algo aunque una pese mucho más
    final big = buildMindTree(nb, [e(s, 1, 'p'), for (var i = 0; i < 9; i++) e(s, 2, 'q$i'), e(s, 1, 'z')], 'x');
    final sb = splitSides(big);
    expect([sb.right.length, sb.left.length], [1, 1]);
  });

  test('un mapa sin títulos es solo la raíz', () {
    final m = layoutMindMap(buildMindTree(Notebook.create('Vacío'), const [], 'x'), measure);
    expect(m.nodes.length, 1);
    expect(m.edges, isEmpty);
    expect(m.bounds, m.root.rect);
  });

  group('FreeMind', () {
    MindNode tree(List<(int, String)> t, {String name = 'C'}) {
      final nb = Notebook.create(name);
      final s = nb.sections.single;
      return buildMindTree(nb, [for (final x in t) e(s, x.$1, x.$2)], 'Sin título');
    }

    test('estructura: nodos anidados, POSITION en el primer nivel y XML bien formado', () {
      final xml = mindMapToFreeMind(tree([(1, 'A'), (2, 'A1'), (1, 'B')]));
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>\n<map version="1.0.1">'));
      expect(xml.trimRight(), endsWith('</map>'));
      expect(xml, contains('<node TEXT="C">'));
      expect(xml, contains('<node TEXT="A" POSITION="right">'));
      expect(xml, contains('<node TEXT="A1"/>'));
      expect(xml, contains('<node TEXT="B" POSITION="left"/>'));
      // etiquetas balanceadas
      var depth = 0;
      for (final m in RegExp(r'<(/?)node\b[^>]*?(/?)>').allMatches(xml)) {
        if (m[2] == '/') continue;
        depth += m[1] == '/' ? -1 : 1;
        expect(depth, greaterThanOrEqualTo(0));
      }
      expect(depth, 0);
    });

    test('escapes: & < > comillas, saltos de línea y caracteres inválidos', () {
      final xml = mindMapToFreeMind(tree([(1, 'a & b <c> "d"\nlínea\r2\tx\u0001y')], name: 'R&D'));
      expect(xml, contains('TEXT="R&amp;D"'));
      expect(xml, contains('TEXT="a &amp; b &lt;c&gt; &quot;d&quot;&#10;línea&#13;2&#9;xy"'));
      // ningún valor de atributo trae un carácter sin escapar
      for (final m in RegExp(r'TEXT="([^"]*)"').allMatches(xml)) {
        expect(m[1], isNot(matches(RegExp(r'[<>\n\r]'))));
        expect(m[1]!.replaceAll(RegExp(r'&(amp|lt|gt|quot|#10|#13|#9);'), ''), isNot(contains('&')));
      }
    });
  });
}
