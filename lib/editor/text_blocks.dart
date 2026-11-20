import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import '../rendering/text_layout.dart';
import '../theme/colors.dart';
import 'rich_editing.dart';

/// Campos de edición (uno por párrafo, con su foco) de los bloques de texto de una página.
class TextFields {
  TextFields({required this.onFocusChange, required this.onLeftEmpty, required this.onEdited});

  /// Hay que redibujar (foco, párrafos nuevos, listas).
  final VoidCallback onFocusChange;

  /// Se salió de un bloque vacío: hay que borrarlo.
  final void Function(String id) onLeftEmpty;

  /// Se escribió / formateó un bloque: crece la hoja y se guarda.
  final void Function(TextBlock t) onEdited;

  /// Cambia con el foco, la selección y el formato: la barra de formato lo escucha.
  final tick = ValueNotifier(0);

  /// Último bloque donde se escribió o tuvo foco (el teclado vuelve ahí).
  String? lastEdited;

  late NotebookDoc doc;
  final _eds = <String, BlockEditor>{};
  final _saveTimers = <String, Timer>{};

  /// Arma los campos de todos los textos de [p] (y suelta los de la página anterior).
  void attach(NotebookDoc p) {
    for (final id in _eds.keys.toList()) {
      _unbind(id);
    }
    doc = p;
    for (final t in p.texts.values) {
      _bind(t);
    }
  }

  /// Arma los campos de los textos de la página que todavía no tienen (hojas que se cargaron).
  void adoptNew() {
    for (final t in doc.texts.values.toList()) {
      if (!_eds.containsKey(t.id)) _bind(t);
    }
  }

  /// Suelta los campos de los textos que ya no están en la página (hojas que se descargaron).
  void releaseGone() {
    for (final id in _eds.keys.toList()) {
      if (!doc.texts.containsKey(id)) _unbind(id);
    }
  }

  BlockEditor? editor(String id) => _eds[id];
  bool get anyFocused => _eds.values.any((e) => e.hasFocus);

  /// El bloque que tiene el foco ahora.
  BlockEditor? get focused {
    for (final e in _eds.values) {
      if (e.hasFocus) return e;
    }
    return null;
  }

  void _notify() => tick.value++;

  void _bind(TextBlock t) {
    late final BlockEditor ed;
    ed = BlockEditor(
      t,
      onStructure: () {
        _notify();
        onFocusChange();
      },
      onEdited: () {
        doc.markDirtyElement(ed.block); // cambió su contenido: la hoja se guarda
        lastEdited = ed.block.id;
        _notify();
        onEdited(ed.block);
      },
      onFocus: () {
        if (ed.hasFocus) lastEdited = ed.block.id;
        _notify();
        onFocusChange();
        if (!ed.hasFocus) {
          // pasó de un párrafo a otro del mismo bloque: se mira recién después del cuadro
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final cur = _eds[ed.block.id];
            if (cur == ed && !ed.hasFocus && ed.body.isBlank && doc.texts.containsKey(ed.block.id)) {
              onLeftEmpty(ed.block.id);
            }
          });
        }
      },
    );
    _eds[t.id] = ed;
  }

  void _unbind(String id) {
    _saveTimers.remove(id)?.cancel();
    final e = _eds.remove(id);
    if (e == null) return;
    // los campos todavía están en pantalla este frame: se liberan después
    WidgetsBinding.instance.addPostFrameCallback((_) => e.dispose());
  }

  /// Pone (o saca, si [t] es null) un bloque de texto en la página, con sus campos de edición.
  void put(String id, TextBlock? t) {
    if (t == null) {
      doc.texts.remove(id);
      _unbind(id);
      return;
    }
    doc.texts[id] = t;
    final e = _eds[id];
    if (e == null) {
      _bind(t);
    } else if (!identical(e.block, t) && e.block.body != t.body) {
      e.replaceModel(t);
    } else {
      e.block = t;
    }
  }

  /// Foca el último párrafo del bloque [id] y abre el teclado.
  void focusEnd(String id) {
    _eds[id]?.focusEnd();
    showKeyboard();
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
    for (final e in _eds.values) {
      e.dispose();
    }
    tick.dispose();
  }
}

/// Pide al sistema que muestre el teclado (el foco solo no alcanza si se lo ocultó a mano).
void showKeyboard() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show').catchError((_) {});
  });
}

/// Un bloque de texto sobre la hoja. Solo se toca en modo texto; ahí aparece la agarradera para moverlo.
class TextBlockView extends StatelessWidget {
  final TextBlock block;
  final BlockEditor editor;
  final double scale;
  final double line; // alto del renglón (unidades de la hoja donde está)
  final bool textMode, selected;
  final ValueChanged<Offset> onHandleDrag; // delta en píxeles de pantalla
  final VoidCallback onHandleDragEnd;
  const TextBlockView({
    super.key,
    required this.block,
    required this.editor,
    required this.scale,
    required this.line,
    required this.textMode,
    required this.selected,
    required this.onHandleDrag,
    required this.onHandleDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = block;
    editor
      ..line = line
      ..scale = scale;
    final focused = editor.hasFocus && textMode;
    return Positioned(
      left: t.x * scale,
      top: t.y * scale,
      width: t.w * scale,
      child: IgnorePointer(
        ignoring: !textMode,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            decoration: focused
                ? BoxDecoration(
                    color: const Color(0x082F5BD3),
                    border: Border.all(color: const Color(0x552F5BD3)),
                    borderRadius: BorderRadius.circular(3))
                : selected
                    ? BoxDecoration(color: const Color(0x1A2F5BD3), borderRadius: BorderRadius.circular(3))
                    : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < editor.fields.length; i++) _paraRow(i),
            ]),
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

  Widget _paraRow(int i) {
    final f = editor.fields[i], pl = editor.layoutFor(i);
    final h = line * scale;
    Widget marker = const SizedBox.shrink();
    if (pl.marker != null) {
      marker = Text(pl.marker!, style: pl.base, strutStyle: pl.strut);
    } else if (pl.para.list == ListKind.checklist) {
      final side = checkboxSide(line) * scale;
      marker = GestureDetector(
        key: Key('check-${block.id}-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: () => editor.toggleChecked(i),
        child: Align(
            alignment: Alignment.centerLeft,
            child: CustomPaint(size: Size(side, side), painter: _CheckPainter(pl.para.checked))),
      );
    }
    return Row(key: ValueKey(f.ctl), crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: pl.indent),
      SizedBox(width: pl.markerWidth, height: h, child: marker),
      Expanded(
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, e) => editor.handleKey(f.ctl.index, e) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: TextField(
            key: Key('para-${block.id}-$i'),
            controller: f.ctl,
            focusNode: f.focus,
            maxLines: null,
            textAlign: pl.align,
            style: pl.base,
            strutStyle: pl.strut,
            decoration: const InputDecoration.collapsed(hintText: ''),
            cursorColor: kAccent,
          ),
        ),
      ),
    ]);
  }
}

class _CheckPainter extends CustomPainter {
  final bool checked;
  _CheckPainter(this.checked);
  @override
  void paint(Canvas c, Size s) => paintCheckbox(c, Offset.zero & s, checked, kInk);
  @override
  bool shouldRepaint(_CheckPainter o) => o.checked != checked;
}
