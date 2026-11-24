import 'dart:ui';

import 'elements.dart';
import 'geometry.dart';
import 'notebook.dart';
import 'notebook_doc.dart';
import 'values.dart';

/// Un título del índice: marca elementos de una hoja (trazos, textos o elementos, por id).
class Heading {
  final String id;
  int level; // 1, 2, 3... (libre; el índice lo normaliza para que no haya saltos)
  String title;
  double y; // borde de arriba de lo marcado, LOCAL a la hoja (0 = arriba de la hoja)
  List<String> ids; // elementos marcados
  bool hidden; // lo marcado no está en la hoja (se borró): no aparece en el índice, pero vuelve si reaparece (deshacer)
  Rect? box; // zona marcada (ej. un renglón de una página de PDF), RELATIVA a la esquina (x, y) del elemento ancla
  Heading(this.id, {this.level = 1, this.title = '', this.y = 0, List<String>? ids, this.hidden = false, this.box}) : ids = ids ?? [];

  Heading copy() => Heading(id, level: level, title: title, y: y, ids: List.of(ids), hidden: hidden, box: box);

  factory Heading.fromJson(Map j) => Heading(
        (j['id'] ?? newId('h')) as String,
        level: ((j['l'] ?? 1) as num).toInt().clamp(1, 99),
        title: (j['t'] ?? '') as String,
        y: jsonDouble(j['y']),
        ids: [for (final e in (j['ids'] as List? ?? const [])) e as String],
        hidden: (j['x'] ?? false) as bool,
        box: _boxFrom(j['b']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'l': level,
        't': title,
        'y': round1(y),
        'ids': ids,
        if (hidden) 'x': true,
        if (box != null) 'b': [round1(box!.left), round1(box!.top), round1(box!.width), round1(box!.height)],
      };

  static Rect? _boxFrom(Object? b) {
    if (b is! List || b.length < 4 || b.any((e) => e is! num)) return null;
    return Rect.fromLTWH(jsonDouble(b[0]), jsonDouble(b[1]), jsonDouble(b[2]), jsonDouble(b[3]));
  }
}

/// Una línea del índice del cuaderno.
class OutlineEntry {
  final String sectionId, headingId, sheetId;
  final int sheet; // índice de la hoja dentro de su sección
  final double y; // local a la hoja
  final int level; // ya normalizado
  final String number; // '1', '1.2', '2.1.3'
  final String title;
  const OutlineEntry(
      {required this.sectionId,
      required this.headingId,
      required this.sheetId,
      required this.sheet,
      required this.y,
      required this.level,
      required this.number,
      required this.title});
}

/// El índice de todo el cuaderno: por sección, sus hojas en orden y en cada una sus títulos (los no ocultos) por altura.
/// La numeración reinicia en cada sección. Un nivel nunca salta más de uno respecto del anterior ("1" -> "1.1").
List<OutlineEntry> buildOutline(Notebook nb) {
  final out = <OutlineEntry>[];
  for (final sec in nb.sections) {
    final counters = <int>[];
    var prev = 0;
    final sheets = nb.sheetsOf(sec.id);
    for (var k = 0; k < sheets.length; k++) {
      final m = sheets[k];
      final hs = [for (final h in m.heads) if (!h.hidden) h];
      final order = {for (var i = 0; i < hs.length; i++) hs[i]: i};
      hs.sort((a, b) {
        final c = a.y.compareTo(b.y);
        return c != 0 ? c : order[a]!.compareTo(order[b]!);
      });
      for (final h in hs) {
        final level = h.level.clamp(1, prev + 1);
        while (counters.length > level) {
          counters.removeLast();
        }
        while (counters.length < level) {
          counters.add(0);
        }
        counters[level - 1]++;
        prev = level;
        out.add(OutlineEntry(
            sectionId: sec.id,
            headingId: h.id,
            sheetId: m.id,
            sheet: k,
            y: h.y,
            level: level,
            number: counters.join('.'),
            title: h.title));
      }
    }
  }
  return out;
}

/// Pone al día los títulos de las hojas cargadas con lo que hay en memoria: busca sus elementos por id. Sin ninguno,
/// el título queda oculto (vuelve si reaparecen, ej. al deshacer); si no, se corrige su altura y, si lo marcado pasó a otra
/// hoja cargada, el título se muda a ella. Sube `updated` de las hojas tocadas. Devuelve si algo cambió.
bool syncHeadings(NotebookDoc doc) {
  var changed = false;
  final now = DateTime.now().millisecondsSinceEpoch;
  final sheets = doc.sheets;
  for (var k = 0; k < sheets.length; k++) {
    final m = sheets[k];
    if (m.heads.isEmpty || !doc.isLoaded(m.id)) continue;
    for (final h in List.of(m.heads)) {
      double? top;
      final box = h.box;
      for (final id in h.ids) {
        final double? t = box != null && doc.items[id] != null
            ? doc.items[id]!.y + box.top
            : doc.strokes[id]?.bounds.top ?? doc.texts[id]?.y ?? doc.items[id]?.y;
        if (t != null && (top == null || t < top)) top = t;
      }
      if (top == null) {
        if (!h.hidden) {
          h.hidden = true;
          m.updated = now;
          changed = true;
        }
        continue;
      }
      final to = doc.sheetOfY(top);
      final local = top - to * kSheetStep;
      if (to != k && doc.isLoadedAt(to)) {
        m.heads.remove(h);
        h
          ..hidden = false
          ..y = local;
        sheets[to].heads.add(h);
        m.updated = sheets[to].updated = now;
        changed = true;
      } else if (to == k && (h.hidden || (h.y - local).abs() > .05)) {
        h
          ..hidden = false
          ..y = local;
        m.updated = now;
        changed = true;
      }
    }
  }
  return changed;
}

/// Rectángulo (global) de lo marcado por [h] que está en memoria, o null si no hay nada.
/// [textBox] da el rectángulo de un texto (depende del renglón de su hoja).
Rect? headingBounds(NotebookDoc doc, Heading h, Rect Function(TextBlock) textBox) => unionRects([
      for (final id in h.ids) ...[
        if (doc.strokes[id] case final s?) s.bounds,
        if (doc.texts[id] case final t?) textBox(t),
        if (doc.items[id] case final it?) h.box?.shift(Offset(it.x, it.y)) ?? it.rect,
      ]
    ]);
