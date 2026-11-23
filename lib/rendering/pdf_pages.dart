import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Ancho en píxeles al que se pide una página de PDF para mostrarla [px] píxeles de ancho: se redondea hacia arriba a
/// múltiplos de 512 (así el zoom no pide un ancho nuevo en cada cuadro), entre 512 y 2560.
int pdfPixelWidth(double px) => ((px / 512).ceil() * 512).clamp(512, 2560);

/// Páginas de PDF a demanda: un PDF importado es UN archivo en media/ y cada hoja muestra una de sus páginas, que se
/// dibuja acá al ancho que haga falta (editor, miniaturas y exportación). Guarda unos pocos documentos abiertos y las
/// últimas páginas ya dibujadas (con un tope de memoria) para no repetir trabajo al scrollear.
class PdfPages {
  PdfPages({this.maxDocs = 3, this.maxImageBytes = 64 * 1024 * 1024});
  final int maxDocs, maxImageBytes;

  Future<void>? _init;
  final _docs = <String, Future<PdfDocument?>>{}; // (la más vieja primero)
  final _images = <String, ui.Image>{}; // idem
  final _flights = <String, Future<ui.Image?>>{};
  final _sizes = <String, List<ui.Size>>{};
  int _imageBytes = 0;

  Future<void> _ready() => _init ??= pdfrxFlutterInitialize();

  Future<PdfDocument?> _open(String path) {
    final hit = _docs.remove(path);
    if (hit != null) {
      _docs[path] = hit;
      return hit;
    }
    final fut = () async {
      try {
        await _ready();
        return await PdfDocument.openFile(path);
      } catch (e) {
        debugPrint('PdfPages: no se pudo abrir $path: $e');
        return null;
      }
    }();
    _docs[path] = fut;
    while (_docs.length > maxDocs) {
      final old = _docs.remove(_docs.keys.first)!;
      unawaited(old.then((d) => d?.dispose()));
    }
    return fut;
  }

  /// Tamaños (ancho, alto en puntos) de todas las páginas de [f]; vacía si no se pudo abrir.
  Future<List<ui.Size>> pageSizes(File f) async {
    final known = _sizes[f.path];
    if (known != null) return known;
    final d = await _open(f.path);
    if (d == null) return const [];
    try {
      final r = [for (final p in d.pages) ui.Size(p.width, p.height)];
      _sizes[f.path] = r;
      return r;
    } catch (e) {
      debugPrint('PdfPages: no se pudieron leer los tamaños de ${f.path}: $e');
      return const [];
    }
  }

  /// La página [page] (desde 0) de [f] dibujada a [pixelWidth] px de ancho; null si el archivo falta o está roto.
  /// Quien la pide recibe un clon y lo libera cuando termina (así la caché puede soltar la suya sin romper lo que se
  /// está dibujando). Dos pedidos iguales comparten el mismo vuelo.
  Future<ui.Image?> page(File f, int page, int pixelWidth) async {
    final key = '${f.path}#$page@$pixelWidth';
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit;
      return hit.clone();
    }
    final img = await (_flights[key] ??= _render(f.path, page, pixelWidth, key).whenComplete(() {
      _flights.remove(key); // (con llaves: devolver el Future del mapa haría que se espere a sí mismo)
    }));
    try {
      return img?.clone();
    } catch (_) {
      return null; // la caché la soltó justo antes de clonarla
    }
  }

  Future<ui.Image?> _render(String path, int page, int pixelWidth, String key) async {
    try {
      final d = await _open(path);
      if (d == null || page < 0 || page >= d.pages.length) return null;
      final p = d.pages[page];
      final w = pixelWidth, h = (pixelWidth * p.height / p.width).round().clamp(1, 1 << 14);
      final pdfImg = await p.render(fullWidth: w.toDouble(), fullHeight: h.toDouble());
      if (pdfImg == null) return null;
      try {
        final img = await pdfImg.createImage();
        _images[key] = img;
        _imageBytes += img.width * img.height * 4;
        while (_imageBytes > maxImageBytes && _images.length > 1) {
          final k = _images.keys.first;
          final old = _images.remove(k)!;
          _imageBytes -= old.width * old.height * 4;
          old.dispose();
        }
        return img;
      } finally {
        pdfImg.dispose();
      }
    } catch (e) {
      debugPrint('PdfPages: no se pudo dibujar $path página $page: $e');
      return null;
    }
  }

  /// Suelta lo abierto y dibujado de [path] (si se borró o cambió el archivo).
  void evictFile(String path) {
    final d = _docs.remove(path);
    if (d != null) unawaited(d.then((x) => x?.dispose()));
    _sizes.remove(path);
    for (final k in _images.keys.where((k) => k.startsWith('$path#')).toList()) {
      final img = _images.remove(k)!;
      _imageBytes -= img.width * img.height * 4;
      img.dispose();
    }
  }
}

final pdfPages = PdfPages();
