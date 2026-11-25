// Datos de ejemplo para las capturas del README: carpetas, cuadernos y "escritura a mano" sintética.
// NUNCA se usan cuadernos reales: todo se escribe en la carpeta temporal que le pasa screenshots_test.dart.
//
// La letra es texto real en cursiva de un solo trazo (fuente Hershey, ver hershey_script.dart), con variaciones
// al azar; sale de un Random con semilla fija, así las capturas salen siempre iguales.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:pdf/widgets.dart' as pw;

import 'hershey_script.dart';

const shotLang = String.fromEnvironment('SHOT_LANG', defaultValue: 'es');
bool get _en => shotLang == 'en';

/// Elige el texto de ejemplo según el idioma de las capturas (`--dart-define=SHOT_LANG=es|en`; por defecto es).
String tr(String es, String en) => _en ? en : es;

// Nombres de los cuadernos (el test los abre por su key `nb-<nombre>`).
final nbPhysics = tr('Física – Óptica', 'Physics – Optics');
final nbCalcII = tr('Análisis II', 'Calculus II');
final nbMeeting = tr('Reunión lunes', 'Monday meeting');
final nbShopping = tr('Lista de compras', 'Shopping list');
final nbAlgebra = tr('Álgebra lineal', 'Linear algebra');
final nbProbability = tr('Probabilidad', 'Probability');
final nbReport = tr('Informe trimestral', 'Quarterly report');
final nbAppIdeas = tr('Ideas de app', 'App ideas');
final nbAnalysis = tr('Análisis Matemático II', 'Mathematical Analysis');
final nbControl = tr('Sistemas de control', 'Control systems');
final nbWorksheet = tr('Práctica 3', 'Worksheet 3');

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
  final facultad = Folder.create(tr('Facultad', 'University')), trabajo = Folder.create(tr('Trabajo', 'Work')), ideas = Folder.create(tr('Ideas', 'Ideas'));
  final folders = [facultad, trabajo, ideas];

  // --- Física – Óptica: el cuaderno de las capturas (3 hojas) ---
  final fisica = _notebook(nbPhysics, 3, favorite: true, minutesAgo: 5, titles: [tr('Lentes delgadas', 'Thin lenses'), tr('Ley de Snell', "Snell's law"), tr('Ejercicios', 'Exercises')]);
  fisica.sheets[1].bookmark = true;
  final h1 = _hand(r, 10, [
    tr('Los rayos paralelos al eje se desvían hacia el foco F.', 'Rays parallel to the axis bend toward the focus F.'),
    tr('Distancia focal: f = 15 cm (lente biconvexa).', 'Focal length: f = 15 cm (biconvex lens).'),
    tr('Ecuación de lentes: 1/f = 1/do + 1/di', 'Lens equation: 1/f = 1/do + 1/di'),
    tr('Aumento: A = -di/do = hi/ho', 'Magnification: M = -di/do = hi/ho'),
    tr('Si do > 2f la imagen es real, invertida y menor.', 'If do > 2f the image is real, inverted and smaller.'),
  ]);
  h1.texts.add(typed(_textY(2) - 8, [
    _title(tr('Óptica geométrica', 'Geometric optics')),
    Para([
      Run(tr('Una ', 'A ')),
      Run(tr('lente convergente', 'converging lens'), RunStyle(bold: true)),
      Run(tr(' desvía los rayos paralelos al eje hacia el foco.', ' bends rays parallel to the axis toward the focus.')),
    ]),
  ], w: 500));
  h1.items.add(sticky(690, 95, tr('Repasar para el parcial del viernes', 'Review for the Friday midterm'), w: 250, h: 175));
  final label = write(r, _rule(17), tr('Lente convergente', 'Converging lens'), x0: 150, color: _blue);
  final eq = span(h1.strokes.where((s) => s.bounds.center.dy > _rule(11) && s.bounds.center.dy < _rule(12)).toList());
  h1.strokes
    ..add(highlighter(eq.left - 6, eq.right + 6, eq.center.dy + 3))
    ..addAll(lensDiagram(r, axisY: 760))
    ..addAll(label)
    ..add(underline(r, 150, span(label).right, _rule(17) + 6, _blue))
    ..addAll(write(r, _rule(24), tr('Con f = 15 cm y do = 40 cm: di = 24 cm.', 'With f = 15 cm and do = 40 cm: di = 24 cm.')))
    ..addAll(write(r, _rule(25), tr('La imagen es real, invertida y más chica.', 'The image is real, inverted and smaller.')));
  final h2 = _hand(r, 5, [
    tr('Al pasar de un medio a otro, el rayo se desvía.', 'Going from one medium to another, the ray bends.'),
    tr('n1 y n2: índices de refracción de cada medio.', 'n1 and n2: refractive index of each medium.'),
    tr('n_1 sen θ_1 = n_2 sen θ_2', 'n_1 sin θ_1 = n_2 sin θ_2'),
    tr('Aire a vidrio (n = 1,5), θ_1 = 30 grados:', 'Air to glass (n = 1.5), θ_1 = 30 degrees:'),
    tr('sen θ_2 = 0,33  =>  θ_2 = 19,5 grados', 'sin θ_2 = 0.33  =>  θ_2 = 19.5 degrees'),
    tr('Más denso: el rayo se acerca a la normal.', 'Denser medium: the ray bends toward the normal.'),
    tr('Reflexión total interna: sen θ_c = n_2 / n_1', 'Total internal reflection: sin θ_c = n_2 / n_1'),
    tr('(solo si n_1 > n_2)', '(only if n_1 > n_2)'),
  ], blue: {2});
  final snell = span(h2.strokes.where((s) => s.bounds.center.dy > _rule(6) && s.bounds.center.dy < _rule(7)).toList());
  h2.texts.add(typed(_textY(2), [_title(tr('Ley de Snell', "Snell's law"))], w: 600));
  h2.strokes
    ..add(highlighter(snell.left - 6, snell.right + 6, snell.center.dy + 3))
    ..addAll(write(r, _rule(15), tr('Intensidad en función del tiempo', 'Intensity as a function of time'), x0: 200, color: _blue))
    ..addAll(graph(r, const Offset(200, 620), 620, 300));
  final h3 = _hand(r, 5, [
    tr('1) Lente con f = 20 cm y objeto a 50 cm.', '1) Lens with f = 20 cm and object at 50 cm.'),
    tr('Hallar la posición de la imagen y el aumento.', 'Find the image position and the magnification.'),
    '1/di = 1/20 - 1/50 = 3/100',
    tr('di = 33,3 cm  (imagen real)', 'di = 33.3 cm  (real image)'),
    tr('A = -di/do = -0,67  (invertida y menor)', 'M = -di/do = -0.67  (inverted and smaller)'),
    tr('2) Repetir con do = 10 cm (menor que f).', '2) Repeat with do = 10 cm (less than f).'),
  ]);
  h3.texts.add(typed(_textY(2), [_title(tr('Ejercicios', 'Exercises'))], w: 600));
  h3.strokes.addAll(lensDiagram(r, axisY: 620));
  save(fisica, [h1, h2, h3]);

  // --- Análisis II (favorito) ---
  final analisis = _notebook(nbCalcII, 2, favorite: true, minutesAgo: 90, folder: null);
  final a1 = _hand(r, 7, [
    tr('lim f(x) = L (x -> a) si para todo e > 0', 'lim f(x) = L (x -> a) if for every e > 0'),
    tr('existe d > 0 con |x - a| < d => |f(x) - L| < e.', 'there is d > 0 with |x - a| < d => |f(x) - L| < e.'),
    tr('Ejemplo: lim (2x + 1) = 5 cuando x -> 2', 'Example: lim (2x + 1) = 5 as x -> 2'),
    tr('Dado e, tomo d = e/2: |2x - 4| = 2|x - 2| < e.', 'Given e, take d = e/2: |2x - 4| = 2|x - 2| < e.'),
    tr('f es continua en a si lim f(x) = f(a).', 'f is continuous at a if lim f(x) = f(a).'),
    tr('Discontinuidades: evitable, de salto y esencial.', 'Discontinuities: removable, jump and essential.'),
    tr('Hacer los ejercicios 4 al 9 de la práctica 3.', 'Do exercises 4 to 9 of worksheet 3.'),
  ], blue: {1});
  a1.texts.add(typed(_textY(2), [
    _title(tr('Límites y continuidad', 'Limits and continuity')),
    Para([Run(tr('Definición ε–δ', 'ε–δ definition'), RunStyle(bold: true)), Run(tr(' y ejemplos resueltos.', ' and worked examples.'))]),
  ]));
  a1.strokes.addAll(graph(r, const Offset(250, 760), 520, 280));
  final a2 = _hand(r, 5, [
    tr('Teorema del valor intermedio', 'Intermediate value theorem'),
    tr('Si f es continua en [a, b] y k está entre f(a) y f(b),', 'If f is continuous on [a, b] and f(a) < k < f(b),'),
    tr('existe c en [a, b] tal que f(c) = k.', 'there is c in [a, b] such that f(c) = k.'),
    tr('Ejemplo: cos(x) = x tiene solución en [0, 1].', 'Example: cos(x) = x has a solution in [0, 1].'),
    tr('Sea f(x) = cos(x) - x. Entonces f(0) = 1 > 0', 'Let f(x) = cos(x) - x. Then f(0) = 1 > 0'),
    tr('y f(1) = cos(1) - 1 < 0, así que hay una raíz.', 'and f(1) = cos(1) - 1 < 0, so there is a root.'),
    tr('Bolzano es el caso particular con k = 0.', 'Bolzano is the special case with k = 0.'),
  ]);
  save(analisis, [a1, a2]);

  // --- Reunión lunes ---
  final reunion = _notebook(nbMeeting, 1, minutesAgo: 200);
  final m = _hand(r, 14, [
    tr('Notas de la reunión:', 'Meeting notes:'),
    tr('- Ana cierra el informe el jueves', '- Ana closes the report on Thursday'),
    tr('- Pedir presupuesto del servidor', '- Ask for the server quote'),
    tr('- Demo con el cliente: martes', '- Client demo: Tuesday'),
  ], blue: {2}, maxWidth: 480);
  m.texts.add(typed(_textY(2), [
    _title(tr('Reunión de equipo', 'Team meeting')),
    _list(ListKind.bullet, tr('Revisar el avance del trimestre', 'Review progress this quarter')),
    _list(ListKind.bullet, tr('Definir prioridades de la semana', 'Set priorities for the week')),
    _list(ListKind.bullet, tr('Fecha de la próxima demo', 'Date of the next demo')),
  ]));
  m.items.add(sticky(660, 560, tr('Mandar el resumen antes del miércoles', 'Send the summary before Wednesday'), color: '#bfdbfe', w: 240, h: 150));
  save(reunion, [m]);

  // --- Lista de compras ---
  final compras = _notebook(nbShopping, 1, minutesAgo: 600);
  final l = SheetContent();
  l.texts.add(typed(_textY(2), [
    _title(nbShopping),
    _list(ListKind.checklist, tr('Yerba', 'Coffee beans'), checked: true),
    _list(ListKind.checklist, tr('Leche', 'Milk'), checked: true),
    _list(ListKind.checklist, tr('Pan y facturas', 'Bread and pastries')),
    _list(ListKind.checklist, tr('Tomates', 'Tomatoes')),
    _list(ListKind.checklist, tr('Café', 'Tea')),
    _list(ListKind.checklist, tr('Detergente', 'Detergent')),
  ]));
  save(compras, [l]);

  // --- adentro de las carpetas ---
  final notes = {
    nbAlgebra: [
      [tr('Matrices y determinantes', 'Matrices and determinants'), tr('det(A) = ad - bc para A de 2x2', 'det(A) = ad - bc for a 2x2 A'), tr('A tiene inversa si det(A) no es 0', 'A has an inverse if det(A) is not 0'), tr('Autovalores: det(A - L I) = 0', 'Eigenvalues: det(A - L I) = 0'), tr('Ejemplo: A = [2 1 ; 1 2] => L = 1 y 3', 'Example: A = [2 1 ; 1 2] => L = 1 and 3')],
      [tr('Espacios vectoriales', 'Vector spaces'), tr('Base: vectores L.I. que generan el espacio', 'Basis: independent vectors that span it'), 'dim(R3) = 3', tr('Rango de A = dim del espacio columna', 'Rank of A = dim of the column space'), tr('Teorema: rango + nulidad = n', 'Theorem: rank + nullity = n')],
    ],
    nbProbability: [
      [tr('Probabilidad condicional', 'Conditional probability'), tr('P(A|B) = P(A y B) / P(B)', 'P(A|B) = P(A and B) / P(B)'), tr('Independientes: P(A y B) = P(A) P(B)', 'Independent: P(A and B) = P(A) P(B)'), 'Bayes: P(A|B) = P(B|A) P(A) / P(B)', tr('Ejemplo: dos dados, P(suma = 7) = 1/6', 'Example: two dice, P(sum = 7) = 1/6')]
    ],
    nbReport: [
      [tr('Resumen del trimestre', 'Quarter summary'), tr('Ventas: +12 % respecto del anterior', 'Sales: +12 % over the previous one'), tr('Pendiente: cerrar el balance de marzo', 'Pending: close the March books'), tr('Mandar el borrador a Laura el lunes', 'Send the draft to Laura on Monday'), tr('Revisar los números con contaduría', 'Check the numbers with accounting')]
    ],
    nbAppIdeas: [
      [tr('Ideas para la app', 'Ideas for the app'), tr('Recordatorios por voz con aviso', 'Voice reminders with an alert'), tr('Modo oscuro automático al anochecer', 'Automatic dark mode at dusk'), tr('Exportar notas a PDF y a texto', 'Export notes to PDF and text'), tr('Probar con tres usuarios esta semana', 'Test with three users this week')]
    ],
  };
  for (final (name, f, n, ago) in [
    (nbAlgebra, facultad, 2, 1500),
    (nbProbability, facultad, 1, 2000),
    (nbReport, trabajo, 1, 800),
    (nbAppIdeas, ideas, 1, 3000),
  ]) {
    final nb = _notebook(name, n, folder: f.id, minutesAgo: ago);
    save(nb, [for (var i = 0; i < n; i++) _hand(r, 9, notes[name]![i], blue: {0})]);
  }

  for (final (nb, contents) in books) {
    await s.saveNotebook(NotebookDoc.fromSheets(nb, contents));
  }
  await s.saveIndex(NotesIndex(notebooks: [for (final b in books) b.$1], folders: folders));
}

