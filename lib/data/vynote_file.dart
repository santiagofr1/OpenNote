import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/domain.dart';
import 'sheet_codec.dart';
import 'storage.dart';

/// Versión del formato de los archivos `.vynote` que escribe esta app. Se rechazan los de una versión más nueva.
const kVynoteFormat = 1;

enum VynoteError {
  notReadable,
  missingFile,
  brokenFile,
  notVynote,
  newerVersion,
  brokenSheetList,
  noSheets,
  brokenSheet,
  brokenSheetAny,
  invalidNames,
  notZip,
  noNotebooks,
  other,
}

/// El archivo no se pudo importar (roto, de otra app o de una versión más nueva). [message] se le muestra al usuario.
class VynoteException implements Exception {
  final String message;

  /// Qué pasó, para que la pantalla lo muestre en el idioma de la app ([message] queda en español para los logs).
  final VynoteError kind;

  /// Nombre del archivo o de la hoja a la que se refiere el error, si aplica.
  final String? arg;
  VynoteException(this.message, {this.kind = VynoteError.other, this.arg});
  @override
  String toString() => message;
}

/// Un `.vynote` es un ZIP con:
///   `manifest.json`            {app, format, name, bg, paper, spacing, size, sheets, exported}
///   `notebook.json`            secciones, orden y datos de las hojas (igual que en disco; todas las secciones)
///   `sheets/<hoja>.sheet`      el archivo de cada hoja tal cual está en disco (sin decodificar)
///   `media/<archivo>`          las imágenes y audios que usan las hojas
/// Las hojas no cargadas se copian de disco: no hace falta cargarlas. Lo que esté sin guardar tiene que guardarse antes
/// (la pantalla del cuaderno hace flush).
Future<Uint8List> exportNotebookBytes(Storage store, Notebook nb) async {
  await store.settle(nb.id);
  final zip = Archive();
  final media = <String>{};
  for (final m in nb.allSheets) {
    final f = store.sheetFile(nb.id, m.id);
    if (!await f.exists()) continue; // hoja nueva que nunca se escribió: queda vacía al importar
    final bytes = await f.readAsBytes();
    zip.add(ArchiveFile.bytes('sheets/${m.id}.sheet', bytes));
    media.addAll(await _compute(() => _mediaOf(bytes)));
  }
  for (final m in nb.allSheets) {
    if (m.image != null) media.add(m.image!);
  }
  if (nb.image != null) media.add(nb.image!);
  for (final name in media) {
    final f = store.media(name);
    if (await f.exists()) zip.add(ArchiveFile.bytes('media/$name', await f.readAsBytes()));
  }
  final manifest = {
    'app': 'Vynote',
    'format': kVynoteFormat,
    'notebookFormat': Notebook.kFormat,
    'name': nb.name,
    'bg': nb.bg,
    if (nb.image != null) 'image': nb.image,
    'paper': nb.paper,
    'spacing': nb.spacing,
    if (nb.size != 'a4') 'size': nb.size,
    if (nb.canvas) 'canvas': true,
    if (nb.canvas) 'canvasW': nb.canvasW,
    'sheets': nb.totalSheets,
    'exported': DateTime.now().millisecondsSinceEpoch,
  };
  zip.add(ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))));
  zip.add(ArchiveFile.bytes('notebook.json', utf8.encode(jsonEncode(nb.sheetsJson()))));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

/// Nombres de archivo de media que usan las imágenes y audios de esta hoja.
Set<String> _mediaOf(Uint8List sheet) {
  try {
    return {for (final it in decodeSheet(sheet).items) if (it.file != null) it.file!};
  } on SheetFormatException {
    return {};
  }
}

