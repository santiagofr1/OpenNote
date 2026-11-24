import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../domain/domain.dart';
import 'paper.dart';
import 'stroke_painter.dart';
import 'text_layout.dart';

/// Dibuja la hoja [sheet] del cuaderno [doc], completa (papel, renglones, elementos, tinta y texto),
/// en coordenadas lógicas con origen en la esquina de esa hoja. Para miniaturas, PNG y PDF.
/// [region] (coordenadas del documento): si viene, dibuja ese rectángulo (papel liso y lo que lo toca) con origen en su
/// esquina, en vez de la hoja [sheet]. Es la página de un lienzo infinito al exportar.
/// Con [background] falso no hay fondo: sobre blanco, sin papel de color, patrón ni imagen de fondo.
void paintSheet(Canvas c, NotebookDoc doc, int sheet, double pxPerUnit,
    {Map<String, ui.Image>? images, Rect? region, bool background = true}) {
  final top = region?.top ?? sheet * kSheetStep;
  final meta = doc.sheets[region == null ? sheet : doc.sheetOfY(region.top)];
  final page = region == null ? const Rect.fromLTWH(0, 0, kW, kSheetH) : Rect.fromLTWH(0, 0, region.width, region.height);
  c.save();
  c.clipRect(page);
  c.drawRect(page, Paint()..color = background ? parseColor(meta.paper) : const Color(0xFFFFFFFF));
  if (!background || region != null) {
    // sin fondo, o lienzo: papel liso, sin patrón
  } else if (meta.bg == 'image') {
    // fondo de imagen: entra completa en la hoja, sin patrón
    final img = meta.image == null ? null : images?[bgImageKey(meta.image!)];
    if (img != null) {
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          containRect(img.width.toDouble(), img.height.toDouble()), Paint()..filterQuality = FilterQuality.medium);
    }
  } else {
    // en miniaturas chicas las líneas no pueden ser más finas que esto o desaparecen
    paintPaperPattern(c, meta.bg, meta.spacing, size: meta.size, ruleWidth: max(.6, 1 / pxPerUnit), marginWidth: max(.8, 1.2 / pxPerUnit));
  }
  c.translate(-(region?.left ?? 0), -top);
  final visible = region ?? Rect.fromLTWH(0, top, kW, kSheetH);
  // un solo orden de dibujo para todo; de cada tanda de trazos seguidos, los resaltadores van primero
  for (final run in zRuns(doc.drawOrder())) {
    final e = run.single;
    if (run.strokes != null) {
      paintStrokes(c, run.strokes!, cull: visible);
    } else if (e is Item) {
      if (e.rect.overlaps(visible)) paintItem(c, e, images?[e.type == 'pdf' ? pdfImageKey(e) : e.file]);
    } else if (e is TextBlock) {
      final t = e;
      // kLine * 40: tope generoso del alto de un texto, para no medirlos todos
      if (t.text.trim().isEmpty || t.y > visible.bottom || t.y + kLine * 40 * t.scale + (t.angle == 0 ? 0 : kLine * 40 * t.scale) < top) continue;
      if (region != null && t.x > region.right) continue;
      paintTextBlock(c, t, doc.lineAt(t.y));
    }
  }
  c.restore();
}

/// Clave, en el mapa de imágenes de [paintSheet], del fondo de imagen [file].
String bgImageKey(String file) => 'bg:$file';

/// Rectángulo donde entra una imagen de [imgW] x [imgH] completa en la hoja (0, 0, kW, kSheetH), centrada y sin deformar.
Rect containRect(double imgW, double imgH) {
  final k = min(kW / imgW, kSheetH / imgH), w = imgW * k, h = imgH * k;
  return Rect.fromLTWH((kW - w) / 2, (kSheetH - h) / 2, w, h);
}

/// Miniatura de la hoja [sheet] (por defecto la primera)
class SheetThumbPainter extends CustomPainter {
  final NotebookDoc doc;
  final int sheet;
  final int version; // cambia cuando se edita el cuaderno abierto
  final Map<String, ui.Image>? images; // imágenes y páginas de PDF ya cargadas (como en [paintSheet])
  SheetThumbPainter(this.doc, {this.sheet = 0, this.version = 0, this.images});
  @override
  void paint(Canvas c, Size size) {
    final k = size.width / kW;
    c.scale(k);
    if (sheet < doc.sheetCount) paintSheet(c, doc, sheet, k, images: images);
  }

  @override
  bool shouldRepaint(SheetThumbPainter o) => o.doc != doc || o.sheet != sheet || o.version != version || o.images != images;
}

const _stickyText = Color(0xFF2B2A27);

/// Clave, en el mapa de imágenes de [paintSheet], de la página de PDF de [it].
String pdfImageKey(Item it) => '${it.file}#${it.page}';

/// Elemento insertado (para miniaturas y PDF; en el editor son widgets). Un 'link' no dibuja nada (es solo una zona).
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
    case 'pdf':
      if (img != null) {
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r,
            Paint()..filterQuality = FilterQuality.medium);
      } else {
        c.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
        c.drawRect(r.deflate(.5), Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x22000000));
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
        text: TextSpan(text: '${it.text.isEmpty ? 'Audio' : it.text} ${fmtDuration(it.dur)}', style: const TextStyle(fontSize: 20, color: _stickyText)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(r.left + r.height + 6, r.center.dy - tp.height / 2));
  }
}
