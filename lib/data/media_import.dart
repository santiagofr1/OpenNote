import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/domain.dart';
import '../rendering/pdf_pages.dart';
import 'export.dart';
import 'storage.dart';

/// Selectores del sistema. Son variables para que los tests los reemplacen
/// (los tests no pueden tocar la galería ni la cámara de verdad).
class Pickers {
  static Future<File?> Function(bool camera) image = (camera) async {
    final x = await ImagePicker()
        .pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    return x == null ? null : File(x.path);
  };

  static Future<(Uint8List, String)?> Function() pdf = () async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final f = r.isEmpty ? null : r.first;
    if (f?.path == null) return null;
    return (await File(f!.path!).readAsBytes(), f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
  };

  /// Un archivo `.opennote` (bytes) para importar; null si se canceló.
  static Future<Uint8List?> Function() opennote = () async {
    final r = await FilePicker.pickFiles(type: FileType.any);
    final p = r.isEmpty ? null : r.first.path;
    return p == null ? null : File(p).readAsBytes();
  };

  /// Una imagen (PNG / JPG) de la tablet para usar de fondo de hoja; null si se canceló.
  static Future<File?> Function() bgImage = () async {
    final r = await FilePicker.pickFiles(type: FileType.image);
    final p = r.isEmpty ? null : r.first.path;
    return p == null ? null : File(p);
  };

  /// Cuánto dura un audio (ms); variable para que los tests no necesiten el plugin de audio.
  static Future<int> Function(File) audioLength = (f) => audioDuration(f);

  static Future<File?> Function() audio = () async {
    final r = await FilePicker.pickFiles(type: FileType.audio);
    final p = r.isEmpty ? null : r.first.path;
    return p == null ? null : File(p);
  };
}

/// Imagen (galería o cámara) → elemento listo para insertar, con la proporción de la foto.
Future<Item?> makeImageItem(Storage store, {required bool camera}) async {
  final f = await Pickers.image(camera);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  final img = await decodeImage(bytes);
  final ext = mediaExt(f.path, 'jpg') == 'png' ? 'png' : 'jpg';
  final name = await store.addMedia(bytes, ext);
  const w = 560.0;
  final h = w * img.height / img.width;
  img.dispose();
  return Item(newId('i'), 'image', 0, 0, w, h, file: name);
}

Item makeSticky() => Item(newId('i'), 'sticky', 0, 0, 320, 240, color: '#fde68a');

/// Audio ya guardado en media/ ([file]) de [dur] ms, con el nombre [name] (en `Item.text`; vacío = sin nombre).
Item makeAudioItem(String file, int dur, {String name = ''}) =>
    Item(newId('i'), 'audio', 0, 0, 360, 64, file: file, dur: dur, text: name);

/// Nombre por defecto de un audio nuevo: "Audio N", con N = el mayor número de "Audio N" que ya hay en [items] + 1.
/// Ve solo los elementos de las hojas cargadas (las otras no están en memoria).
String nextAudioName(Iterable<Item> items) {
  var top = 0;
  for (final it in items) {
    if (it.type != 'audio') continue;
    final n = int.tryParse(RegExp(r'^Audio (\d+)$').firstMatch(it.text.trim())?.group(1) ?? '');
    if (n != null && n > top) top = n;
  }
  return 'Audio ${top + 1}';
}

/// Duración en ms (0 si no se puede leer).
Future<int> audioDuration(File f) async {
  final p = AudioPlayer();
  try {
    await p.setSource(DeviceFileSource(f.path));
    final d = await p.getDuration().timeout(const Duration(seconds: 4), onTimeout: () => null);
    return d?.inMilliseconds ?? 0;
  } catch (_) {
    return 0;
  } finally {
    await p.dispose();
  }
}

/// La extensión para el nombre en media/ de un archivo elegido ([path]): solo la del NOMBRE del archivo (no la de las
/// carpetas) y solo si son letras y números (hasta 8). Si no, [fallback]. Todo nombre de media/ tiene que encajar en
/// sync_paths.dart: una extensión con espacios, barras o muy larga dejaba el archivo sin sincronizar (o sin copiar).
String mediaExt(String path, String fallback) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : fallback;
}

Future<Item?> makeAudioFileItem(Storage store, {String name = ''}) async {
  final f = await Pickers.audio();
  if (f == null) return null;
  final ext = mediaExt(f.path, 'm4a');
  final file = await store.addMediaFile(f, ext);
  return makeAudioItem(file, await Pickers.audioLength(store.media(file)), name: name);
}

/// PDF → una hoja nueva por cada página del PDF. El PDF se guarda UNA vez en media/ y cada hoja trae un elemento
/// `pdf` con su página (se dibuja a demanda, ver pdf_pages.dart): no se rasteriza nada al importar. Cada hoja viene
/// con su contenido (coordenadas locales) y se titula "archivo · n"; quien llama la pone en el cuaderno.
Future<List<(SheetMeta, SheetContent)>> importPdf(Storage store, {void Function(int)? onPage}) async {
  final picked = await Pickers.pdf();
  if (picked == null) return [];
  final (bytes, name) = picked;
  final file = await store.addMedia(bytes, 'pdf');
  final sizes = await pdfPages.pageSizes(store.media(file));
  if (sizes.isEmpty) {
    try {
      await store.media(file).delete(); // roto o sin páginas: no queda el archivo huérfano
    } catch (_) {}
    return [];
  }
  final out = <(SheetMeta, SheetContent)>[];
  for (var i = 0; i < sizes.length; i++) {
    final s = sizes[i];
    // que entre en la hoja respetando la proporción
    var w = kW, h = kW * s.height / s.width;
    if (h > kSheetH) {
      h = kSheetH;
      w = kSheetH * s.width / s.height;
    }
    final it = Item(newId('i'), 'pdf', (kW - w) / 2, (kSheetH - h) / 2, w, h, file: file, page: i);
    out.add((SheetMeta(newId('h'), title: '$name · ${i + 1}', bg: 'blank'), SheetContent(items: [it])));
    onPage?.call(i + 1);
  }
  return out;
}
