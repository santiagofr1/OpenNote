import 'dart:ui';

import 'geometry.dart';
import 'stroke.dart';
import 'values.dart';

/// Bloque de texto escrito con teclado. [y] queda 4 por debajo del renglón.
class TextBlock {
  final String id;
  double x, y, w;
  String text;
  TextBlock(this.id, this.x, this.y, this.w, this.text);

  TextBlock copy({String? id, Offset d = Offset.zero}) => TextBlock(id ?? this.id, x + d.dx, y + d.dy, w, text);

  factory TextBlock.fromJson(Map j) => TextBlock(
      j['id'] as String, jsonDouble(j['x']), jsonDouble(j['y']), jsonDouble(j['w'], 800), (j['text'] ?? '') as String);
  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y, 'w': w, 'text': text};
}

/// Elemento insertado en la página: imagen, nota adhesiva o audio.
class Item {
  final String id;
  final String type; // image | sticky | audio
  double x, y, w, h;
  String? file; // nombre del archivo en media/ (imagen o audio)
  String text; // nota adhesiva
  String color; // nota adhesiva
  int dur; // audio, en ms
  Item(this.id, this.type, this.x, this.y, this.w, this.h,
      {this.file, this.text = '', this.color = '#fde68a', this.dur = 0});

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  Item copy({String? id, Offset d = Offset.zero}) =>
      Item(id ?? this.id, type, x + d.dx, y + d.dy, w, h, file: file, text: text, color: color, dur: dur);

  factory Item.fromJson(Map j) => Item(
        j['id'] as String,
        j['type'] as String,
        jsonDouble(j['x']),
        jsonDouble(j['y']),
        jsonDouble(j['w'], 200),
        jsonDouble(j['h'], 200),
        file: j['file'] as String?,
        text: (j['text'] ?? '') as String,
        color: (j['color'] ?? '#fde68a') as String,
        dur: (j['dur'] ?? 0) as int,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (file != null) 'file': file,
        if (text.isNotEmpty) 'text': text,
        if (type == 'sticky') 'color': color,
        if (dur > 0) 'dur': dur,
      };
}

/// Una página: varias hojas apiladas (con espacio entre ellas) y su contenido.
class PageData {
  /// Versión del formato. 1: hojas pegadas; 2: con [kGap] entre hojas.
  static const layout = 2;

  final String id;
  int rev;
  double h;
  String bg; // lined | grid | dots | blank
  String paper; // color del papel
  int updated; // ms epoch, para sincronizar algún día
  final Map<String, Stroke> strokes; // mantiene orden de inserción
  final Map<String, TextBlock> texts;
  final Map<String, Item> items;

  PageData(this.id,
      {this.rev = 0,
      this.h = kSheetH,
      this.bg = 'lined',
      this.paper = '#fffefb',
      this.updated = 0,
      Map<String, Stroke>? strokes,
      Map<String, TextBlock>? texts,
      Map<String, Item>? items})
      : strokes = strokes ?? {},
        texts = texts ?? {},
        items = items ?? {};

  factory PageData.fromJson(Map j) {
    final p = PageData._fromJson(j);
    if (((j['layout'] ?? 1) as int) < 2) p._addGaps();
    return p;
  }

  /// Páginas viejas (hojas pegadas): corre todo para dejar el espacio entre hojas.
  void _addGaps() {
    double shift(double y) => y + (y ~/ kSheetH) * kGap;
    for (final s in strokes.values) {
      for (var i = 1; i < s.pts.length; i += 3) {
        s.pts[i] = shift(s.pts[i]);
      }
      s.invalidate();
    }
    for (final t in texts.values) {
      t.y = shift(t.y);
    }
    for (final i in items.values) {
      i.y = shift(i.y);
    }
    h = heightFor((h / kSheetH).ceil());
  }

  factory PageData._fromJson(Map j) => PageData(
        j['id'] as String,
        rev: (j['rev'] ?? 0) as int,
        h: jsonDouble(j['h'], kSheetH),
        bg: (j['bg'] ?? 'lined') as String,
        paper: (j['paper'] ?? '#fffefb') as String,
        updated: (j['updated'] ?? 0) as int,
        items: {for (final i in ((j['items'] ?? {}) as Map).values) (i['id'] as String): Item.fromJson(i as Map)},
        strokes: {for (final s in ((j['strokes'] ?? {}) as Map).values) (s['id'] as String): Stroke.fromJson(s as Map)},
        texts: {for (final t in ((j['texts'] ?? {}) as Map).values) (t['id'] as String): TextBlock.fromJson(t as Map)},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rev': rev,
        'h': h,
        'bg': bg,
        'paper': paper,
        'updated': updated,
        'items': {for (final i in items.values) i.id: i.toJson()},
        'layout': layout,
        'strokes': {for (final s in strokes.values) s.id: s.toJson()},
        'texts': {for (final t in texts.values) t.id: t.toJson()},
      };

  /// Copia completa con id nuevo (los trazos/textos/elementos conservan sus ids).
  PageData duplicate() => PageData.fromJson({...toJson(), 'id': newId('p')});

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;

  /// La última hoja no tiene nada: se puede quitar.
  bool get lastSheetEmpty {
    final top = (sheetCount(h) - 1) * kSheetStep;
    return !strokes.values.any((s) => s.bounds.bottom > top) &&
        !texts.values.any((t) => t.y + kLine > top) &&
        !items.values.any((i) => i.y + i.h > top);
  }

  /// Agrega (o quita, con [delta] negativo) hojas al final.
  void addSheets(int delta) => h = heightFor(sheetCount(h) + delta);
}
