import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import 'pdf_page_image.dart';
import 'voice_recorder.dart';

const _stickyInk = Color(0xFF2B2A27);

/// Elemento insertado en la hoja (imagen, página de PDF, nota adhesiva o audio), en su lugar y tamaño.
class ItemView extends StatelessWidget {
  final Item item;
  final File file; // imagen o audio en media/ (puede no existir)
  final double scale;
  final bool textMode, selected;
  final ValueChanged<String> onStickyChanged;
  final ValueChanged<bool>? onStickyFocus; // la nota ganó o perdió el foco (el editor la deja armada mientras lo tenga)

  /// La grabación de voz en curso (un audio que se está grabando se dibuja como etiqueta "Grabando") y qué hacer al tocar parar.
  final VoiceRecorder? recorder;
  final VoidCallback? onStopRecording;
  const ItemView({
    super.key,
    required this.item,
    required this.file,
    required this.scale,
    required this.textMode,
    required this.selected,
    required this.onStickyChanged,
    this.onStickyFocus,
    this.recorder,
    this.onStopRecording,
  });

  @override
  Widget build(BuildContext context) {
    final it = item, s = scale;
    final cs = Theme.of(context).colorScheme;
    final Widget child = switch (it.type) {
      'image' => ClipRRect(
          borderRadius: BorderRadius.circular(4 * s),
          child: Image.file(file,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(color: const Color(0xFFE6E3DA))),
        ),
      'pdf' => ClipRRect(
          borderRadius: BorderRadius.circular(4 * s),
          child: PdfPageImage(file: file, page: it.page, logicalWidth: it.w * s),
        ),
      'sticky' => Container(
          decoration: BoxDecoration(
            color: parseColor(it.color),
            borderRadius: BorderRadius.circular(10 * s),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
          ),
          padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 10 * s),
          child: IgnorePointer(
            // se escribe solo en modo texto; si no, el lápiz dibuja encima
            ignoring: !textMode,
            child: StickyField(
                key: ValueKey('sticky-${it.id}'),
                text: it.text,
                fontSize: 20 * s,
                onChanged: onStickyChanged,
                onFocus: onStickyFocus),
          ),
        ),
      _ => recorder == null
          ? AudioChip(file: file, dur: it.dur, scale: s, name: it.text)
          : ListenableBuilder(
              listenable: recorder!,
              builder: (_, _) => recorder!.isRecording(it.id)
                  ? RecordingChip(recorder: recorder!, scale: s, name: it.text, onStop: onStopRecording)
                  : AudioChip(file: file, dur: it.dur, scale: s, name: it.text),
            ),
    };
    return Positioned(
      left: it.x * s,
      top: it.y * s,
      width: it.w * s,
      height: it.h * s,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected ? Border.all(color: cs.primary.withValues(alpha: .7), width: 1.5) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    );
  }
}

/// Campo de texto de una nota adhesiva (mantiene su propio controlador)
class StickyField extends StatefulWidget {
  final String text;
  final double fontSize;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool>? onFocus;
  const StickyField({super.key, required this.text, required this.fontSize, required this.onChanged, this.onFocus});
  @override
  State<StickyField> createState() => _StickyFieldState();
}

class _StickyFieldState extends State<StickyField> {
  late final c = TextEditingController(text: widget.text);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onFocusChange: widget.onFocus,
        child: TextField(
          controller: c,
          maxLines: null,
          expands: true,
          style: TextStyle(fontSize: widget.fontSize, height: 1.35, color: _stickyInk),
          decoration: const InputDecoration.collapsed(hintText: 'Nota…', hintStyle: TextStyle(color: Color(0x662B2A27))),
          cursorColor: _stickyInk,
          onChanged: widget.onChanged,
        ),
      );
}

/// Audio insertado: tocar para reproducir/pausar
class AudioChip extends StatefulWidget {
  final File file;
  final int dur;
  final double scale;

  /// Nombre del audio ("Audio 3"); vacío en los audios viejos, que se ven como "Audio".
  final String name;
  const AudioChip({super.key, required this.file, required this.dur, required this.scale, this.name = ''});
  @override
  State<AudioChip> createState() => _AudioChipState();
}

