// Driver de las capturas: guarda cada imagen que manda screenshots_test.dart en docs/img/<nombre>.png,
// sin la franja negra de abajo (la barra de navegación de Android).
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test_driver_extended.dart';

/// Saca las filas casi negras del final. Si no hay (o no se puede decodificar), deja la imagen igual.
List<int> cropBottomBar(List<int> bytes) {
  final im = img.decodePng(Uint8List.fromList(bytes));
  if (im == null) return bytes;
  bool dark(int y) {
    for (var x = 0; x < im.width; x += 4) {
      final p = im.getPixel(x, y);
      if (p.luminance > 40) return false;
    }
    return true;
  }

  var h = im.height;
  while (h > 1 && dark(h - 1)) {
    h--;
  }
  if (h == im.height) return bytes;
  return img.encodePng(img.copyCrop(im, x: 0, y: 0, width: im.width, height: h));
}

Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        File('docs/img/$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(cropBottomBar(bytes));
        return true;
      },
    );
