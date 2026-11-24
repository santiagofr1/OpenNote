import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/domain.dart';
import '../rendering/pdf_pages.dart';
import '../rendering/sheet_render.dart';
import '../rendering/text_layout.dart';
import 'storage.dart';

/// Resolución de cada hoja exportada (ancho en píxeles): ~200 ppp en A4.
const _pxWidth = 1654.0;

/// Una hoja a exportar: su lugar [k] dentro de las hojas [list] de su sección [section].
typedef ExportSheet = ({Section section, int k, List<SheetMeta> list});

/// Las hojas a exportar, en el orden de las secciones. [sections]: ids de las secciones a incluir (todas si es null);
/// [only]: índices de hojas de la sección ABIERTA (si se da, se exporta solo eso y [sections] no cuenta).
List<ExportSheet> exportSheets(Notebook nb, {Set<String>? sections, List<int>? only}) {
  if (only != null) {
    return [for (var k = 0; k < nb.sheets.length; k++) if (only.contains(k)) (section: nb.activeSection, k: k, list: nb.sheets)];
  }
  return [
    for (final s in nb.sections)
      if (sections == null || sections.contains(s.id))
        for (var k = 0; k < nb.sheetsOf(s.id).length; k++) (section: s, k: k, list: nb.sheetsOf(s.id)),
  ];
}

/// Arma el PDF del cuaderno: una página del tamaño de cada hoja, cada una con su fondo y su papel. Las secciones elegidas
/// ([sections], todas si es null) van una atrás de la otra, en su orden.
/// [only]: índices de las hojas de la sección abierta a incluir. [onProgress] recibe (hechas, total).
Future<Uint8List> buildNotebookPdf(Storage store, NotebookDoc nb,
    {void Function(int, int)? onProgress, List<int>? only, Set<String>? sections}) async {
  final pdf = pw.Document(title: nb.nb.name, creator: 'OpenNote');
  if (nb.nb.canvas) {
    // lienzo infinito: se parte en páginas de ancho A4 (solo las que tienen algo)
    await for (final p in canvasPagePngs(store, nb, sections: sections, onProgress: onProgress)) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(kA4WidthMm * PdfPageFormat.mm, kA4WidthMm * kSheetStep / kW * PdfPageFormat.mm),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(p.png), fit: pw.BoxFit.fill),
      ));
    }
    return pdf.save();
  }
  final sheets = exportSheets(nb.nb, sections: sections, only: only);
  var done = 0;
  for (final e in sheets) {
    // las hojas sin cargar se leen de disco de a una y se sueltan: el PDF no necesita todo el cuaderno en memoria
    final (src, i) = await exportSource(store, nb, e);
    final images = await loadImages(store, src, sheet: i);
    final Uint8List png;
    try {
      png = await renderSheetPng(src, i, images: images);
    } finally {
      for (final img in images.values) {
        img.dispose();
      }
    }
    final m = src.sheets[i];
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat(paperWidthMm(m.size) * PdfPageFormat.mm, paperHeightMm(m.size) * PdfPageFormat.mm),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
    ));
    onProgress?.call(++done, sheets.length);
  }
  return pdf.save();
}

/// Páginas en que se parte un lienzo al exportar: celdas de [kW] x [kSheetStep] (ancho A4) recorridas por filas, y solo
/// las que tienen algo (algún trazo, texto o elemento que las toque). Si todo está vacío, una página (la primera).
List<ui.Rect> canvasPages(NotebookDoc doc) {
  final cols = max(1, (doc.width / kW).ceil());
  final rects = <ui.Rect>[
    for (var k = 0; k < doc.sheetCount; k++)
      for (var c = 0; c < cols; c++) ui.Rect.fromLTWH(c * kW, k * kSheetStep, kW, kSheetStep)
  ];
  final used = <ui.Rect>[
    for (final r in rects)
      if (doc.strokes.values.any((s) => s.bounds.overlaps(r)) ||
          doc.items.values.any((i) => i.rect.overlaps(r)) ||
          doc.texts.values.any((t) => t.text.trim().isNotEmpty && textBounds(t, doc.lineAt(t.y)).overlaps(r)))
        r
  ];
  return used.isEmpty ? [rects.first] : used;
}

