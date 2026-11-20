import 'dart:ui';

import 'elements.dart';
import 'geometry.dart';
import 'notebook.dart';
import 'stroke.dart';
import 'values.dart';

/// Lo que hay en una hoja, con coordenadas LOCALES (y = 0 es el borde de arriba de esa hoja).
/// Es lo que se guarda en cada archivo `.sheet`.
class SheetContent {
  final List<Stroke> strokes;
  final List<TextBlock> texts;
  final List<Item> items;
  SheetContent({List<Stroke>? strokes, List<TextBlock>? texts, List<Item>? items})
      : strokes = strokes ?? [],
        texts = texts ?? [],
        items = items ?? [];

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;
}

/// El cuaderno abierto en memoria: una tira continua de hojas.
///
/// Trazos, textos y elementos viven en coordenadas GLOBALES de la tira (la hoja k ocupa
/// y de `k * kSheetStep` a `k * kSheetStep + kSheetH`), así el editor, la selección, la tinta
/// y el deshacer funcionan igual que con una sola página larga.
/// Cada elemento pertenece a la hoja que contiene su borde de arriba ([sheetOfY]).
/// Un solo mapa ordenado por tipo: el orden de inserción es el orden de dibujo.
class NotebookDoc {
  final Notebook nb;
  final Map<String, Stroke> strokes;
  final Map<String, TextBlock> texts;
  final Map<String, Item> items;

  NotebookDoc(this.nb, {Map<String, Stroke>? strokes, Map<String, TextBlock>? texts, Map<String, Item>? items})
      : strokes = strokes ?? {},
        texts = texts ?? {},
        items = items ?? {} {
    if (nb.sheets.isEmpty) nb.sheets.add(nb.newSheet()); // un cuaderno siempre tiene al menos una hoja
  }

  /// Un documento de una sola hoja suelta (miniaturas de la biblioteca).
  factory NotebookDoc.single(SheetMeta meta, SheetContent c) =>
      NotebookDoc.fromSheets(Notebook('', '', sheets: [meta]), [c]);

  String get id => nb.id;
  List<SheetMeta> get sheets => nb.sheets;
  int get sheetCount => sheets.length;

  /// Alto de toda la tira.
  double get h => heightFor(sheets.length);

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;

  /// Hoja que contiene la altura [y] (el espacio entre hojas cuenta para la de arriba).
  int sheetOfY(double y) => (y / kSheetStep).floor().clamp(0, sheets.length - 1);

  int _sheetOfStroke(Stroke s) => sheetOfY(s.bounds.top);

  // ================= hojas al final =================
  /// Agrega una hoja al final con el estilo del cuaderno.
  void addSheet() => sheets.add(nb.newSheet());

  /// Agrega hojas hasta que [y] quede a menos de una hoja del final (escribir o pegar abajo).
  void growFor(double y) {
    final want = y ~/ kSheetStep + 2;
    if (y > h - 250) {
      while (sheets.length < want) {
        addSheet();
      }
    }
  }

  /// La última hoja no tiene nada: se puede quitar.
  bool get lastSheetEmpty {
    final top = (sheets.length - 1) * kSheetStep;
    return !strokes.values.any((s) => s.bounds.bottom > top) &&
        !texts.values.any((t) => t.y + kLine > top) &&
        !items.values.any((i) => i.y + i.h > top);
  }

  /// Quita la última hoja si hay más de una y está vacía.
  bool removeLastSheetIfEmpty() {
    if (sheets.length < 2 || !lastSheetEmpty) return false;
    sheets.removeLast();
    return true;
  }

  // ================= operaciones sobre hojas =================
  // Todas corren los elementos en el lugar (los objetos son los mismos: los campos de texto
  // y la selección que los referencian siguen valiendo, pero el deshacer ya no).

  /// Corre [dy] los elementos de las hojas para las que [test] da verdadero.
  void _shiftWhere(bool Function(int sheet) test, double dy) {
    if (dy == 0) return;
    for (final s in strokes.values) {
      if (test(_sheetOfStroke(s))) s.translateY(dy);
    }
    for (final t in texts.values) {
      if (test(sheetOfY(t.y))) t.y += dy;
    }
    for (final i in items.values) {
      if (test(sheetOfY(i.y))) i.y += dy;
    }
  }

  /// Hoja nueva en la posición [at] (0..cantidad): lo que estaba desde ahí baja una hoja.
  /// [content] (coordenadas locales) se pone adentro; se usa tal cual, sin copiar.
  SheetMeta insertSheet(int at, {SheetMeta? meta, SheetContent? content}) {
    at = at.clamp(0, sheets.length);
    _shiftWhere((k) => k >= at, kSheetStep);
    final m = meta ?? nb.newSheet();
    sheets.insert(at, m);
    if (content != null) _place(content, at * kSheetStep);
    return m;
  }

