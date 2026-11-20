import 'dart:ui';

import 'values.dart';
import 'z_order.dart';

/// Bloque de texto escrito con teclado. [y] queda 4 por debajo del renglón.
class TextBlock extends Layered {
  @override
  final String id;
  double x, y, w;
  String text;
  TextBlock(this.id, this.x, this.y, this.w, this.text);

  TextBlock copy({String? id, Offset d = Offset.zero}) =>
      TextBlock(id ?? this.id, x + d.dx, y + d.dy, w, text)..z = z;

  factory TextBlock.fromJson(Map j) => TextBlock(
      j['id'] as String, jsonDouble(j['x']), jsonDouble(j['y']), jsonDouble(j['w'], 800), (j['text'] ?? '') as String)
        ..z = (j['z'] as num? ?? 0).toInt();
  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y, 'w': w, 'text': text};
}

/// Elemento insertado en una hoja: imagen, nota adhesiva o audio.
class Item extends Layered {
  @override
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
      Item(id ?? this.id, type, x + d.dx, y + d.dy, w, h, file: file, text: text, color: color, dur: dur)..z = z;

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
      )..z = (j['z'] as num? ?? 0).toInt();
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