// ---------- cuadernos extra (capturas 04, 05 y 06; se siembran DESPUÉS de las tres primeras) ----------

/// Trazos corridos [dx], [dy].
List<Stroke> _shift(List<Stroke> ss, double dx, double dy) => [
      for (final s in ss)
        Stroke(s.id, s.k, s.c, s.w, [for (var i = 0; i < s.pts.length; i += 3) ...[s.pts[i] + dx, s.pts[i + 1] + dy, s.pts[i + 2]]], s.o)
    ];

/// Texto a mano centrado en [c] (apoyado en la línea [base]).
List<Stroke> _centered(Random r, String text, double cx, double base, {double size = 1.12, String color = _ink}) {
  final raw = write(r, base, text, x0: 0, color: color, size: size, maxWidth: 2000);
  final b = span(raw);
  return _shift(raw, cx - b.center.dx, 0);
}

/// Título escrito a mano (más grande) que queda marcado en el índice de [m] con el [level] dado.
void _headed(Random r, SheetMeta m, SheetContent c, int level, double base, String text) {
  final ss = write(r, base, text, size: 1.65, maxWidth: 700);
  c.strokes.addAll(ss);
  m.heads.add(Heading(newId('h'), level: level, title: text, y: span(ss).top, ids: [for (final s in ss) s.id]));
}

