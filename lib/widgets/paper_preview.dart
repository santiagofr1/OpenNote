import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/domain.dart';
import '../rendering/paper.dart';

/// Vista previa de una hoja A4 con su papel y su fondo (mismo dibujo que las miniaturas y el PDF).
class PaperPreview extends StatelessWidget {
  final String bg, paper;
  final double spacing, width;
  const PaperPreview({super.key, required this.bg, required this.paper, required this.spacing, this.width = 150});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), boxShadow: const [
        BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
      ]),
      child: CustomPaint(
        key: const Key('stylePreview'),
        size: Size(width, width * kSheetH / kW),
        painter: _PreviewPainter(bg, paper, spacing),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final String bg, paper;
  final double spacing;
  _PreviewPainter(this.bg, this.paper, this.spacing);

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / kW;
    c.scale(k);
    c.drawRect(const Rect.fromLTWH(0, 0, kW, kSheetH), Paint()..color = parseColor(paper));
    paintPaperPattern(c, bg, spacing, ruleWidth: max(.6, 1 / k), marginWidth: max(.8, 1.2 / k));
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.bg != bg || o.paper != paper || o.spacing != spacing;
}
