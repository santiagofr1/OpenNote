// Datos de ejemplo para las capturas del README: carpetas, cuadernos y "escritura a mano" sintética.
// NUNCA se usan cuadernos reales: todo se escribe en la carpeta temporal que le pasa screenshots_test.dart.
//
// La letra es texto real en cursiva de un solo trazo (fuente Hershey, ver hershey_script.dart), con variaciones
// al azar; sale de un Random con semilla fija, así las capturas salen siempre iguales.

import 'dart:math';
import 'dart:ui';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';

import 'hershey_script.dart';

const _ink = '#22211e', _blue = '#1d4ed8', _grey = '#6b6b66';

Stroke _stroke(String kind, String color, double w, List<double> pts, [double o = 1]) =>
    Stroke(newId('s'), kind, color, w, pts, o);

/// Un renglón escrito a mano apoyado sobre la línea de rayado [base] (la letra queda 3 unidades arriba).
List<Stroke> write(Random r, double base, String text,
        {double x0 = 150, double maxWidth = 780, String color = _ink, double size = 1.12}) =>
    handwrite(text, Offset(x0, base - 3), rnd: r, color: color, maxWidth: maxWidth, size: size);

/// Rectángulo que ocupan [strokes] (para subrayar o resaltar lo escrito).
Rect span(List<Stroke> strokes) => strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));

/// Subrayado ondulado.
Stroke underline(Random r, double x0, double x1, double y, String color) {
  final pts = <double>[];
  for (var x = x0; x <= x1; x += 3) {
    pts.addAll([x, y + sin((x - x0) / 38) * 1.4 + (r.nextDouble() - .5) * .6, .55]);
  }
  return _stroke('pen', color, 2.2, pts);
}

/// Recta de [a] a [b] con apenas temblor.
Stroke line(Random r, Offset a, Offset b, {String color = _ink, double w = 2.4, String kind = 'pen', double wobble = .35}) {
  final n = max(4, ((b - a).distance / 6).ceil());
  final pts = <double>[];
  for (var i = 0; i <= n; i++) {
    final p = Offset.lerp(a, b, i / n)!;
    pts.addAll([p.dx + (r.nextDouble() - .5) * wobble, p.dy + (r.nextDouble() - .5) * wobble, .62]);
  }
  return _stroke(kind, color, w, pts);
}

/// Punta de flecha en [tip] mirando hacia [dir] (ángulo en radianes).
Stroke arrowHead(Offset tip, double dir, {String color = _blue, double len = 15}) {
  final pts = <double>[];
  for (final side in [-1, 0, 1]) {
    final p = side == 0 ? tip : tip - Offset.fromDirection(dir + side * .45, len);
    pts.addAll([p.dx, p.dy, .65]);
  }
  return _stroke('pen', color, 2.4, pts);
}

/// Línea con una flecha en [t] (0..1) y otra opcional en la punta.
List<Stroke> arrowLine(Random r, Offset a, Offset b, {String color = _blue, double midArrow = .5, bool tip = false}) {
  final d = (b - a).direction;
  return [
    line(r, a, b, color: color, w: 2.2),
    if (midArrow > 0) arrowHead(Offset.lerp(a, b, midArrow)! + Offset.fromDirection(d, 7), d, color: color),
    if (tip) arrowHead(b, d, color: color),
  ];
}

Stroke ellipse(Offset c, double rx, double ry, {String color = _ink, double w = 3}) {
  final pts = <double>[];
  for (var i = 0; i <= 64; i++) {
    final a = -pi / 2 + 2 * pi * i / 64 * 1.01;
    pts.addAll([c.dx + rx * cos(a), c.dy + ry * sin(a), .7]);
  }
  return _stroke('pen', color, w, pts);
}

/// Lente delgada convergente: eje óptico, lente, tres rayos paralelos que se juntan en el foco, y marcas.
List<Stroke> lensDiagram(Random r, {double axisY = 760}) {
  const lensX = 500.0, focusX = 760.0, leftX = 190.0;
  final f = Offset(focusX, axisY);
  final out = <Stroke>[
    line(r, Offset(150, axisY), Offset(930, axisY), color: _grey, w: 1.6, kind: 'fine'),
    ellipse(Offset(lensX, axisY), 24, 118),
  ];
  for (final h in [-85.0, -40.0, 45.0, 90.0]) {
    final p = Offset(lensX, axisY + h);
    out
      ..addAll(arrowLine(r, Offset(leftX, axisY + h), p, midArrow: .5))
      ..addAll(arrowLine(r, p, Offset.lerp(p, f, 1.25)!, midArrow: .55));
  }
  out
    ..add(ellipse(f, 4, 4, color: _blue, w: 3))
    ..add(ellipse(Offset(lensX - 260, axisY), 4, 4, color: _grey, w: 2.5))
    ..add(line(r, Offset(focusX, axisY + 12), Offset(focusX, axisY + 24), color: _grey, w: 1.6, kind: 'fine'));
  out
    ..addAll(write(r, axisY + 50, 'F', x0: focusX - 5, color: _blue, size: 1.1))
    ..addAll(write(r, axisY + 50, '-F', x0: lensX - 275, color: _grey, size: 1.1));
  return out;
}