Stroke _shape(ShapeFit f, {String color = _ink, double w = 2.8}) => _stroke('pen', color, w, f.toPoints(.62));
ShapeFit _rect(double l, double t, double rr, double b) =>
    ShapeFit(ShapeKind.rect, [Offset(l, t), Offset(rr, t), Offset(rr, b), Offset(l, b)], Offset((l + rr) / 2, (t + b) / 2));
List<Stroke> _arrow(Offset a, Offset b) {
  final d = (b - a).direction;
  return [_shape(ShapeFit(ShapeKind.line, [a, b], (a + b) / 2), color: _blue, w: 2.4), arrowHead(b, d)];
}

/// Agrega a la biblioteca ya sembrada: el cuaderno con índice (04), el del esquema (05) y uno vacío para importar el PDF (06).
Future<void> seedExtras(Storage s) async {
  final r = Random(21);
  final idx = await s.loadIndex();
  final now = DateTime.now().millisecondsSinceEpoch;

  // --- Análisis Matemático II: 4 hojas con títulos a mano marcados en el índice ---
  final am = Notebook(newId('n'), nbAnalysis, favorite: true, updated: now);
  for (final t in [tr('Límites', 'Limits'), tr('Continuidad', 'Continuity'), tr('Derivadas', 'Derivatives'), tr('Aplicaciones', 'Applications')]) {
    am.sheets.add(SheetMeta(newId('h'), title: t));
  }
  final c1 = SheetContent(), c2 = SheetContent(), c3 = SheetContent(), c4 = SheetContent();
  void lines(SheetContent c, int first, List<String> ls, {Set<int> blue = const {}}) {
    for (var i = 0; i < ls.length; i++) {
      c.strokes.addAll(write(r, _rule(first + i), ls[i], color: blue.contains(i) ? _blue : _ink));
    }
  }

  _headed(r, am.sheets[0], c1, 1, _rule(3), tr('Límites', 'Limits'));
  _headed(r, am.sheets[0], c1, 2, _rule(5), tr('Definición', 'Definition'));
  lines(c1, 6, [tr('lim f(x) = L (x -> a) si para todo e > 0', 'lim f(x) = L (x -> a) if for every e > 0'), tr('existe d > 0 con |x - a| < d => |f(x) - L| < e.', 'there is d > 0 with |x - a| < d => |f(x) - L| < e.'), tr('Ejemplo: lim (2x + 1) = 5 cuando x -> 2', 'Example: lim (2x + 1) = 5 as x -> 2')], blue: {0});
  _headed(r, am.sheets[0], c1, 2, _rule(11), tr('Propiedades', 'Properties'));
  lines(c1, 12, ['lim (f + g) = lim f + lim g', 'lim (f . g) = lim f . lim g', tr('lim (f / g) = lim f / lim g  si lim g no es 0', 'lim (f / g) = lim f / lim g  if lim g is not 0')]);
  _headed(r, am.sheets[1], c2, 2, _rule(3), tr('Continuidad', 'Continuity'));
  lines(c2, 4, [tr('f es continua en a si lim f(x) = f(a).', 'f is continuous at a if lim f(x) = f(a).'), tr('Discontinuidades: evitable, de salto y esencial.', 'Discontinuities: removable, jump and essential.')], blue: {0});
  _headed(r, am.sheets[1], c2, 2, _rule(8), tr('Valor intermedio', 'Intermediate value'));
  lines(c2, 9, [tr('Si f es continua en [a, b] y k está entre f(a) y f(b),', 'If f is continuous on [a, b] and f(a) < k < f(b),'), tr('existe c en [a, b] tal que f(c) = k.', 'there is c in [a, b] such that f(c) = k.'), tr('Bolzano es el caso k = 0.', 'Bolzano is the case k = 0.')]);
  _headed(r, am.sheets[2], c3, 1, _rule(3), tr('Derivadas', 'Derivatives'));
  lines(c3, 4, [tr("f'(a) = lim (f(a + h) - f(a)) / h  cuando h -> 0", "f'(a) = lim (f(a + h) - f(a)) / h  as h -> 0"), tr('Es la pendiente de la recta tangente en a.', 'It is the slope of the tangent line at a.')]);
  _headed(r, am.sheets[2], c3, 2, _rule(8), tr('Regla de la cadena', 'Chain rule'));
  lines(c3, 9, ["(f o g)'(x) = f'(g(x)) . g'(x)", tr('Ejemplo: h(x) = sen(x^2)  =>  h\'(x) = 2x cos(x^2)', "Example: h(x) = sin(x^2)  =>  h'(x) = 2x cos(x^2)")], blue: {0});
  _headed(r, am.sheets[2], c3, 2, _rule(13), tr('Regla del producto', 'Product rule'));
  lines(c3, 14, ["(f . g)' = f' . g + f . g'"]);
  _headed(r, am.sheets[3], c4, 1, _rule(3), tr('Aplicaciones', 'Applications'));
  lines(c4, 4, [tr('Optimizar: buscar los puntos donde f\'(x) = 0.', "Optimizing: look for the points where f'(x) = 0.")]);
  _headed(r, am.sheets[3], c4, 2, _rule(7), tr('Máximos y mínimos', 'Maxima and minima'));
  lines(c4, 8, [tr("Si f'(c) = 0 y f''(c) < 0, c es un máximo local.", "If f'(c) = 0 and f''(c) < 0, c is a local maximum."), tr("Si f'(c) = 0 y f''(c) > 0, c es un mínimo local.", "If f'(c) = 0 and f''(c) > 0, c is a local minimum.")], blue: {0});
  final nbAm = NotebookDoc.fromSheets(am, [c1, c2, c3, c4]);

  // --- Sistema de control: diagrama de bloques con figuras limpias ---
  final sc = Notebook(newId('n'), nbControl, updated: now - 60000);
  sc.sheets.add(SheetMeta(newId('h'), title: tr('Lazo cerrado', 'Closed loop'), bg: 'grid'));
  final d = SheetContent();
  d.strokes
    ..addAll(write(r, 170, tr('Control de temperatura', 'Temperature control'), x0: 130, size: 1.65, maxWidth: 740))
    ..addAll(_centered(r, 'Ref.', 190, 300, color: _blue))
    ..add(_shape(ShapeFit(ShapeKind.circle, const [], const Offset(190, 285), rx: 55, ry: 55)))
    ..addAll(_arrow(const Offset(190, 341), const Offset(190, 447)))
    ..add(_shape(_rect(80, 450, 300, 590)))
    ..addAll(_centered(r, 'Sensor', 190, 532))
    ..add(_shape(_rect(400, 450, 700, 590)))
    ..addAll(_centered(r, tr('Microcontrolador', 'Microcontroller'), 550, 532))
    ..add(_shape(_rect(780, 450, 960, 590)))
    ..addAll(_centered(r, tr('Actuador', 'Actuator'), 870, 532))
    ..addAll(_arrow(const Offset(300, 520), const Offset(398, 520)))
    ..addAll(_arrow(const Offset(700, 520), const Offset(778, 520)))
    ..add(_shape(ShapeFit(ShapeKind.ellipse, const [], const Offset(520, 800), rx: 260, ry: 80)))
    ..addAll(_centered(r, tr('Entorno (horno)', 'Environment (oven)'), 520, 812))
    ..addAll(_arrow(const Offset(860, 592), const Offset(762, 770)))
    ..addAll(_arrow(const Offset(282, 770), const Offset(190, 592)))
    ..addAll(write(r, 1000, tr('El sensor mide y se compara con la referencia.', 'The sensor reading is compared with the setpoint.'), x0: 130, maxWidth: 760))
    ..addAll(write(r, 1040, tr('Si falta calor, el actuador enciende la resistencia.', 'If it is too cold, the heater turns on.'), x0: 130, maxWidth: 760));
  final nbSc = NotebookDoc.fromSheets(sc, [d]);

  // --- Práctica 3: una hoja vacía (el PDF se importa en la captura 06) ---
  final pr = Notebook(newId('n'), nbWorksheet, updated: now - 120000);
  pr.sheets.add(SheetMeta(newId('h')));
  final nbPr = NotebookDoc.fromSheets(pr, [SheetContent()]);

  for (final doc in [nbAm, nbSc, nbPr]) {
    await s.saveNotebook(doc);
  }
  await s.saveIndex(NotesIndex(notebooks: [...idx.notebooks, am, sc, pr], folders: idx.folders));
}

