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

/// Arma el PDF del cuaderno: una hoja A4 por cada hoja, cada una con su fondo y su papel. Las secciones elegidas
/// ([sections], todas si es null) van una atrás de la otra, en su orden.
/// [only]: índices de las hojas de la sección abierta a incluir. [onProgress] recibe (hechas, total).
Future<Uint8List> buildNotebookPdf(Storage store, NotebookDoc nb,
    {void Function(int, int)? onProgress, List<int>? only, Set<String>? sections}) async {
  final sheets = exportSheets(nb.nb, sections: sections, only: only);
  final pdf = pw.Document(title: nb.nb.name, creator: 'OpenNote');
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
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
    ));
    onProgress?.call(++done, sheets.length);
  }
  return pdf.save();
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
Future<Map<String, ui.Image>> loadImages(Storage store, NotebookDoc doc, {int? sheet}) async {
  final images = <String, ui.Image>{};
  for (final it in doc.items.values) {
    if (sheet != null && !it.rect.overlaps(ui.Rect.fromLTWH(0, sheet * kSheetStep, kW, kSheetH))) continue;
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
  final sheetRect = ui.Rect.fromLTWH(0, sheet * kSheetStep, kW, kSheetH);
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

Future<Uint8List> renderSheetPng(NotebookDoc doc, int sheet, {Map<String, ui.Image>? images}) async {
  const k = _pxWidth / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(k);
  paintSheet(c, doc, sheet, k, images: images);
  final img = await rec.endRecording().toImage(_pxWidth.round(), (kSheetH * k).round());
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
  final refs = exportSheets(doc.nb, sections: sections);
  final n = refs.length;
  final safe = safeFileName(doc.nb.name).trim();
  final name = safe.isEmpty ? 'Cuaderno' : safe;
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
  final n = exportSheets(doc.nb, sections: sections).length;
  final zip = Archive();
  Uint8List? single;
  await for (final p in notebookPngs(store, doc, sections: sections, onProgress: onProgress, cancelled: cancelled)) {
    if (n == 1) single = p.png;
    zip.add(ArchiveFile.bytes(p.name, p.png));
  }
  if (zip.length < n) return null; // se canceló
  if (single != null) return (bytes: single, zip: false);
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