/// Importa el `.vynote` [bytes] como un cuaderno NUEVO (id nuevo; no pisa nada) y lo devuelve ya escrito en disco,
/// pero sin agregarlo al índice (eso lo hace quien llama). [taken]: nombres de cuadernos que ya existen: si el del
/// archivo choca se llama "X (importado)". Valida todo antes de escribir; si el archivo está roto lanza [VynoteException]
/// y no deja nada en disco.
Future<Notebook> importNotebookBytes(Storage store, Uint8List bytes,
    {required Set<String> taken, String? folder}) async {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw VynoteException('El archivo no es un cuaderno de Vynote (no se puede leer).', kind: VynoteError.notReadable);
  }
  final files = <String, ArchiveFile>{for (final f in zip) if (f.isFile) f.name: f};

  Map readJson(String name) {
    final f = files[name];
    if (f == null) throw VynoteException('Al archivo le falta $name: está roto o no es de Vynote.', kind: VynoteError.missingFile, arg: name);
    try {
      return jsonDecode(utf8.decode(f.readBytes()!)) as Map;
    } catch (_) {
      throw VynoteException('$name está roto.', kind: VynoteError.brokenFile, arg: name);
    }
  }

  final manifest = readJson('manifest.json');
  // los `.opennote` de antes del cambio de nombre traen app 'OpenNote': se siguen aceptando
  if (!{'Vynote', 'OpenNote'}.contains(manifest['app']) || manifest['format'] is! int) {
    throw VynoteException('El archivo no es un cuaderno de Vynote.', kind: VynoteError.notVynote);
  }
  if ((manifest['format'] as int) > kVynoteFormat) {
    throw VynoteException('El archivo es de una versión más nueva de Vynote. Actualizá la app para abrirlo.', kind: VynoteError.newerVersion);
  }
  final List<SheetMeta> sheets;
  final Map nbJson;
  try {
    nbJson = readJson('notebook.json');
    // se lee con el mismo código que el disco: archivos viejos (sin secciones) quedan en "General"
    sheets = (Notebook('', '')..loadSheetsJson(nbJson)).allSheets;
  } on VynoteException {
    rethrow;
  } catch (_) {
    throw VynoteException('La lista de hojas está rota.', kind: VynoteError.brokenSheetList);
  }
  if (sheets.isEmpty) throw VynoteException('El cuaderno no tiene hojas.', kind: VynoteError.noSheets);
  final ids = <String>{};
  for (final m in sheets) {
    // los ids son nombres de archivo: nada de rutas ni repetidos
    if (!isSafeId(m.id) || !ids.add(m.id)) throw VynoteException('La lista de hojas está rota.', kind: VynoteError.brokenSheetList);
  }

  final sheetFiles = <String, Uint8List>{};
  for (final m in sheets) {
    final f = files['sheets/${m.id}.sheet'];
    if (f == null) continue; // hoja sin archivo: vacía
    List<int>? data;
    try {
      data = f.readBytes(); // una entrada dañada del zip (CRC, cifrada) tira acá
    } catch (_) {
      data = null;
    }
    if (data == null) throw VynoteException('La hoja ${m.id} está rota.', kind: VynoteError.brokenSheet, arg: m.id);
    final b = Uint8List.fromList(data);
    final ok = await _compute(() {
      try {
        decodeSheet(b);
        return true;
      } on SheetFormatException {
        return false;
      }
    });
    if (!ok) throw VynoteException('Una hoja del archivo está rota.', kind: VynoteError.brokenSheetAny);
    sheetFiles[m.id] = b;
  }
  final media = <String, Uint8List>{};
  for (final f in files.values) {
    if (!f.name.startsWith('media/')) continue;
    final name = f.name.substring(6);
    if (!isSafeFileName(name)) throw VynoteException('El archivo tiene nombres no válidos.', kind: VynoteError.invalidNames);
    List<int>? d;
    try {
      d = f.readBytes();
    } catch (_) {
      throw VynoteException('El archivo está roto.', kind: VynoteError.brokenFile, arg: f.name);
    }
    if (d != null) media[name] = Uint8List.fromList(d);
  }

  final name = _uniqueName(manifest['name'] is String && (manifest['name'] as String).trim().isNotEmpty ? (manifest['name'] as String).trim() : 'Cuaderno', taken);
  final nb = Notebook(newId('n'), name,
      bg: manifest['bg'] is String ? manifest['bg'] as String : 'lined',
      image: manifest['image'] is String ? manifest['image'] as String : null,
      paper: manifest['paper'] is String ? manifest['paper'] as String : '#fffefb',
      spacing: manifest['spacing'] is num ? (manifest['spacing'] as num).toDouble() : null,
      size: validPaperSize(manifest['size']),
      canvas: manifest['canvas'] == true,
      canvasW: (manifest['canvasW'] is num ? (manifest['canvasW'] as num).toDouble() : kCanvasW0).clamp(kCanvasW0, 1e6).toDouble(),
      folder: folder)
    ..loadSheetsJson(nbJson) // secciones y hojas (las secciones se conservan al importar)
    ..touch();
  // la media es compartida: lo que ya está no se pisa
  for (final e in media.entries) {
    final f = store.media(e.key);
    if (!await f.exists()) await f.writeAsBytes(e.value, flush: true);
  }
  await store.writeImportedNotebook(nb, sheetFiles);
  return nb;
}

String _uniqueName(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  var n = 1, name = '$base (importado)';
  while (taken.contains(name)) {
    name = '$base (importado ${++n})';
  }
  return name;
}

Future<R> _compute<R>(R Function() f) => Storage.useIsolates ? Isolate.run(f) : Future.sync(f);