  /// Copia la hoja [i] justo después de ella (con ids nuevos). Devuelve la hoja nueva.
  SheetMeta duplicateSheet(int i) {
    final src = sheets[i];
    final copy = _contentOf(i, fresh: true);
    return insertSheet(i + 1,
        meta: src.copy(id: newId('h'), title: src.title.isEmpty ? '' : '${src.title} (copia)', bookmark: false),
        content: copy);
  }

  /// Borra la hoja [i] con todo lo que tiene; lo de abajo sube. No se puede borrar la última que queda.
  bool deleteSheet(int i) {
    if (sheets.length < 2 || i < 0 || i >= sheets.length) return false;
    strokes.removeWhere((_, s) => _sheetOfStroke(s) == i);
    texts.removeWhere((_, t) => sheetOfY(t.y) == i);
    items.removeWhere((_, it) => sheetOfY(it.y) == i);
    _shiftWhere((k) => k > i, -kSheetStep);
    sheets.removeAt(i);
    return true;
  }

  /// Lleva la hoja [from] a la posición [to] (las del medio se corren una).
  void moveSheet(int from, int to) {
    final n = sheets.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    // nueva posición de cada hoja vieja
    final order = List.generate(n, (i) => i)
      ..removeAt(from)
      ..insert(to, from);
    final newPos = List.filled(n, 0);
    for (var p = 0; p < n; p++) {
      newPos[order[p]] = p;
    }
    // el corrimiento depende de la hoja vieja de cada elemento: se calcula antes de tocar nada
    for (final s in strokes.values) {
      final k = _sheetOfStroke(s);
      s.translateY((newPos[k] - k) * kSheetStep);
    }
    for (final t in texts.values) {
      final k = sheetOfY(t.y);
      t.y += (newPos[k] - k) * kSheetStep;
    }
    for (final it in items.values) {
      final k = sheetOfY(it.y);
      it.y += (newPos[k] - k) * kSheetStep;
    }
    sheets.insert(to, sheets.removeAt(from));
  }

  // ================= hojas <-> documento =================
  /// Lo de la hoja [i] en coordenadas locales (copias; con ids nuevos si [fresh]).
  SheetContent _contentOf(int i, {bool fresh = false}) {
    final d = Offset(0, -i * kSheetStep);
    return SheetContent(
      strokes: [
        for (final s in strokes.values)
          if (_sheetOfStroke(s) == i) s.moved(d, id: fresh ? newId('s') : null)
      ],
      texts: [
        for (final t in texts.values)
          if (sheetOfY(t.y) == i) t.copy(id: fresh ? newId('t') : null, d: d)
      ],
      items: [
        for (final it in items.values)
          if (sheetOfY(it.y) == i) it.copy(id: fresh ? newId('i') : null, d: d)
      ],
    );
  }

  /// Parte el documento en el contenido de cada hoja, en coordenadas locales (copias).
  /// Cada elemento va a la hoja que contiene el borde de arriba de su rectángulo.
  /// Se recorre una sola vez, manteniendo el orden de inserción dentro de cada hoja.
  List<SheetContent> splitBySheet() {
    final out = List.generate(sheets.length, (_) => SheetContent());
    for (final s in strokes.values) {
      final k = _sheetOfStroke(s);
      out[k].strokes.add(s.moved(Offset(0, -k * kSheetStep)));
    }
    for (final t in texts.values) {
      final k = sheetOfY(t.y);
      out[k].texts.add(t.copy(d: Offset(0, -k * kSheetStep)));
    }
    for (final it in items.values) {
      final k = sheetOfY(it.y);
      out[k].items.add(it.copy(d: Offset(0, -k * kSheetStep)));
    }
    return out;
  }

  /// Arma el documento global del cuaderno [nb] con el contenido local de cada hoja
  /// (inverso de [splitBySheet]). [sheets] tiene que tener una entrada por hoja de [nb].
  factory NotebookDoc.fromSheets(Notebook nb, List<SheetContent> sheets) {
    assert(sheets.length == nb.sheets.length);
    final doc = NotebookDoc(nb);
    for (var k = 0; k < sheets.length; k++) {
      doc._place(sheets[k], k * kSheetStep);
    }
    return doc;
  }

  /// Agrega [c] (coordenadas locales) corrido [top] hacia abajo, sin copiar.
  void _place(SheetContent c, double top) {
    for (final s in c.strokes) {
      if (top != 0) s.translateY(top);
      strokes[s.id] = s;
    }
    for (final t in c.texts) {
      t.y += top;
      texts[t.id] = t;
    }
    for (final i in c.items) {
      i.y += top;
      items[i.id] = i;
    }
  }
}