/// Ejes con una curva amortiguada (gráfico de ejemplo).
List<Stroke> graph(Random r, Offset origin, double w, double h, {String color = _blue}) {
  final out = <Stroke>[
    ...arrowLine(r, origin + Offset(0, h * .5), origin + Offset(w, h * .5), color: _ink, midArrow: 0, tip: true),
    ...arrowLine(r, origin + Offset(0, h), origin, color: _ink, midArrow: 0, tip: true),
  ];
  final pts = <double>[];
  for (var i = 0; i <= 90; i++) {
    final u = i / 90, x = origin.dx + u * (w - 20);
    pts.addAll([x, origin.dy + h * .5 - sin(u * 4.5 * pi) * exp(-u * 2.2) * h * .42, .6]);
  }
  out.add(_stroke('pen', color, 2.8, pts));
  for (var i = 1; i < 5; i++) {
    final x = origin.dx + w * i / 5;
    out.add(line(r, Offset(x, origin.dy + h * .5 - 6), Offset(x, origin.dy + h * .5 + 6), w: 1.8, wobble: 0));
  }
  return out;
}

/// Resaltador amarillo horizontal.
Stroke highlighter(double x0, double x1, double y) {
  final pts = <double>[];
  for (var x = x0; x <= x1; x += 12) {
    pts.addAll([x, y, .5]);
  }
  return _stroke('hl', '#f7d22c', 22, pts, .4);
}

// ---------- texto con teclado ----------
TextBlock typed(double y, List<Para> paras, {double x = 140, double w = 780}) =>
    TextBlock(newId('t'), x, y, w, '', body: RichBody(paras));

Para _title(String s) => Para([Run(s)], style: ParaStyle.title);
Para _list(ListKind kind, String s, {bool checked = false}) => Para([Run(s)], list: kind, checked: checked);

/// y de un renglón de texto de la hoja lisa de 8 mm (la y del bloque queda un poquito debajo de la línea)
double _textY(int ruleNumber) => mmToUnits(8) * ruleNumber + textInset(mmToUnits(8));
/// y de la línea de rayado número [n] (8 mm)
double _rule(int n) => mmToUnits(8) * n;

Item sticky(double x, double y, String text, {String color = '#fde68a', double w = 240, double h = 170}) =>
    Item(newId('i'), 'sticky', x, y, w, h, text: text, color: color);

// ---------- cuadernos ----------
Notebook _notebook(String name, int sheets, {String? folder, bool favorite = false, int minutesAgo = 0, List<String>? titles}) {
  final nb = Notebook(newId('n'), name,
      favorite: favorite,
      folder: folder,
      updated: DateTime.now().millisecondsSinceEpoch - minutesAgo * 60000);
  for (var i = 0; i < sheets; i++) {
    nb.sheets.add(SheetMeta(newId('h'), title: titles != null && i < titles.length ? titles[i] : ''));
  }
  return nb;
}

/// Hoja con [lines] escritos a mano, uno por renglón de rayado desde el número [first]; los de [blue] en azul.
SheetContent _hand(Random r, int first, List<String> lines, {Set<int> blue = const {}, double maxWidth = 780}) {
  final c = SheetContent();
  for (var i = 0; i < lines.length; i++) {
    c.strokes.addAll(write(r, _rule(first + i), lines[i], color: blue.contains(i) ? _blue : _ink, maxWidth: maxWidth));
  }
  return c;
}

