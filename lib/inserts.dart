import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:printing/printing.dart';
import 'package:record/record.dart';

import 'model.dart';
import 'pdf_export.dart';
import 'storage.dart';

/// Selectores del sistema. Son variables para que los tests los reemplacen
/// (los tests no pueden tocar la galería ni la cámara de verdad).
class Pickers {
  static Future<File?> Function(bool camera) image = (camera) async {
    final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    return x == null ? null : File(x.path);
  };

  static Future<(Uint8List, String)?> Function() pdf = () async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final f = r.isEmpty ? null : r.first;
    if (f?.path == null) return null;
    return (await File(f!.path!).readAsBytes(), f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
  };

  static Future<File?> Function() audio = () async {
    final r = await FilePicker.pickFiles(type: FileType.audio);
    final p = r.isEmpty ? null : r.first.path;
    return p == null ? null : File(p);
  };
}

/// Imagen (galería o cámara) → elemento listo para insertar
Future<Item?> makeImageItem(Storage store, {required bool camera}) async {
  final f = await Pickers.image(camera);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  final img = await decodeImage(bytes);
  final ext = f.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  final name = await store.addMedia(bytes, ext);
  const w = 560.0;
  final h = w * img.height / img.width;
  img.dispose();
  return Item(newId('i'), 'image', 0, 0, w, h, file: name);
}

Item makeSticky() => Item(newId('i'), 'sticky', 0, 0, 320, 240, color: '#fde68a');

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

Future<Item?> makeAudioFileItem(Storage store) async {
  final f = await Pickers.audio();
  if (f == null) return null;
  final ext = f.path.contains('.') ? f.path.split('.').last.toLowerCase() : 'm4a';
  final name = await store.addMediaFile(f, ext);
  return Item(newId('i'), 'audio', 0, 0, 360, 64, file: name, dur: await audioDuration(store.media(name)));
}

/// PDF → una página nueva por cada hoja del PDF, con la hoja como imagen de fondo.
/// Devuelve las páginas creadas (ya guardadas) y sus títulos.
Future<List<(PageData, String)>> importPdf(Storage store, {void Function(int)? onPage}) async {
  final picked = await Pickers.pdf();
  if (picked == null) return [];
  final (bytes, name) = picked;
  final out = <(PageData, String)>[];
  var n = 0;
  await for (final raster in Printing.raster(bytes, dpi: 150)) {
    final png = await raster.toPng();
    final file = await store.addMedia(png, 'png');
    // que entre en la hoja respetando la proporción
    var w = kW, h = kW * raster.height / raster.width;
    if (h > kSheetH) {
      h = kSheetH;
      w = kSheetH * raster.width / raster.height;
    }
    final page = PageData(newId('p'), bg: 'blank');
    final it = Item(newId('i'), 'image', (kW - w) / 2, (kSheetH - h) / 2, w, h, file: file);
    page.items[it.id] = it;
    await store.savePage(page);
    n++;
    out.add((page, '$name · $n'));
    onPage?.call(n);
  }
  return out;
}

/// Diálogo de grabación de voz. Devuelve el elemento de audio o null si se canceló.
Future<Item?> recordVoice(BuildContext context, Storage store) => showDialog<Item>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecordDialog(store),
    );

class _RecordDialog extends StatefulWidget {
  final Storage store;
  const _RecordDialog(this.store);
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final rec = AudioRecorder();
  final sw = Stopwatch();
  Timer? tick;
  String? name, error;
  double level = 0;
  StreamSubscription? ampSub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await rec.hasPermission()) {
      setState(() => error = 'Sin permiso para usar el micrófono');
      return;
    }
    name = '${newId('m')}.m4a';
    await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: widget.store.media(name!).path);
    sw.start();
    tick = Timer.periodic(const Duration(milliseconds: 200), (_) => mounted ? setState(() {}) : null);
    ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      if (mounted) setState(() => level = ((a.current + 50) / 50).clamp(0.0, 1.0));
    });
  }

  Future<void> _finish(bool keep) async {
    tick?.cancel();
    await ampSub?.cancel();
    sw.stop();
    await rec.stop();
    await rec.dispose();
    if (!mounted) return;
    if (!keep || name == null) {
      if (name != null) unawaited(widget.store.media(name!).delete().catchError((_) => File('')));
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, Item(newId('i'), 'audio', 0, 0, 360, 64, file: name, dur: sw.elapsedMilliseconds));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = sw.elapsed.inSeconds;
    return AlertDialog(
      icon: Icon(Symbols.mic, weight: 300, color: cs.error),
      title: const Text('Grabando'),
      content: error != null
          ? Text(error!)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: level, minHeight: 6, color: cs.error, backgroundColor: cs.surfaceContainerHighest),
              ),
            ]),
      actions: [
        TextButton(onPressed: () => _finish(false), child: const Text('Descartar')),
        if (error == null) FilledButton.icon(onPressed: () => _finish(true), icon: const Icon(Symbols.stop, fill: 1), label: const Text('Terminar')),
      ],
    );
  }
}