/// Posiciones (en puntos del PDF A4 de 595 x 842) de cada enunciado de [buildPracticePdf], para anotar encima.
const practiceTop = {1: 150.0, 2: 270.0, 3: 390.0, 4: 510.0};

/// PDF de 2 hojas que parece una práctica impresa: título y enunciados numerados en posiciones fijas.
Future<Uint8List> buildPracticePdf() async {
  final d = pw.Document();
  pw.Widget at(double top, String text, {double size = 12, bool bold = false, double left = 50, double width = 495}) => pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(width: width, child: pw.Text(text, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))));
  pw.Widget page(List<pw.Widget> ch) => pw.Stack(children: ch);
  final ex = [
    tr('1) Calcular el límite lim (3x + 1) cuando x tiende a 2.', '1) Compute the limit lim (3x + 1) as x tends to 2.'),
    tr('2) Calcular lim sen(x) / x cuando x tiende a 0.', '2) Compute lim sin(x) / x as x tends to 0.'),
    tr('3) Hallar el valor de a para que f sea continua en x = 1.', '3) Find the value of a so that f is continuous at x = 1.'),
    tr('4) Probar con la definición que lim (2x - 1) = 3 cuando x -> 2.', '4) Prove from the definition that lim (2x - 1) = 3 as x -> 2.'),
  ];
  d.addPage(pw.Page(
    margin: pw.EdgeInsets.zero,
    build: (_) => page([
      at(40, tr('Análisis Matemático II  ·  Facultad de Ingeniería', 'Mathematical Analysis  ·  School of Engineering'), size: 10),
      at(62, tr('Práctica 3: Límites y continuidad', 'Worksheet 3: Limits and continuity'), size: 22, bold: true),
      at(100, tr('Resolver los ejercicios. Justificar cada paso.', 'Solve the exercises. Justify every step.'), size: 11),
      for (var i = 0; i < 4; i++) at(practiceTop[i + 1]!, ex[i]),
    ]),
  ));
  d.addPage(pw.Page(
    margin: pw.EdgeInsets.zero,
    build: (_) => page([
      at(40, tr('Análisis Matemático II  ·  Práctica 3', 'Mathematical Analysis  ·  Worksheet 3'), size: 10),
      at(80, tr('5) Estudiar la continuidad de f(x) = (x^2 - 1) / (x - 1).', '5) Study the continuity of f(x) = (x^2 - 1) / (x - 1).')),
      at(200, tr('6) Calcular lim (x^2 - 4) / (x - 2) cuando x tiende a 2.', '6) Compute lim (x^2 - 4) / (x - 2) as x tends to 2.')),
    ]),
  ));
  return Uint8List.fromList(await d.save());
}