/// Crea la biblioteca de ejemplo en [s] (ya con `init()`).
Future<void> seedLibrary(Storage s) async {
  final r = Random(7);
  final books = <(Notebook, List<SheetContent>)>[];
  void save(Notebook nb, List<SheetContent> contents) => books.add((nb, contents));
  final facultad = Folder.create('Facultad'), trabajo = Folder.create('Trabajo'), ideas = Folder.create('Ideas');
  final folders = [facultad, trabajo, ideas];

  // --- Física – Óptica: el cuaderno de las capturas (3 hojas) ---
  final fisica = _notebook('Física – Óptica', 3, favorite: true, minutesAgo: 5, titles: ['Lentes delgadas', 'Ley de Snell', 'Ejercicios']);
  fisica.sheets[1].bookmark = true;
  final h1 = _hand(r, 10, [
    'Los rayos paralelos al eje se desvían hacia el foco F.',
    'Distancia focal: f = 15 cm (lente biconvexa).',
    'Ecuación de lentes: 1/f = 1/do + 1/di',
    'Aumento: A = -di/do = hi/ho',
    'Si do > 2f la imagen es real, invertida y menor.',
  ]);
  h1.texts.add(typed(_textY(2) - 8, [
    _title('Óptica geométrica'),
    Para([
      const Run('Una '),
      const Run('lente convergente', RunStyle(bold: true)),
      const Run(' desvía los rayos paralelos al eje hacia el foco.'),
    ]),
  ], w: 500));
  h1.items.add(sticky(690, 95, 'Repasar para el parcial del viernes', w: 250, h: 175));
  final label = write(r, _rule(17), 'Lente convergente', x0: 150, color: _blue);
  final eq = span(h1.strokes.where((s) => s.bounds.center.dy > _rule(11) && s.bounds.center.dy < _rule(12)).toList());
  h1.strokes
    ..add(highlighter(eq.left - 6, eq.right + 6, eq.center.dy + 3))
    ..addAll(lensDiagram(r, axisY: 760))
    ..addAll(label)
    ..add(underline(r, 150, span(label).right, _rule(17) + 6, _blue))
    ..addAll(write(r, _rule(24), 'Con f = 15 cm y do = 40 cm: di = 24 cm.'))
    ..addAll(write(r, _rule(25), 'La imagen es real, invertida y más chica.'));
  final h2 = _hand(r, 5, [
    'Al pasar de un medio a otro, el rayo se desvía.',
    'n1 y n2: índices de refracción de cada medio.',
    'n_1 sen θ_1 = n_2 sen θ_2',
    'Aire a vidrio (n = 1,5), θ_1 = 30 grados:',
    'sen θ_2 = 0,33  =>  θ_2 = 19,5 grados',
    'Más denso: el rayo se acerca a la normal.',
    'Reflexión total interna: sen θ_c = n_2 / n_1',
    '(solo si n_1 > n_2)',
  ], blue: {2});
  final snell = span(h2.strokes.where((s) => s.bounds.center.dy > _rule(6) && s.bounds.center.dy < _rule(7)).toList());
  h2.texts.add(typed(_textY(2), [_title('Ley de Snell')], w: 600));
  h2.strokes
    ..add(highlighter(snell.left - 6, snell.right + 6, snell.center.dy + 3))
    ..addAll(write(r, _rule(15), 'Intensidad en función del tiempo', x0: 200, color: _blue))
    ..addAll(graph(r, const Offset(200, 620), 620, 300));
  final h3 = _hand(r, 5, [
    '1) Lente con f = 20 cm y objeto a 50 cm.',
    'Hallar la posición de la imagen y el aumento.',
    '1/di = 1/20 - 1/50 = 3/100',
    'di = 33,3 cm  (imagen real)',
    'A = -di/do = -0,67  (invertida y menor)',
    '2) Repetir con do = 10 cm (menor que f).',
  ]);
  h3.texts.add(typed(_textY(2), [_title('Ejercicios')], w: 600));
  h3.strokes.addAll(lensDiagram(r, axisY: 620));
  save(fisica, [h1, h2, h3]);

  // --- Análisis II (favorito) ---
  final analisis = _notebook('Análisis II', 2, favorite: true, minutesAgo: 90, folder: null);
  final a1 = _hand(r, 7, [
    'lim f(x) = L (x -> a) si para todo e > 0',
    'existe d > 0 con |x - a| < d => |f(x) - L| < e.',
    'Ejemplo: lim (2x + 1) = 5 cuando x -> 2',
    'Dado e, tomo d = e/2: |2x - 4| = 2|x - 2| < e.',
    'f es continua en a si lim f(x) = f(a).',
    'Discontinuidades: evitable, de salto y esencial.',
    'Hacer los ejercicios 4 al 9 de la práctica 3.',
  ], blue: {1});
  a1.texts.add(typed(_textY(2), [
    _title('Límites y continuidad'),
    Para([const Run('Definición ε–δ', RunStyle(bold: true)), const Run(' y ejemplos resueltos.')]),
  ]));
  a1.strokes.addAll(graph(r, const Offset(250, 760), 520, 280));
  final a2 = _hand(r, 5, [
    'Teorema del valor intermedio',
    'Si f es continua en [a, b] y k está entre f(a) y f(b),',
    'existe c en [a, b] tal que f(c) = k.',
    'Ejemplo: cos(x) = x tiene solución en [0, 1].',
    'Sea f(x) = cos(x) - x. Entonces f(0) = 1 > 0',
    'y f(1) = cos(1) - 1 < 0, así que hay una raíz.',
    'Bolzano es el caso particular con k = 0.',
  ]);
  save(analisis, [a1, a2]);

  // --- Reunión lunes ---
  final reunion = _notebook('Reunión lunes', 1, minutesAgo: 200);
  final m = _hand(r, 14, [
    'Notas de la reunión:',
    '- Ana cierra el informe el jueves',
    '- Pedir presupuesto del servidor',
    '- Demo con el cliente: martes',
  ], blue: {2}, maxWidth: 480);
  m.texts.add(typed(_textY(2), [
    _title('Reunión de equipo'),
    _list(ListKind.bullet, 'Revisar el avance del trimestre'),
    _list(ListKind.bullet, 'Definir prioridades de la semana'),
    _list(ListKind.bullet, 'Fecha de la próxima demo'),
  ]));
  m.items.add(sticky(660, 560, 'Mandar el resumen antes del miércoles', color: '#bfdbfe', w: 240, h: 150));
  save(reunion, [m]);

  // --- Lista de compras ---
  final compras = _notebook('Lista de compras', 1, minutesAgo: 600);
  final l = SheetContent();
  l.texts.add(typed(_textY(2), [
    _title('Lista de compras'),
    _list(ListKind.checklist, 'Yerba', checked: true),
    _list(ListKind.checklist, 'Leche', checked: true),
    _list(ListKind.checklist, 'Pan y facturas'),
    _list(ListKind.checklist, 'Tomates'),
    _list(ListKind.checklist, 'Café'),
    _list(ListKind.checklist, 'Detergente'),
  ]));
  save(compras, [l]);

  // --- adentro de las carpetas ---
  const notes = {
    'Álgebra lineal': [
      ['Matrices y determinantes', 'det(A) = ad - bc para A de 2x2', 'A tiene inversa si det(A) no es 0', 'Autovalores: det(A - L I) = 0', 'Ejemplo: A = [2 1 ; 1 2] => L = 1 y 3'],
      ['Espacios vectoriales', 'Base: vectores L.I. que generan el espacio', 'dim(R3) = 3', 'Rango de A = dim del espacio columna', 'Teorema: rango + nulidad = n'],
    ],
    'Probabilidad': [
      ['Probabilidad condicional', 'P(A|B) = P(A y B) / P(B)', 'Independientes: P(A y B) = P(A) P(B)', 'Bayes: P(A|B) = P(B|A) P(A) / P(B)', 'Ejemplo: dos dados, P(suma = 7) = 1/6']
    ],
    'Informe trimestral': [
      ['Resumen del trimestre', 'Ventas: +12 % respecto del anterior', 'Pendiente: cerrar el balance de marzo', 'Mandar el borrador a Laura el lunes', 'Revisar los números con contaduría']
    ],
    'Ideas de app': [
      ['Ideas para la app', 'Recordatorios por voz con aviso', 'Modo oscuro automático al anochecer', 'Exportar notas a PDF y a texto', 'Probar con tres usuarios esta semana']
    ],
  };
  for (final (name, f, n, ago) in [
    ('Álgebra lineal', facultad, 2, 1500),
    ('Probabilidad', facultad, 1, 2000),
    ('Informe trimestral', trabajo, 1, 800),
    ('Ideas de app', ideas, 1, 3000),
  ]) {
    final nb = _notebook(name, n, folder: f.id, minutesAgo: ago);
    save(nb, [for (var i = 0; i < n; i++) _hand(r, 9, notes[name]![i], blue: {0})]);
  }

  for (final (nb, contents) in books) {
    await s.saveNotebook(NotebookDoc.fromSheets(nb, contents));
  }
  await s.saveIndex(NotesIndex(notebooks: [for (final b in books) b.$1], folders: folders));
}
