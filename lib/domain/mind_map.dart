import 'dart:math' as math;
import 'dart:ui';

import 'notebook.dart';
import 'outline.dart';

/// Qué es un nodo del mapa: la raíz (el cuaderno), una sección o un título del índice.
enum MindKind { root, section, heading }

/// Un nodo del mapa mental. La posición ([rect]) y el lado ([side]) los pone [layoutMindMap].
class MindNode {
  final String text;
  final MindKind kind;
  final int depth; // 0 la raíz, 1 sus hijos, etc.
  final List<MindNode> children = [];
  int branch = -1; // número de la rama de primer nivel de la que cuelga (-1 la raíz): da el color
  int side = 0; // -1 izquierda, 1 derecha, 0 la raíz
  Rect rect = Rect.zero;
  MindNode(this.text, this.kind, this.depth);

  int get leaves => children.isEmpty ? 1 : children.fold(0, (s, c) => s + c.leaves);
}

class MindEdge {
  final MindNode from, to;
  const MindEdge(this.from, this.to);
}

/// El mapa ya acomodado: nodos (en orden de recorrido), aristas y el rectángulo que los contiene a todos.
class MindMap {
  final MindNode root;
  final List<MindNode> nodes;
  final List<MindEdge> edges;
  final Rect bounds;
  const MindMap(this.root, this.nodes, this.edges, this.bounds);
}

/// Arma el árbol del índice: raíz = cuaderno; hijos = secciones con títulos (si el cuaderno tiene una sola sección, los
/// títulos cuelgan de la raíz); cada título cuelga del anterior de un nivel menos. [untitled] reemplaza los textos vacíos.
MindNode buildMindTree(Notebook nb, List<OutlineEntry> outline, String untitled) {
  String t(String s) {
    final v = s.trim();
    return v.isEmpty ? untitled : v;
  }

  final root = MindNode(t(nb.name), MindKind.root, 0);
  final single = nb.sections.length == 1;
  for (final sec in nb.sections) {
    final mine = [for (final e in outline) if (e.sectionId == sec.id) e];
    if (mine.isEmpty) continue;
    final base = single ? root : MindNode(t(sec.name), MindKind.section, 1);
    if (!single) root.children.add(base);
    final stack = <MindNode>[]; // el último título de cada nivel
    for (final e in mine) {
      final level = math.min(math.max(e.level, 1), stack.length + 1); // un nivel nunca salta más de uno
      stack.length = level - 1;
      final parent = stack.isEmpty ? base : stack.last;
      final n = MindNode(t(e.title), MindKind.heading, parent.depth + 1);
      parent.children.add(n);
      stack.add(n);
    }
  }
  _tag(root);
  return root;
}

void _tag(MindNode root) {
  for (var i = 0; i < root.children.length; i++) {
    void go(MindNode n) {
      n.branch = i;
      n.children.forEach(go);
    }

    go(root.children[i]);
  }
}

/// Reparte las ramas de primer nivel entre derecha e izquierda, en orden, cortando donde la diferencia de hojas es menor
/// (con 2 ramas o más, cada lado tiene al menos una). Fija [MindNode.side] en cada nodo.
({List<MindNode> right, List<MindNode> left}) splitSides(MindNode root) {
  final b = root.children;
  var cut = b.length;
  if (b.length >= 2) {
    final total = root.leaves;
    var acc = 0, best = -1, bestDiff = 1 << 30;
    for (var k = 1; k < b.length; k++) {
      acc += b[k - 1].leaves;
      final diff = (acc - (total - acc)).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = k;
      }
    }
    cut = best;
  }
  final right = b.sublist(0, cut), left = b.sublist(cut);
  void mark(MindNode n, int s) {
    n.side = s;
    for (final c in n.children) {
      mark(c, s);
    }
  }

  for (final n in right) {
    mark(n, 1);
  }
  for (final n in left) {
    mark(n, -1);
  }
  return (right: right, left: left);
}

