import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/domain.dart';
import '../rendering/paper.dart';

/// Vista previa de una hoja con su papel y su fondo (mismo dibujo que las miniaturas y el PDF).
class PaperPreview extends StatelessWidget {
  final String bg, paper;
  final String size;
  final double spacing, width;
  final File? image; // fondo de imagen (con bg == 'image')
  const PaperPreview(
      {super.key,
      required this.bg,
      required this.paper,
      required this.spacing,
      this.size = 'a4',
      this.width = 150,
      this.image});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), boxShadow: const [
        BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
      ]),
      child: Stack(children: [
        CustomPaint(
          key: const Key('stylePreview'),
          size: Size(width, width * kSheetH / kW),
          painter: _PreviewPainter(bg, paper, spacing, size),
        ),
        if (bg == 'image' && image != null)
          Positioned.fill(
            child: Image.file(image!,
                fit: BoxFit.contain, cacheWidth: 400, errorBuilder: (_, _, _) => const SizedBox()),
          ),
      ]),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final String bg, paper, paperSize;
  final double spacing;
  _PreviewPainter(this.bg, this.paper, this.spacing, this.paperSize);

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / kW;
    c.scale(k);
    c.drawRect(const Rect.fromLTWH(0, 0, kW, kSheetH), Paint()..color = parseColor(paper));
    if (bg == 'image') return;
    paintPaperPattern(c, bg, spacing, size: paperSize, ruleWidth: max(.6, 1 / k), marginWidth: max(.8, 1.2 / k));
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.bg != bg || o.paper != paper || o.spacing != spacing || o.paperSize != paperSize;
}
