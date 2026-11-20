import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import '../rendering/text_layout.dart';
import '../theme/colors.dart';

/// Campos de edición (controlador + foco) de los bloques de texto de una página.
class TextFields {
  TextFields({required this.onFocusChange, required this.onLeftEmpty});

  /// Cambió el foco de algún bloque (hay que redibujar su borde).
  final VoidCallback onFocusChange;

  /// Se salió de un bloque vacío: hay que borrarlo.
  final void Function(String id) onLeftEmpty;

  late NotebookDoc doc;
  final _ctrls = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _saveTimers = <String, Timer>{};

  /// Arma los campos de todos los textos de [p] (y suelta los de la página anterior).
  void attach(NotebookDoc p) {
    for (final id in _ctrls.keys.toList()) {
      _unbind(id);
    }
    doc = p;
    for (final t in p.texts.values) {
      _bind(t);
    }
  }

  TextEditingController? controller(String id) => _ctrls[id];
  FocusNode? focusOf(String id) => _focus[id];
  bool get anyFocused => _focus.values.any((f) => f.hasFocus);

  void _bind(TextBlock t) {
    final c = TextEditingController(text: t.text);
    final f = FocusNode();
    f.addListener(() {
      if (!f.hasFocus && c.text.trim().isEmpty && doc.texts.containsKey(t.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onLeftEmpty(t.id));
      }
      onFocusChange();
    });
    _ctrls[t.id] = c;
    _focus[t.id] = f;
  }

  void _unbind(String id) {
    _saveTimers.remove(id)?.cancel();
    final c = _ctrls.remove(id), f = _focus.remove(id);
    // el campo todavía está en pantalla este frame: se libera después
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c?.dispose();
      f?.dispose();
    });
  }

  /// Pone (o saca, si [t] es null) un bloque de texto en la página, con su campo de edición.
  void put(String id, TextBlock? t) {
    if (t == null) {
      doc.texts.remove(id);
      _unbind(id);
      return;
    }
    doc.texts[id] = t;
    final c = _ctrls[id];
    if (c == null) {
      _bind(t);
    } else if (c.text != t.text) {
      c.text = t.text;
    }
  }

  /// Guarda [onSave] después de una pausa al escribir, para no grabar en cada tecla.
  void debounceSave(String id, VoidCallback onSave) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] = Timer(const Duration(milliseconds: 300), onSave);
  }

  void dispose() {
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
  }
}

/// Un bloque de texto sobre la hoja. Solo se toca en modo texto; ahí aparece la agarradera para moverlo.
class TextBlockView extends StatelessWidget {
  final TextBlock block;
  final TextEditingController controller;
  final FocusNode focus;
  final double scale;
  final double line; // alto del renglón (unidades de la hoja donde está)
  final bool textMode, selected;
  final ValueChanged<String> onChanged;
  final ValueChanged<Offset> onHandleDrag; // delta en píxeles de pantalla
  final VoidCallback onHandleDragEnd;
  const TextBlockView({
    super.key,
    required this.block,
    required this.controller,
    required this.focus,
    required this.scale,
    required this.line,
    required this.textMode,
    required this.selected,
    required this.onChanged,
    required this.onHandleDrag,
    required this.onHandleDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = block;
    return Positioned(
      left: t.x * scale,
      top: t.y * scale,
      width: t.w * scale,
      child: IgnorePointer(
        ignoring: !textMode,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            decoration: focus.hasFocus && textMode
                ? BoxDecoration(
                    color: const Color(0x082F5BD3),
                    border: Border.all(color: const Color(0x552F5BD3)),
                    borderRadius: BorderRadius.circular(3))
                : selected
                    ? BoxDecoration(color: const Color(0x1A2F5BD3), borderRadius: BorderRadius.circular(3))
                    : null,
            child: TextField(
              controller: controller,
              focusNode: focus,
              maxLines: null,
              style: textStyle(line, scale: scale, color: kInk),
              strutStyle: textStrut(line, scale: scale),
              decoration: const InputDecoration.collapsed(hintText: ''),
              cursorColor: kAccent,
              onChanged: onChanged,
            ),
          ),
          if (textMode)
            Positioned(
              left: -30,
              top: 0,
              child: GestureDetector(
                onPanUpdate: (d) => onHandleDrag(d.delta),
                onPanEnd: (_) => onHandleDragEnd(),
                child: SizedBox(
                  width: 26,
                  height: max(line * scale, 28),
                  child: const Icon(Symbols.drag_indicator, size: 20, color: Color(0x99777777)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
