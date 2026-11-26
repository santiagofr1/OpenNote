import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;

/// Lectura de los píxeles de una imagen ya dibujada (RGBA sin premultiplicar). Es una variable para que los tests (y las
/// pruebas en la tablet) la reemplacen y simulen un motor que devuelve basura.
@visibleForTesting
Future<ByteData?> Function(ui.Image img) rasterReader = (img) => img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);

/// Dibuja [pic] en una imagen de [w] x [h]. También reemplazable (ver [rasterReader]).
@visibleForTesting
Future<ui.Image> Function(ui.Picture pic, int w, int h) rasterToImage = (pic, w, h) => pic.toImage(w, h);

/// Cuántas lecturas seguidas IGUALES hacen falta para dar una por buena (1 = como antes: se cree la primera).
/// En Android con Impeller/Vulkan (Flutter 3.50, regresión flutter/flutter#196627 y #196980) `toByteData` justo después de
/// `Picture.toImage` a veces devuelve la imagen ANTERIOR, píxeles transparentes o a medio dibujar; una segunda lectura de la
/// misma imagen sale bien. Por eso se lee hasta que dos lecturas seguidas coinciden (y la hoja, que es opaca, no tiene huecos).
int rasterStableReads = 2;

/// Lecturas máximas de una misma imagen antes de volver a dibujarla, y dibujados máximos antes de rendirse.
const _maxReads = 6, _maxRenders = 3;

/// Espera entre lecturas distintas (le da tiempo a la GPU de terminar).
Duration rasterRetryPause = const Duration(milliseconds: 20);

/// Veces que hizo falta repetir una lectura o un dibujado (para diagnóstico y tests).
@visibleForTesting
int rasterRetries = 0;

bool _same(Uint8List a, Uint8List b) {
  if (a.lengthInBytes != b.lengthInBytes) return false;
  final n8 = a.lengthInBytes ~/ 8;
  final x = a.buffer.asUint64List(a.offsetInBytes, n8), y = b.buffer.asUint64List(b.offsetInBytes, n8);
  for (var i = 0; i < n8; i++) {
    if (x[i] != y[i]) return false;
  }
  for (var i = n8 * 8; i < a.lengthInBytes; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// la hoja siempre se pinta sobre un papel opaco: un píxel con alfa < 255 es una lectura a medias (el borde de abajo y
// de la derecha puede quedar a medio cubrir por el redondeo del tamaño: no se mira)
bool _opaque(Uint8List rgba, int w, int h) {
  for (var y = 0; y < h - 2; y++) {
    for (var x = 0, i = (y * w) * 4 + 3; x < w - 2; x++, i += 4) {
      if (rgba[i] != 255) return false;
    }
  }
  return true;
}

/// Dibuja [pic] y devuelve sus píxeles RGBA (de una hoja opaca), leyéndolos hasta que dos lecturas seguidas coinciden.
/// Lanza si después de [_maxRenders] dibujados no se logra una lectura estable.
Future<Uint8List> rasterizeStable(ui.Picture pic, int w, int h) async {
  try {
    for (var r = 0; r < _maxRenders; r++) {
      final img = await rasterToImage(pic, w, h);
      try {
        Uint8List? prev;
        var streak = 1;
        for (var i = 0; i < _maxReads; i++) {
          final d = await rasterReader(img);
          Uint8List? cur;
          if (d != null) cur = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
          if (cur != null && cur.lengthInBytes == w * h * 4 && _opaque(cur, w, h)) {
            streak = prev != null && _same(prev, cur) ? streak + 1 : 1;
            prev = cur;
            if (streak >= rasterStableReads) return cur;
          } else {
            prev = null;
            streak = 1;
          }
          rasterRetries++;
          await Future<void>.delayed(rasterRetryPause);
        }
      } finally {
        img.dispose();
      }
    }
  } finally {
    pic.dispose();
  }
  throw StateError('no se pudo leer la hoja dibujada: el motor gráfico devolvió datos inestables');
}

/// PNG (RGB, sin alfa: la hoja es opaca) de píxeles RGBA de [w] x [h]. Se arma en otro isolate.
Future<Uint8List> opaquePng(Uint8List rgba, int w, int h) => Isolate.run(() {
      final rgb = Uint8List(w * h * 3);
      for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
        rgb[j] = rgba[i];
        rgb[j + 1] = rgba[i + 1];
        rgb[j + 2] = rgba[i + 2];
      }
      final image = im.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);
      return Uint8List.fromList(im.PngEncoder(level: 3).encode(image));
    });