/// El documento completo de la sección [section] de un lienzo (las hojas sin cargar se leen de disco), para partirlo
/// en páginas. Es del mismo cuaderno pero suelto: no toca el documento abierto.
Future<NotebookDoc> canvasSectionDoc(Storage store, NotebookDoc doc, Section section) async {
  final metas = doc.nb.sheetsOf(section.id);
  final active = section.id == doc.nb.activeSection.id;
  final contents = <SheetContent>[];
  for (final m in metas) {
    contents.add(active && doc.isLoaded(m.id) ? (doc.splitSheets({m.id})[m.id] ?? SheetContent()) : await store.readSheetContent(doc.nb, m));
  }
  return NotebookDoc.fromSheets(Notebook('', '', sheets: metas, canvas: true, canvasW: doc.nb.canvasW), contents);
}

/// Cada página (con contenido) de las secciones elegidas de un lienzo, ya dibujada como PNG, de a una.
/// [onProgress] recibe (hechas, total).
Stream<({Section section, int n, Uint8List png})> canvasPagePngs(Storage store, NotebookDoc doc,
    {Set<String>? sections, void Function(int, int)? onProgress, bool Function()? cancelled}) async* {
  final secs = [for (final s in doc.nb.sections) if (sections == null || sections.contains(s.id)) s];
  var total = 0, done = 0;
  for (final s in secs) {
    total += canvasPages(await canvasSectionDoc(store, doc, s)).length;
  }
  for (final s in secs) {
    final sdoc = await canvasSectionDoc(store, doc, s);
    final pages = canvasPages(sdoc);
    for (var i = 0; i < pages.length; i++) {
      if (cancelled?.call() ?? false) return;
      onProgress?.call(done, total);
      final images = await loadImages(store, sdoc, region: pages[i]);
      try {
        yield (section: s, n: i, png: await renderSheetPng(sdoc, 0, images: images, region: pages[i]));
      } finally {
        for (final img in images.values) {
          img.dispose();
        }
      }
      done++;
    }
  }
  onProgress?.call(total, total);
}

/// De dónde dibujar la hoja [k] de [nb]: el propio documento si está cargada; si no, un documento chico con la hoja
/// de arriba (de memoria o de disco: lo que se le pasa de largo cae en esta) y esta, leída de disco. Devuelve el
/// documento y el índice de la hoja en él. Lo que esté sin guardar de una hoja cargada se ve igual.
Future<(NotebookDoc, int)> sheetSource(Storage store, NotebookDoc nb, int k) async {
  if (nb.isLoadedAt(k)) return (nb, k);
  final metas = [if (k > 0) nb.sheets[k - 1], nb.sheets[k]];
  final contents = <SheetContent>[];
  for (final m in metas) {
    contents.add(nb.isLoaded(m.id) ? (nb.splitSheets({m.id})[m.id] ?? SheetContent()) : await store.readSheetContent(nb.nb, m));
  }
  return (NotebookDoc.fromSheets(Notebook('', '', sheets: metas), contents), metas.length - 1);
}

/// Como [sheetSource] pero para una hoja de [exportSheets]: si es de la sección abierta sale del documento; si es de
/// otra sección, de disco (con la de arriba de SU sección, por si un trazo se pasa).
Future<(NotebookDoc, int)> exportSource(Storage store, NotebookDoc doc, ExportSheet e) async {
  if (e.section.id == doc.nb.activeSection.id) return sheetSource(store, doc, e.k);
  final metas = [if (e.k > 0) e.list[e.k - 1], e.list[e.k]];
  final contents = [for (final m in metas) await store.readSheetContent(doc.nb, m)];
  return (NotebookDoc.fromSheets(Notebook('', '', sheets: metas), contents), metas.length - 1);
}

/// Imágenes insertadas en [doc] (solo las de la hoja [sheet] si se da), decodificadas, por nombre de archivo
/// (las que faltan se saltean). Las páginas de PDF van por [pdfImageKey], dibujadas al ancho de la salida.
Future<Map<String, ui.Image>> loadImages(Storage store, NotebookDoc doc, {int? sheet, ui.Rect? region}) async {
  final images = <String, ui.Image>{};
  for (final m in region != null ? const <SheetMeta>[] : sheet != null ? [doc.sheets[sheet]] : doc.sheets) {
    if (m.bg != 'image' || m.image == null) continue;
    final key = bgImageKey(m.image!), f = store.media(m.image!);
    if (!images.containsKey(key) && await f.exists()) images[key] = await decodeImage(await f.readAsBytes());
  }
  for (final it in doc.items.values) {
    if (region != null && !it.rect.overlaps(region)) continue;
    if (sheet != null && !it.rect.overlaps(doc.bandRect(sheet))) continue;
    if (it.type == 'pdf' && it.file != null) {
      final key = pdfImageKey(it);
      final f = store.media(it.file!);
      if (!images.containsKey(key) && await f.exists()) {
        final img = await pdfPages.page(f, it.page, pdfPixelWidth(it.w * _pxWidth / kW));
        if (img != null) images[key] = img;
      }
    } else if (it.type == 'image' && it.file != null && !images.containsKey(it.file)) {
      final f = store.media(it.file!);
      if (await f.exists()) images[it.file!] = await decodeImage(await f.readAsBytes());
    }
  }
  return images;
}

