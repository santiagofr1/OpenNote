import 'dart:ui';

import 'rich_text.dart';
import 'values.dart';

/// Bloque de texto escrito con teclado: párrafos con formato ([RichBody]). [y] queda 4 por debajo del renglón.
class TextBlock {
  final String id;
  double x, y, w;
  RichBody body;
  TextBlock(this.id, this.x, this.y, this.w, String text, {RichBody? body}) : body = body ?? RichBody.plain(text);

  /// Texto sin formato (búsqueda, portapapeles). Al asignarlo se pierde el formato.
  String get text => body.plainText;
  set text(String v) => body = RichBody.plain(v);

  TextBlock copy({String? id, Offset d = Offset.zero}) => TextBlock(id ?? this.id, x + d.dx, y + d.dy, w, '', body: body);

  /// Los textos viejos traen solo `text`: se leen como párrafos normales (uno por línea).
  factory TextBlock.fromJson(Map j) => TextBlock(
      j['id'] as String, jsonDouble(j['x']), jsonDouble(j['y']), jsonDouble(j['w'], 800), (j['text'] ?? '') as String,
      body: j['rich'] is List ? RichBody.fromJson(j['rich'] as List) : null);

  /// Sin formato se guarda igual que antes (solo `text`); con formato, `rich` y además `text` como respaldo.
  Map<String, dynamic> toJson() =>
      {'id': id, 'x': x, 'y': y, 'w': w, 'text': text, if (!body.isPlain) 'rich': body.toJson()};
}

/// Elemento insertado en una hoja: imagen, nota adhesiva o audio.
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

