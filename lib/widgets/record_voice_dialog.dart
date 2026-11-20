import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:record/record.dart';

import '../data/media_import.dart';
import '../data/storage.dart';
import '../domain/domain.dart';

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
    Navigator.pop(context, makeAudioItem(name!, sw.elapsedMilliseconds));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Symbols.mic, weight: 300, color: cs.error),
      title: const Text('Grabando'),
      content: error != null
          ? Text(error!)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(fmtDuration(sw.elapsedMilliseconds),
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w300,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: level, minHeight: 6, color: cs.error, backgroundColor: cs.surfaceContainerHighest),
              ),
            ]),
      actions: [
        TextButton(onPressed: () => _finish(false), child: const Text('Descartar')),
        if (error == null)
          FilledButton.icon(
              onPressed: () => _finish(true), icon: const Icon(Symbols.stop, fill: 1), label: const Text('Terminar')),
      ],
    );
  }
}
