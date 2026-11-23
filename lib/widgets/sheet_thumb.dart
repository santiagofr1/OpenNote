import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/export.dart';
import '../data/storage.dart';
import '../domain/domain.dart';
import '../rendering/sheet_render.dart';

/// Cómo se cargan las imágenes de una miniatura (reemplazable en los tests para no abrir PDFs de verdad).
Future<Map<String, ui.Image>> Function(Storage, NotebookDoc, int, double) thumbImagesLoader = loadThumbImages;

/// Miniatura de una hoja con sus imágenes y páginas de PDF: las pide al ancho que ocupa y mientras llegan dibuja la
/// hoja sin ellas. Vuelve a pedirlas si cambia el documento, la hoja, qué imágenes tiene la hoja o si hace falta
/// bastante más resolución; no con cada cambio de versión (cada trazo en la hoja abierta), que no toca las imágenes. Libera las imágenes que deja de usar.
class SheetThumb extends StatefulWidget {
  final NotebookDoc doc;
  final int sheet, version;
  final Storage store;
  const SheetThumb({super.key, required this.doc, this.sheet = 0, this.version = 0, required this.store});

  @override
  State<SheetThumb> createState() => _SheetThumbState();
}

class _SheetThumbState extends State<SheetThumb> {
  Map<String, ui.Image>? _images;
  int _gen = 0; // cuenta los pedidos: una carga que llega con otro número ya no sirve
  double _loadedPx = 0; // ancho (px) al que se pidió lo que hay
  String? _loadedKeys; // imágenes de la hoja que se pidieron
  Object? _loadedDoc;
  int _loadedSheet = -1;

  /// Claves de las imágenes y PDF de la hoja (ordenadas): si cambian hay que volver a pedir.
  String _keys() {
    final w = widget;
    if (w.sheet >= w.doc.sheetCount) return '';
    final r = Rect.fromLTWH(0, w.sheet * kSheetStep, kW, kSheetH);
    final ks = <String>[
      for (final it in w.doc.items.values)
        if (it.file != null && (it.type == 'pdf' || it.type == 'image') && it.rect.overlaps(r))
          '${it.type == 'pdf' ? pdfImageKey(it) : it.file}@${it.w.round()}',
    ]..sort();
    return ks.join('|');
  }

  void _disposeAll(Map<String, ui.Image>? m) {
    if (m == null) return;
    for (final i in m.values) {
      i.dispose();
    }
  }

  void _request(double px) {
    final w = widget;
    final keys = _keys();
    _loadedPx = px;
    _loadedKeys = keys;
    _loadedDoc = w.doc;
    _loadedSheet = w.sheet;
    final gen = ++_gen;
    if (keys.isEmpty) {
      // nada que pedir: se suelta lo viejo y se dibuja sin imágenes
      final old = _images;
      _images = null;
      _disposeAll(old);
      return;
    }
    thumbImagesLoader(w.store, w.doc, w.sheet, px).then((m) {
      if (!mounted || gen != _gen) {
        _disposeAll(m);
        return;
      }
      final old = _images;
      setState(() => _images = m);
      _disposeAll(old);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _gen++;
    _disposeAll(_images);
    _images = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return LayoutBuilder(builder: (context, box) {
      final px = box.maxWidth.isFinite ? box.maxWidth * MediaQuery.devicePixelRatioOf(context) : 0.0;
      final stale = !identical(_loadedDoc, w.doc) ||
          _loadedSheet != w.sheet ||
          _loadedKeys != _keys() ||
          px > _loadedPx * 1.5;
      if (stale && px > 0) {
        // (no se hace setState en el build: _request solo usa setState cuando llega la carga, ya en otro cuadro)
        _request(px);
      }
      return CustomPaint(painter: SheetThumbPainter(w.doc, sheet: w.sheet, version: w.version, images: _images));
    });
  }
}