/// Las imágenes de la hoja [sheet] de [doc] para una miniatura de [pxWidth] px de ancho (como [loadImages] pero a ese
/// tamaño y no al completo: son muchas tarjetas). Quien la pide libera las imágenes que recibe. Sin imágenes ni PDF en la
/// hoja devuelve `{}` sin tocar el disco.
Future<Map<String, ui.Image>> loadThumbImages(Storage store, NotebookDoc doc, int sheet, double pxWidth) async {
  final images = <String, ui.Image>{};
  final sheetRect = ui.Rect.fromLTWH(0, sheet * kSheetStep, kW, kSheetH); // la miniatura es siempre de la hoja (o franja) tal cual
  final bgm = doc.sheets[sheet];
  if (bgm.bg == 'image' && bgm.image != null) {
    try {
      final f = store.media(bgm.image!);
      if (await f.exists()) {
        final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: max(1, pxWidth.ceil()));
        images[bgImageKey(bgm.image!)] = (await codec.getNextFrame()).image;
        codec.dispose();
      }
    } catch (_) {
      // un fondo roto no impide ver el resto de la miniatura
    }
  }
  for (final it in doc.items.values) {
    if (it.file == null || (it.type != 'pdf' && it.type != 'image') || !it.rect.overlaps(sheetRect)) continue;
    final w = it.w * pxWidth / kW;
    final key = it.type == 'pdf' ? pdfImageKey(it) : it.file!;
    if (images.containsKey(key)) continue;
    final f = store.media(it.file!);
    try {
      if (!await f.exists()) continue;
      if (it.type == 'pdf') {
        final img = await pdfPages.page(f, it.page, pdfPixelWidth(w));
        if (img != null) images[key] = img;
      } else {
        final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: max(1, w.ceil()));
        images[key] = (await codec.getNextFrame()).image;
        codec.dispose();
      }
    } catch (_) {
      // una imagen rota no impide ver el resto de la miniatura
    }
  }
  return images;
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// [region]: página de un lienzo (ver [paintSheet]); el PNG tiene el mismo ancho y el alto proporcional.
Future<Uint8List> renderSheetPng(NotebookDoc doc, int sheet, {Map<String, ui.Image>? images, ui.Rect? region}) async {
  const k = _pxWidth / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(k);
  paintSheet(c, doc, sheet, k, images: images, region: region);
  final img = await rec.endRecording().toImage(_pxWidth.round(), ((region?.height ?? kSheetH) * k).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// Cambia los caracteres que no se permiten en nombres de archivo.
String safeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

/// Abre el selector del sistema para elegir carpeta y nombre, y guarda el PDF.
/// Devuelve false si el usuario canceló.
Future<bool> savePdf(Uint8List bytes, String name) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar PDF',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.pdf',
    bytes: bytes,
    mimeType: 'application/pdf',
  );
  return uri != null;
}

/// Guarda la hoja [sheet] como PNG, preguntando dónde. Devuelve false si el usuario canceló.
Future<bool> saveSheetPng(Storage store, NotebookDoc doc, int sheet, String name) async {
  final (src, i) = await sheetSource(store, doc, sheet);
  final png = await renderSheetPng(src, i, images: await loadImages(store, src, sheet: i));
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar imagen',
    fileName: safeFileName('$name.png'),
    bytes: png,
    mimeType: 'image/png',
  );
  return uri != null;
}