class _AudioChipState extends State<AudioChip> {
  AudioPlayer? player;
  bool playing = false;
  Duration pos = Duration.zero;

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (player == null) {
      player = AudioPlayer();
      player!.onPositionChanged.listen((p) => mounted ? setState(() => pos = p) : null);
      player!.onPlayerComplete.listen((_) => mounted
          ? setState(() {
              playing = false;
              pos = Duration.zero;
            })
          : null);
    }
    if (playing) {
      await player!.pause();
    } else {
      await player!.play(DeviceFileSource(widget.file.path));
    }
    if (mounted) setState(() => playing = !playing);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    // Solo el botón de reproducir (los primeros ~54 unidades, ver PageEditor.kAudioPlayZone) reproduce: el resto del audio
    // es para elegirlo y moverlo con el dedo. Con el lápiz no reproduce: sigue escribiendo / eligiendo encima.
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFE9E6F5), borderRadius: BorderRadius.circular(999)),
      padding: EdgeInsets.only(right: 10 * s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          onTap: _toggle,
          child: Padding(
            padding: EdgeInsets.only(left: 10 * s, right: 8 * s),
            child: Center(
              child: Icon(playing ? Symbols.pause_circle : Symbols.play_circle,
                  size: 34 * s, fill: 1, color: const Color(0xFF5B4FC4)),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              playing || pos > Duration.zero
                  ? '${fmtDuration(pos.inMilliseconds)} / ${fmtDuration(widget.dur)}'
                  : '${widget.name.isEmpty ? 'Audio' : widget.name} · ${fmtDuration(widget.dur)}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(fontSize: 19 * s, color: _stickyInk, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
        SizedBox(width: 24 * s), // equilibra el ícono de la izquierda
      ]),
    );
  }
}

/// Audio que se está grabando: "Grabando" con un punto rojo que late, el tiempo transcurrido y el botón de parar (cuadrado).
/// Es un elemento común: se elige, se mueve y se escala. Solo el botón de parar (los últimos [stopZone] de ancho) responde
/// al toque del dedo o el mouse; el resto es para elegirlo y moverlo.
class RecordingChip extends StatefulWidget {
  /// Ancho (unidades de la hoja, desde el borde derecho) de la zona del botón de parar; ver `PageEditor._fingerTap`.
  static const stopZone = 64.0;
  final VoiceRecorder recorder;
  final double scale;
  final VoidCallback? onStop;

  /// Nombre del audio que se graba; se muestra después de "Grabando".
  final String name;
  const RecordingChip({super.key, required this.recorder, required this.scale, this.name = '', this.onStop});
  @override
  State<RecordingChip> createState() => _RecordingChipState();
}

class _RecordingChipState extends State<RecordingChip> with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale, red = Theme.of(context).colorScheme.error;
    return Container(
      key: const ValueKey('recordingChip'),
      decoration: BoxDecoration(
        color: const Color(0xFFF6E7E5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: red.withValues(alpha: .35), width: 1.5),
      ),
      padding: EdgeInsets.only(left: 18 * s, right: 10 * s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        FadeTransition(
          opacity: Tween(begin: .3, end: 1.0).animate(pulse),
          child: Container(key: const ValueKey('recordingDot'), width: 16 * s, height: 16 * s, decoration: BoxDecoration(color: red, shape: BoxShape.circle)),
        ),
        SizedBox(width: 12 * s),
        Expanded(
          child: Text(
            'Grabando${widget.name.isEmpty ? '' : ' · ${widget.name}'}  ${fmtDuration(widget.recorder.elapsedMs)}',
            key: const ValueKey('recordingTime'),
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: TextStyle(fontSize: 19 * s, color: _stickyInk, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          onTap: widget.onStop,
          child: Container(
            key: const ValueKey('recordingStop'),
            width: 44 * s,
            height: 44 * s,
            decoration: BoxDecoration(color: red, shape: BoxShape.circle),
            child: Icon(Symbols.stop, size: 26 * s, fill: 1, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
