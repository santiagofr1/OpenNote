import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';

const _stickyInk = Color(0xFF2B2A27);

/// Elemento insertado en la hoja (imagen, nota adhesiva o audio), en su lugar y tamaño.
class ItemView extends StatelessWidget {
  final Item item;
  final File file; // imagen o audio en media/ (puede no existir)
  final double scale;
  final bool textMode, selected;
  final ValueChanged<String> onStickyChanged;
  final ValueChanged<bool>? onStickyFocus; // la nota ganó o perdió el foco (el editor la deja armada mientras lo tenga)
  const ItemView({
    super.key,
    required this.item,
    required this.file,
    required this.scale,
    required this.textMode,
    required this.selected,
    required this.onStickyChanged,
    this.onStickyFocus,
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
      _ => AudioChip(file: file, dur: it.dur, scale: s),
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
  const AudioChip({super.key, required this.file, required this.dur, required this.scale});
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
    return GestureDetector(
      // solo el dedo o el mouse reproducen; el lápiz sigue escribiendo encima
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      onTap: _toggle,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFFE9E6F5), borderRadius: BorderRadius.circular(999)),
        padding: EdgeInsets.symmetric(horizontal: 10 * s),
        child: Row(children: [
          Icon(playing ? Symbols.pause_circle : Symbols.play_circle, size: 34 * s, fill: 1, color: const Color(0xFF5B4FC4)),
          SizedBox(width: 8 * s),
          Expanded(
            child: Text(
              playing || pos > Duration.zero
                  ? '${fmtDuration(pos.inMilliseconds)} / ${fmtDuration(widget.dur)}'
                  : 'Audio · ${fmtDuration(widget.dur)}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(fontSize: 19 * s, color: _stickyInk, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          SizedBox(width: 24 * s), // equilibra el ícono de la izquierda
        ]),
      ),
    );
  }
}