/// Cada hoja como PNG, de a una (no carga todo en memoria), con el nombre de archivo que le toca:
/// "`cuaderno` - hoja 01.png" (ceros según la cantidad); si el cuaderno tiene más de una sección lleva la sección:
/// "`cuaderno` - `sección` - hoja 01.png" (el número es el de la hoja dentro de su sección). Los nombres no se pisan.
/// [sections]: ids de las secciones a incluir (todas si es null). [onProgress] recibe (hechas, total) antes de cada hoja.
/// Si [cancelled] da true entre hoja y hoja, el flujo termina sin dar las que faltan.
Stream<({String name, Uint8List png})> notebookPngs(Storage store, NotebookDoc doc,
    {Set<String>? sections, void Function(int, int)? onProgress, bool Function()? cancelled}) async* {
  final safe = safeFileName(doc.nb.name).trim();
  final name = safe.isEmpty ? 'Cuaderno' : safe;
  if (doc.nb.canvas) {
    // lienzo infinito: una imagen por página con contenido
    final multi = doc.nb.sections.length > 1, used = <String>{};
    await for (final p in canvasPagePngs(store, doc, sections: sections, onProgress: onProgress, cancelled: cancelled)) {
      final sec = safeFileName(p.section.name).trim();
      final base = '$name - ${multi ? '${sec.isEmpty ? 'Sección' : sec} - ' : ''}página ${'${p.n + 1}'.padLeft(2, '0')}';
      var file = base;
      for (var c = 2; !used.add(file); c++) {
        file = '$base ($c)';
      }
      yield (name: '$file.png', png: p.png);
    }
    return;
  }
  final refs = exportSheets(doc.nb, sections: sections);
  final n = refs.length;
  final most = refs.fold<int>(1, (m, e) => e.list.length > m ? e.list.length : m);
  final width = '$most'.length < 2 ? 2 : '$most'.length;
  final multi = doc.nb.sections.length > 1;
  final used = <String>{};
  for (var d = 0; d < n; d++) {
    final e = refs[d], k = e.k;
    if (cancelled?.call() ?? false) return;
    onProgress?.call(d, n);
    final (src, i) = await exportSource(store, doc, e);
    final images = await loadImages(store, src, sheet: i);
    final Uint8List png;
    try {
      png = await renderSheetPng(src, i, images: images);
    } finally {
      for (final img in images.values) {
        img.dispose();
      }
    }
    final sec = safeFileName(e.section.name).trim();
    final base = '$name - ${multi ? '${sec.isEmpty ? 'Sección' : sec} - ' : ''}hoja ${'${k + 1}'.padLeft(width, '0')}';
    var file = base;
    for (var c = 2; !used.add(file); c++) {
      file = '$base ($c)'; // dos secciones con el mismo nombre: no se pisan
    }
    yield (name: '$file.png', png: png);
  }
  onProgress?.call(n, n);
}

/// Un PNG por hoja ([notebookPngs]). Con varias hojas arma un ZIP; con una sola devuelve el PNG directo (`zip` falso).
/// [onProgress] recibe (hechas, total). Si [cancelled] da true entre hoja y hoja, devuelve null.
Future<({Uint8List bytes, bool zip})?> buildNotebookPngs(Storage store, NotebookDoc doc,
    {void Function(int, int)? onProgress, bool Function()? cancelled, Set<String>? sections}) async {
  final n = doc.nb.canvas ? -1 : exportSheets(doc.nb, sections: sections).length;
  final zip = Archive();
  Uint8List? single;
  await for (final p in notebookPngs(store, doc, sections: sections, onProgress: onProgress, cancelled: cancelled)) {
    single = p.png;
    zip.add(ArchiveFile.bytes(p.name, p.png));
  }
  if (n >= 0 && zip.length < n) return null; // se canceló
  if (n < 0 && (cancelled?.call() ?? false)) return null;
  if (zip.length == 1 && single != null) return (bytes: single, zip: false);
  return (bytes: Uint8List.fromList(ZipEncoder().encode(zip)), zip: true);
}

/// Guarda lo de [buildNotebookPngs] (un `.zip`, o un `.png` si [zip] es falso), preguntando dónde.
/// Es una variable para que los tests la reemplacen. Falso si el usuario canceló.
Future<bool> Function(Uint8List bytes, String name, bool zip) saveImages = (bytes, name, zip) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar imágenes',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.${zip ? 'zip' : 'png'}',
    bytes: bytes,
    mimeType: zip ? 'application/zip' : 'image/png',
  );
  return uri != null;
};

/// Abre el selector del sistema para elegir carpeta y nombre, y guarda el `.opennote`. Falso si el usuario canceló.
/// Es una variable para que los tests la reemplacen (no pueden manejar el diálogo del sistema).
Future<bool> Function(Uint8List bytes, String name) saveOpennote = (bytes, name) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar cuaderno',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.opennote',
    bytes: bytes,
    mimeType: 'application/octet-stream',
  );
  return uri != null;
};
