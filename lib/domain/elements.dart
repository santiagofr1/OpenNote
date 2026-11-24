import 'dart:ui';

import 'rich_text.dart';
import 'values.dart';
import 'z_order.dart';

/// Bloque de texto escrito con teclado: párrafos con formato ([RichBody]). [y] queda 4 por debajo del renglón.
class TextBlock extends Layered {
  @override
  final String id;
  double x, y, w;
  RichBody body;

  /// Escala (multiplica letra y ancho, desde la esquina de arriba a la izquierda) y giro en radianes (alrededor del centro del
  /// rectángulo ya escalado). Con 1 y 0 el texto se acomoda al renglón como siempre; con otra cosa queda libre donde se lo dejó.
  double scale, angle;
  TextBlock(this.id, this.x, this.y, this.w, String text, {RichBody? body, this.scale = 1, this.angle = 0})
      : body = body ?? RichBody.plain(text);

  /// Tiene escala o giro (ya no se acomoda al renglón).
  bool get transformed => scale != 1 || angle != 0;

  /// Texto sin formato (búsqueda, portapapeles). Al asignarlo se pierde el formato.
  String get text => body.plainText;
  set text(String v) => body = RichBody.plain(v);

  TextBlock copy({String? id, Offset d = Offset.zero}) =>
      TextBlock(id ?? this.id, x + d.dx, y + d.dy, w, '', body: body, scale: scale, angle: angle)..z = z;

  /// Los textos viejos traen solo `text`: se leen como párrafos normales (uno por línea).
  factory TextBlock.fromJson(Map j) => TextBlock(
      j['id'] as String, jsonDouble(j['x']), jsonDouble(j['y']), jsonDouble(j['w'], 800), (j['text'] ?? '') as String,
      body: j['rich'] is List ? RichBody.fromJson(j['rich'] as List) : null,
      scale: jsonDouble(j['s'], 1),
      angle: jsonDouble(j['a']))
        ..z = (j['z'] as num? ?? 0).toInt();

  /// Sin formato se guarda igual que antes (solo `text`); con formato, `rich` y además `text` como respaldo.
  Map<String, dynamic> toJson() =>
      {'id': id, 'x': x, 'y': y, 'w': w, 'text': text, if (!body.isPlain) 'rich': body.toJson(), if (scale != 1) 's': scale, if (angle != 0) 'a': angle};
}

/// Elemento insertado en una hoja: imagen, nota adhesiva, audio, página de PDF o zona de link.
class Item extends Layered {
  @override
  final String id;
  final String type; // image | sticky | audio | pdf | link
  double x, y, w, h;
  String? file; // nombre del archivo en media/ (imagen, audio o PDF)
  String text; // nota adhesiva; en un link, el destino (ver links.dart)
  String color; // nota adhesiva
  int dur; // audio, en ms
  int page; // pdf: índice (desde 0) de la página del PDF `file`
  Item(this.id, this.type, this.x, this.y, this.w, this.h,
      {this.file, this.text = '', this.color = '#fde68a', this.dur = 0, this.page = 0});

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  Item copy({String? id, Offset d = Offset.zero}) =>
      Item(id ?? this.id, type, x + d.dx, y + d.dy, w, h, file: file, text: text, color: color, dur: dur, page: page)..z = z;

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
        page: (j['pg'] ?? 0) as int,
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
        if (type == 'pdf') 'pg': page,
      };
}

