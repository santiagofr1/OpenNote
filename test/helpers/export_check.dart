import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/domain/domain.dart';
import 'package:image/image.dart' as im;

/// Marcas para comprobar de dónde sale cada página de un export: cada hoja lleva un trazo grueso de un color único en
/// un lugar único. Si la página i del PDF (o el PNG i) no tiene la marca de la hoja i, o tiene la de otra, se exportó mal.
class Marks {
  /// Color de la marca [m] (distintos entre sí y lejos del papel y de las líneas de los fondos).
  static (int, int, int) rgb(int m) => ((m * 53 + 40) % 200, (m * 97 + 80) % 200, (m * 149 + 20) % 200);

  static String hex(int m) {
    final (r, g, b) = rgb(m);
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${h(r)}${h(g)}${h(b)}';
  }

  /// Centro de la marca [m] en unidades de la hoja (x, y locales).
  static (double, double) pos(int m) => (160.0 + (m % 6) * 130, 200.0 + ((m ~/ 6) % 8) * 130);

  /// El trazo de la marca [m] en la hoja que empieza en [top] (coordenada global).
  static Stroke stroke(String id, int m, double top) {
    final (x, y) = pos(m);
    return Stroke(id, 'pen', hex(m), 40, [x - 30, top + y, .5, x - 10, top + y, .5, x + 10, top + y, .5, x + 30, top + y, .5]);
  }

  /// Agrega la marca [m] en la hoja [sheet] de [doc].
  static void add(NotebookDoc doc, int sheet, int m, {String? id}) {
    final s = stroke(id ?? 'mk$m-$sheet-${doc.strokes.length}', m, sheet * kSheetStep)..z = doc.nextZ();
    doc.strokes[s.id] = s;
    doc.markDirtyElement(s);
  }

  /// ¿La imagen [page] (una hoja) tiene la marca [m]?
  static bool has(im.Image page, int m) {
    final (x, y) = pos(m);
    final k = page.width / kW;
    final p = page.getPixel((x * k).round(), (y * k).round());
    final (r, g, b) = rgb(m);
    return (p.r - r).abs() < 10 && (p.g - g).abs() < 10 && (p.b - b).abs() < 10;
  }

  /// Los números de marca (de [candidates]) que tiene la página.
  static List<int> found(im.Image page, Iterable<int> candidates) => [for (final m in candidates) if (has(page, m)) m];
}

/// ¿Está `pdfimages` (poppler)? Sin eso los tests que miran las imágenes del PDF se saltean.
bool get hasPdfImages => Process.runSync('which', ['pdfimages']).exitCode == 0;

/// Las imágenes de cada página del PDF [pdf], en orden de página (una por página: las hojas son una imagen a página).
Future<List<im.Image>> pdfPageImages(Uint8List pdf) async {
  final d = await Directory.systemTemp.createTemp('pdfimgs');
  try {
    await File('${d.path}/a.pdf').writeAsBytes(pdf);
    final r = await Process.run('pdfimages', ['-png', '${d.path}/a.pdf', '${d.path}/p']);
    if (r.exitCode != 0) throw StateError('pdfimages falló: ${r.stderr}');
    // el PDF puede traer, además de la imagen de cada página, una máscara de transparencia (smask): se saltea
    final list = await Process.run('pdfimages', ['-list', '${d.path}/a.pdf']);
    final out = <im.Image>[];
    var n = 0;
    for (final line in (list.stdout as String).split('\n').skip(2)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      if (parts[2] == 'image') {
        out.add(im.decodePng(await File('${d.path}/p-${n.toString().padLeft(3, '0')}.png').readAsBytes())!);
      }
      n++;
    }
    return out;
  } finally {
    await d.delete(recursive: true);
  }
}

/// Cantidad de páginas del PDF.
int pdfPageCount(Uint8List pdf) => RegExp(r'/Type\s*/Page\b(?!s)').allMatches(String.fromCharCodes(pdf)).length;

/// Los `/MediaBox` de las páginas, en orden: (ancho, alto) en puntos.
List<(double, double)> pdfMediaBoxes(Uint8List pdf) => [
      for (final m in RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').allMatches(String.fromCharCodes(pdf)))
        (double.parse(m.group(1)!), double.parse(m.group(2)!))
    ];
