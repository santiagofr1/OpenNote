import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/domain.dart';
import '../sync/sync_paths.dart';
import 'export.dart';
import 'media_import.dart';
import 'storage.dart';

/// Plantilla propia de este dispositivo: una imagen de media/ que se usa de fondo de hoja.
class SheetTemplate {
  final String id;
  String name;
  final String file;
  SheetTemplate(this.id, this.name, this.file);

  factory SheetTemplate.fromJson(Map j) => SheetTemplate(j['id'] as String, (j['name'] ?? '') as String, j['file'] as String);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'file': file};
}

Directory _templatesDir(Storage store) => Directory('${store.dir.path}/templates');

/// Las plantillas propias, por fecha de creación (y por id si empatan). Cada una es un archivo `templates/<id>.json`
/// que se sincroniza; los rotos o con el id distinto del nombre se ignoran.
Future<List<SheetTemplate>> readTemplates(Storage store) async {
  final d = _templatesDir(store);
  final out = <(int, SheetTemplate)>[];
  try {
    await d.create(recursive: true);
    await for (final e in d.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (syncKind('templates/$name') != SyncKind.template) continue;
      try {
        final j = jsonDecode(await e.readAsString()) as Map;
        if (j['id'] != name.substring(0, name.length - 5)) continue;
        out.add(((j['created'] ?? 0) as int, SheetTemplate.fromJson(j)));
      } catch (_) {
        // archivo roto: se ignora
      }
    }
  } catch (_) {}
  out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.id.compareTo(b.$2.id));
  return [for (final (_, t) in out) t];
}

Future<SheetTemplate> _register(Storage store, String name, String file) async {
  final t = SheetTemplate(newId('t'), name, file);
  final j = {...t.toJson(), 'created': DateTime.now().millisecondsSinceEpoch};
  await store.writeSyncFile(templatePath(t.id), utf8.encode(jsonEncode(j)));
  return t;
}

/// Plantilla desde un PNG / JPG de la tablet (el selector es [Pickers.bgImage]). Si pasa de 2000 px de ancho se achica.
/// null si se canceló o la imagen no se puede leer.
Future<SheetTemplate?> templateFromImage(Storage store) async {
  final f = await Pickers.bgImage();
  if (f == null) return null;
  try {
    final bytes = await f.readAsBytes();
    final img = await decodeImage(bytes);
    final w = img.width;
    img.dispose();
    final ext = mediaExt(f.path, 'png');
    final String name;
    if (w > 2000 || (ext != 'png' && ext != 'jpg')) {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: w > 2000 ? 2000 : null);
      final small = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await small.toByteData(format: ui.ImageByteFormat.png);
      small.dispose();
      name = await store.addMedia(data!.buffer.asUint8List(), 'png');
    } else {
      name = await store.addMedia(bytes, ext);
    }
    final base = f.path.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return await _register(store, dot > 0 ? base.substring(0, dot) : base, name);
  } catch (_) {
    return null;
  }
}

/// Plantilla desde la hoja [sheet] de [doc] tal como se ve (con su contenido), llamada [name].
Future<SheetTemplate> templateFromSheet(Storage store, NotebookDoc doc, int sheet, String name) async {
  final (src, i) = await sheetSource(store, doc, sheet);
  final images = await loadImages(store, src, sheet: i);
  final Uint8List png;
  try {
    png = await renderSheetPng(src, i, images: images);
  } finally {
    for (final img in images.values) {
      img.dispose();
    }
  }
  return _register(store, name, await store.addMedia(png, 'png'));
}

/// Borra la plantilla [id] (la sync propaga el borrado). No borra su imagen de media/: hojas que la usan pueden seguir mostrándola.
Future<void> deleteTemplate(Storage store, String id) => store.deleteSyncFile(templatePath(id));
