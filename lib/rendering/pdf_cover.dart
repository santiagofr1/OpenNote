import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import '../domain/domain.dart';
import 'pdf_pages.dart';

/// Color (ARGB opaco) del fondo alrededor de (cx, cy), en píxeles de la imagen RGBA de [width] x [height]: mira el
/// anillo de radio entre [r] y 1.5 * [r] (lo que cae fuera de la imagen se saltea), cuantiza cada canal a 16 niveles
/// y devuelve el promedio real de los píxeles de la cubeta más frecuente. Sin píxeles: blanco.
int coverColorFromRgba(Uint8List rgba, int width, int height, double cx, double cy, double r) {
  final counts = List<int>.filled(4096, 0), sums = List<int>.filled(4096 * 3, 0);
  final outer = r * 1.5;
  final x0 = max(0, (cx - outer).floor()), x1 = min(width - 1, (cx + outer).ceil());
  final y0 = max(0, (cy - outer).floor()), y1 = min(height - 1, (cy + outer).ceil());
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final d = sqrt((x + .5 - cx) * (x + .5 - cx) + (y + .5 - cy) * (y + .5 - cy));
      if (d < r || d > outer) continue;
      final i = (y * width + x) * 4;
      final R = rgba[i], G = rgba[i + 1], B = rgba[i + 2];
      final k = (R >> 4) << 8 | (G >> 4) << 4 | (B >> 4);
      counts[k]++;
      sums[k * 3] += R;
      sums[k * 3 + 1] += G;
      sums[k * 3 + 2] += B;
    }
  }
  var best = -1;
  for (var k = 0; k < 4096; k++) {
    if (counts[k] > 0 && (best < 0 || counts[k] > counts[best])) best = k;
  }
  if (best < 0) return 0xFFFFFFFF;
  final n = counts[best];
  int avg(int c) => (sums[best * 3 + c] / n).round();
  return 0xFF000000 | avg(0) << 16 | avg(1) << 8 | avg(2);
}

/// Color del fondo de la página de [pdf] alrededor de [p] (coordenadas del documento) para un corrector de radio [r].
/// [mediaPath] es el archivo del PDF. Ante cualquier error: blanco.
Future<int> coverColorAt(Item pdf, Offset p, double r, String mediaPath) async {
  Image? img;
  try {
    img = await pdfPages.page(File(mediaPath), pdf.page, 512);
    if (img == null) return 0xFFFFFFFF;
    final data = await img.toByteData(format: ImageByteFormat.rawRgba);
    if (data == null) return 0xFFFFFFFF;
    final scale = img.width / pdf.w;
    return coverColorFromRgba(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), img.width, img.height,
        (p.dx - pdf.x) * scale, (p.dy - pdf.y) * scale, r * scale);
  } catch (_) {
    return 0xFFFFFFFF;
  } finally {
    img?.dispose();
  }
}

/// Cómo se calcula el color del corrector (los tests lo reemplazan para no abrir un PDF de verdad).
Future<int> Function(Item pdf, Offset p, double r, String mediaPath) pdfCoverColor = coverColorAt;