/// Acomoda el árbol como mapa mental: la raíz en el centro (0, 0) y, a cada lado, árboles horizontales con los hijos
/// apilados sin superponerse y el padre centrado respecto de ellos. [measure] da el tamaño de un nodo según su texto y
/// su profundidad. [hGap] separa columnas y [vGap] hermanos.
MindMap layoutMindMap(MindNode root, Size Function(String text, int depth) measure, {double hGap = 44, double vGap = 10}) {
  final sides = splitSides(root);

  Size sz(MindNode n) => measure(n.text, n.depth);

  // Coloca el subárbol de [n] con su borde cercano en [edge] (su padre queda hacia [dir]) y todo por debajo de [start].
  // Devuelve el borde de abajo del subárbol.
  double place(MindNode n, double edge, int dir, double start) {
    final s = sz(n);
    final x = dir > 0 ? edge : edge - s.width;
    final next = dir > 0 ? x + s.width + hGap : x - hGap;
    if (n.children.isEmpty) {
      n.rect = Rect.fromLTWH(x, start, s.width, s.height);
      return start + s.height;
    }
    var cursor = start, bottom = start;
    for (final c in n.children) {
      bottom = place(c, next, dir, cursor);
      cursor = bottom + vGap;
    }
    final first = n.children.first.rect.top, last = n.children.last.rect.bottom;
    final span = last - first;
    if (s.height > span) {
      final d = (s.height - span) / 2;
      for (final c in n.children) {
        _shift(c, d);
      }
      bottom += d;
    }
    final mid = (first + last) / 2 + (s.height > span ? (s.height - span) / 2 : 0);
    n.rect = Rect.fromLTWH(x, mid - s.height / 2, s.width, s.height);
    return math.max(bottom, n.rect.bottom);
  }

  // Apila las ramas de un lado y las centra verticalmente alrededor de y = 0.
  void side(List<MindNode> branches, double edge, int dir) {
    if (branches.isEmpty) return;
    var cursor = 0.0;
    for (final b in branches) {
      cursor = place(b, edge, dir, cursor) + vGap;
    }
    final top = branches.map(_top).reduce(math.min), bottom = branches.map(_bottom).reduce(math.max);
    final d = -(top + bottom) / 2;
    for (final b in branches) {
      _shift(b, d);
    }
  }

  final rs = sz(root);
  root.rect = Rect.fromCenter(center: Offset.zero, width: rs.width, height: rs.height);
  side(sides.right, root.rect.right + hGap, 1);
  side(sides.left, root.rect.left - hGap, -1);

  final nodes = <MindNode>[];
  final edges = <MindEdge>[];
  void walk(MindNode n) {
    nodes.add(n);
    for (final c in n.children) {
      edges.add(MindEdge(n, c));
      walk(c);
    }
  }

  walk(root);
  var bounds = root.rect;
  for (final n in nodes) {
    bounds = bounds.expandToInclude(n.rect);
  }
  return MindMap(root, nodes, edges, bounds);
}

void _shift(MindNode n, double dy) {
  n.rect = n.rect.shift(Offset(0, dy));
  for (final c in n.children) {
    _shift(c, dy);
  }
}

double _top(MindNode n) => n.children.fold(n.rect.top, (m, c) => math.min(m, _top(c)));
double _bottom(MindNode n) => n.children.fold(n.rect.bottom, (m, c) => math.max(m, _bottom(c)));

String _xmlAttr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      case 0x0A:
        b.write('&#10;');
      case 0x0D:
        b.write('&#13;');
      case 0x09:
        b.write('&#9;');
      default:
        if (r < 0x20 || r == 0xFFFE || r == 0xFFFF || (r >= 0xD800 && r <= 0xDFFF)) continue; // no válidos en XML 1.0
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// El mapa en formato FreeMind (`.mm`), que abren Freeplane, XMind y compañía. Las ramas de primer nivel llevan
/// `POSITION` (derecha o izquierda) igual que en el dibujo.
String mindMapToFreeMind(MindNode root) {
  splitSides(root);
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<map version="1.0.1">\n');
  void node(MindNode n, int indent) {
    final pad = '  ' * indent;
    final pos = n.depth == 1 ? ' POSITION="${n.side > 0 ? 'right' : 'left'}"' : '';
    final open = '$pad<node TEXT="${_xmlAttr(n.text)}"$pos';
    if (n.children.isEmpty) {
      b.writeln('$open/>');
      return;
    }
    b.writeln('$open>');
    for (final c in n.children) {
      node(c, indent + 1);
    }
    b.writeln('$pad</node>');
  }

  node(root, 1);
  b.writeln('</map>');
  return b.toString();
}
