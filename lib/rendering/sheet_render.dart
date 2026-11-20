import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../domain/domain.dart';
import 'paper.dart';
import 'stroke_painter.dart';
import 'text_layout.dart';

/// Dibuja la hoja [sheet] del cuaderno [doc], completa (papel, renglones, elementos, tinta y texto),
/// en coordenadas lógicas con origen en la esquina de esa hoja. Para miniaturas, PNG y PDF.
void paintSheet(Canvas c, NotebookDoc doc, int sheet, double pxPerUnit, {Map<String, ui.Image>? images}) {
  final top = sheet * kSheetStep;
  final meta = doc.sheets[sheet];
  c.save();
  c.clipRect(const Rect.fromLTWH(0, 0, kW, kSheetH));
  c.drawRect(const Rect.fromLTWH(0, 0, kW, kSheetH), Paint()..color = parseColor(meta.paper));
  // en miniaturas chicas las líneas no pueden ser más finas que esto o desaparecen
  paintPaperPattern(c, meta.bg, meta.spacing, ruleWidth: max(.6, 1 / pxPerUnit), marginWidth: max(.8, 1.2 / pxPerUnit));
  c.translate(0, -top);
  final visible = Rect.fromLTWH(0, top, kW, kSheetH);
  for (final it in doc.items.values) {
    if (it.rect.overlaps(visible)) paintItem(c, it, images?[it.file]);
  }
  paintStrokes(c, doc.strokes.values.where((s) => s.bounds.overlaps(visible)).toList());
  for (final t in doc.texts.values) {
    // kLine * 40: tope generoso del alto de un texto, para no medirlos todos
    if (t.text.trim().isEmpty || t.y > top + kSheetH || t.y + kLine * 40 < top) continue;
    final line = doc.lineAt(t.y);
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: textStyle(line, color: kInk)),
      strutStyle: textStrut(line),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: t.w);
    tp.paint(c, Offset(t.x, t.y));
  }
  c.restore();
}

/// Miniatura de la hoja [sheet] (por defecto la primera)
class SheetThumbPainter extends CustomPainter {
  final NotebookDoc doc;
  final int sheet;
  final int version; // cambia cuando se edita el cuaderno abierto
  SheetThumbPainter(this.doc, {this.sheet = 0, this.version = 0});
  @override
  void paint(Canvas c, Size size) {
    final k = size.width / kW;
    c.scale(k);
    if (sheet < doc.sheetCount) paintSheet(c, doc, sheet, k);
  }

  @override
  bool shouldRepaint(SheetThumbPainter o) => o.doc != doc || o.sheet != sheet || o.version != version;
}

const _stickyText = Color(0xFF2B2A27);

/// Elemento insertado (para miniaturas y PDF; en el editor son widgets).
void paintItem(Canvas c, Item it, ui.Image? img) {
  final r = it.rect;
  switch (it.type) {
    case 'image':
      if (img != null) {
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r,
            Paint()..filterQuality = FilterQuality.medium);
      } else {
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = const Color(0xFFE6E3DA));
      }
    case 'sticky':
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
      c.drawRRect(
          rr.shift(const Offset(0, 3)),
          Paint()
            ..color = const Color(0x22000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      c.drawRRect(rr, Paint()..color = parseColor(it.color));
      final tp = TextPainter(
        text: TextSpan(text: it.text, style: const TextStyle(fontSize: 20, height: 1.35, color: _stickyText)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width - 32);
      c.save();
      c.clipRRect(rr);
      tp.paint(c, r.topLeft + const Offset(16, 14));
      c.restore();
    case 'audio':
      final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
      c.drawRRect(rr, Paint()..color = const Color(0xFFE9E6F5));
      c.drawCircle(Offset(r.left + r.height / 2, r.center.dy), r.height * .3, Paint()..color = const Color(0xFF5B4FC4));
      final tp = TextPainter(
        text: TextSpan(text: 'Audio ${fmtDuration(it.dur)}', style: const TextStyle(fontSize: 20, color: _stickyText)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(r.left + r.height + 6, r.center.dy - tp.height / 2));
  }
}
