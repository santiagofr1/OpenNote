import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../rendering/pdf_pages.dart';

/// Una página de un PDF (de media/) dibujada a demanda. Mientras llega se ve el papel en blanco; si cambia el ancho
/// que hace falta (zoom) sigue mostrando la anterior hasta que llegue la nueva.
class PdfPageImage extends StatefulWidget {
  final File file;
  final int page;
  final double logicalWidth; // ancho en pantalla, en píxeles lógicos
  const PdfPageImage({super.key, required this.file, required this.page, required this.logicalWidth});
  @override
  State<PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<PdfPageImage> {
  ui.Image? _img;
  int _wantedW = 0; // lo último que se pidió
  int _seq = 0;

  /// Para los tests: ya se muestra una imagen.
  bool get hasImage => _img != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(PdfPageImage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path || old.page != widget.page) {
      _img?.dispose();
      _img = null;
      _wantedW = 0;
    }
    _request();
  }

  void _request() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = pdfPixelWidth(max(1.0, widget.logicalWidth) * dpr);
    if (w == _wantedW) return;
    _wantedW = w;
    final seq = ++_seq;
    pdfPages.page(widget.file, widget.page, w).then((img) {
      if (img == null) return;
      if (!mounted || seq != _seq) {
        img.dispose();
        return;
      }
      setState(() {
        _img?.dispose();
        _img = img;
      });
    });
  }

  @override
  void dispose() {
    _seq++;
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFFFFFFF), border: Border.fromBorderSide(BorderSide(color: Color(0x22000000)))),
      );
    }
    return RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
  }
}
