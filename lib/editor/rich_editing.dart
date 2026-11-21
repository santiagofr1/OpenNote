import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/domain.dart';
import '../rendering/text_layout.dart';

/// Carácter invisible al principio del texto de cada campo. Si el usuario lo borra (retroceso al
/// principio del párrafo) lo notamos aunque el teclado del celular no mande ninguna tecla.
const kGuide = '​';

/// Controlador del campo de UN párrafo. Muestra el párrafo con su formato ([buildTextSpan]) y
/// pasa lo que se escribe al modelo ([BlockEditor]) antes de aceptarlo.
class RichController extends TextEditingController {
  RichController(this.ed, this.index, String content) : super(text: kGuide + content);

  final BlockEditor ed;
  int index;
  bool _silent = false;

  /// Pone [v] sin tratarlo como una edición del usuario.
  void setSilently(TextEditingValue v) {
    _silent = true;
    try {
      super.value = v;
    } finally {
      _silent = false;
    }
  }

  /// Texto del párrafo (sin el carácter guía).
  String get content => text.startsWith(kGuide) ? text.substring(1) : text;

  /// Alinea el campo con el modelo (texto y formato).
  void syncFromModel() {
    final want = kGuide + ed.body.paras[index].text;
    if (text == want) {
      notifyListeners(); // solo cambió el formato: se vuelve a armar el span
      return;
    }
    final len = want.length;
    setSilently(TextEditingValue(
        text: want,
        selection: TextSelection(
            baseOffset: selection.baseOffset.clamp(1, len), extentOffset: selection.extentOffset.clamp(1, len))));
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) =>
      ed.layoutFor(index).span(lead: kGuide, sel: ed.acrossLocal(index));

  @override
  set value(TextEditingValue v) {
    if (_silent) {
      super.value = v;
      return;
    }
    var nv = v;
    if (nv.text != text) {
      final r = ed.userEdit(index, text, nv);
      if (r == null) return; // lo resolvió el editor (partió o unió párrafos)
      nv = r;
    }
    final len = nv.text.length;
    if (nv.selection.isValid && (nv.selection.start < 1 || nv.selection.end > len)) {
      nv = nv.copyWith(
          selection: TextSelection(
              baseOffset: nv.selection.baseOffset.clamp(1, len), extentOffset: nv.selection.extentOffset.clamp(1, len)));
    }
    final selChanged = nv.selection != selection;
    super.value = nv;
    if (selChanged) ed.selectionChanged();
  }
}

class ParaField {
  final RichController ctl;
  final FocusNode focus;
  ParaField(this.ctl, this.focus);
}

/// Edición de un bloque de texto: un campo por párrafo (así cada uno tiene su alineación, sangría y
/// marcador) y el modelo ([TextBlock.body]) como única fuente de verdad. Los formatos se aplican con
/// las operaciones puras de [RichBody].
class BlockEditor {
  BlockEditor(this.block, {required this.onStructure, required this.onEdited, required this.onFocus}) {
    _rebuildFields();
  }

  TextBlock block;
  final VoidCallback onStructure; // cambió la cantidad de párrafos / listas: hay que rearmar la vista
  final VoidCallback onEdited; // cambió el contenido: guardar
  final VoidCallback onFocus; // cambió el foco o la selección: refrescar la barra de formato

  final fields = <ParaField>[];
  double line = kLine, scale = 1;

  /// Formato con el que sale lo próximo que se escribe en el cursor (negrita sin selección).
  RunStyle? pending;
  int _last = 0; // último párrafo con foco
  List<int>? _numbers;

  RichBody get body => block.body;

  void _setBody(RichBody b) {
    block.body = b;
    _numbers = null;
  }

  ParaLayout layoutFor(int i) {
    _numbers ??= body.numbering();
    final p = body.paras[min(i, body.paras.length - 1)];
    return paraLayout(p, _numbers![min(i, _numbers!.length - 1)], line, scale: scale);
  }

  // ---- campos ----
  ParaField _newField(int i) {
    final f = ParaField(RichController(this, i, body.paras[i].text), FocusNode());
    f.focus.addListener(() {
      if (f.focus.hasFocus) _last = f.ctl.index;
      onFocus();
    });
    return f;
  }

  void _disposeLater(Iterable<ParaField> fs) {
    final l = fs.toList();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final f in l) {
        f.ctl.dispose();
        f.focus.dispose();
      }
    });
  }

  void _rebuildFields() {
    _disposeLater(fields);
    fields.clear();
    _numbers = null;
    for (var i = 0; i < body.paras.length; i++) {
      fields.add(_newField(i));
    }
  }

  /// El modelo cambió desde afuera (deshacer, otro bloque): se alinea todo.
  void replaceModel(TextBlock t) {
    block = t;
    _numbers = null;
    pending = null;
    across = null;
    if (fields.length != body.paras.length) {
      _rebuildFields();
      onStructure();
    } else {
      _syncAll();
    }
  }

  void _syncAll() {
    for (var i = 0; i < fields.length; i++) {
      fields[i].ctl.index = i;
      fields[i].ctl.syncFromModel();
    }
  }

  bool get hasFocus => fields.any((f) => f.focus.hasFocus);

  /// Párrafo con foco (o el último que lo tuvo).
  int get active {
    final i = fields.indexWhere((f) => f.focus.hasFocus);
    return min(i >= 0 ? i : _last, fields.length - 1);
  }

  void dispose() {
    _holdTimer?.cancel();
    for (final f in fields) {
      f.ctl.dispose();
      f.focus.dispose();
    }
  }

  void focusAt(int para, int off) {
    para = para.clamp(0, fields.length - 1);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (para >= fields.length) return;
      final f = fields[para];
      final o = off.clamp(0, body.paras[para].length) + 1;
      f.ctl.setSilently(f.ctl.value.copyWith(selection: TextSelection.collapsed(offset: o)));
      f.focus.requestFocus();
    });
  }

  void focusEnd() => focusAt(fields.length - 1, body.paras.last.length);

  // ---- selección ----
  /// Rango local [inicio, fin] del párrafo [i] y su posición global.
  (int, int) _localSel(int i) {
    final s = fields[i].ctl.selection;
    final len = body.paras[i].length;
    if (!s.isValid) return (len, len);
    return ((s.start - 1).clamp(0, len), (s.end - 1).clamp(0, len));
  }

  (int, int) get globalSel {
    final x = across;
    if (x != null) return x;
    final i = active;
    final (a, b) = _localSel(i);
    return (body.globalOf(i, a), body.globalOf(i, b));
  }

  void selectionChanged() {
    pending = null;
    if (across != null && _pointer == null) {
      across = null; // tocó / movió el cursor: se termina la selección entre párrafos
      _syncAll();
    }
    onFocus();
  }

  // ---- selección entre párrafos ----
  // Cada párrafo es un TextField con su propia selección, así que la que cruza párrafos es un rango
  // global propio ([across]) que se arma mirando el dedo / mouse (mantener apretado y arrastrar, o
  // arrastrar con el mouse) y se pinta como fondo en los tramos. Mientras existe, formato, copiar,
  // cortar y borrar trabajan sobre ella (el modelo ya acepta rangos entre párrafos).

  /// Rango global ordenado [inicio, fin] de la selección que cruza párrafos; null si no hay.
  (int, int)? across;

  int? _pointer; // dedo / mouse apretado sobre el bloque
  bool _armed = false; // el dedo ya aguantó lo suficiente para que arrastrar seleccione
  Timer? _holdTimer;
  int? _anchor; // posición global donde empezó el arrastre

  /// Cuánto hay que mantener apretado (con dedo o lápiz) antes de que arrastrar seleccione.
  static const kHoldToSelect = Duration(milliseconds: 350);

  /// Rango local [inicio, fin) de la selección entre párrafos en el párrafo [i] (null si no lo toca).
  (int, int)? acrossLocal(int i) {
    final x = across;
    if (x == null) return null;
    final g = body.globalOf(i, 0), len = body.paras[i].length;
    final lo = max(x.$1, g) - g, hi = min(x.$2, g + len) - g;
    return hi > lo ? (lo, hi) : null;
  }

  /// Texto de la selección entre párrafos (párrafos separados por salto de línea).
  String? get acrossText {
    final x = across;
    return x == null ? null : body.plainText.substring(x.$1, x.$2);
  }

  /// Arma la selección entre párrafos entre las posiciones globales [a] y [b] (en cualquier orden).
  void selectAcross(int a, int b) {
    a = a.clamp(0, body.length);
    b = b.clamp(0, body.length);
    across = a == b ? null : (min(a, b), max(a, b));
    pending = null;
    _syncAll();
    onFocus();
  }

  /// Deja de haber selección entre párrafos.
  void clearAcross() {
    if (across == null) return;
    across = null;
    _syncAll();
    onFocus();
  }

  Future<void> copyAcross() async {
    final t = acrossText;
    if (t != null) await Clipboard.setData(ClipboardData(text: t));
  }

  Future<void> cutAcross() async {
    await copyAcross();
    deleteAcross();
  }

  /// Borra lo seleccionado entre párrafos (los de en medio desaparecen y los de las puntas se unen).
  void deleteAcross() {
    final x = across;
    if (x == null) return;
    across = null;
    final before = fields.length;
    _setBody(body.replaceRange(x.$1, x.$2, ''));
    _afterStructure(body.locate(x.$1).para, before, x.$1);
  }

  /// El punto [global] cae sobre alguno de los campos del bloque.
  bool containsGlobal(Offset global) {
    for (final f in fields) {
      final box = f.focus.context?.findRenderObject();
      if (box is RenderBox && box.attached && (box.localToGlobal(Offset.zero) & box.size).contains(global)) return true;
    }
    return false;
  }

  /// Párrafo cuyo campo cae en [global] (el de más abajo cuyo tope quedó por encima del punto).
  int _paraAt(Offset global) {
    var best = 0;
    for (var i = 0; i < fields.length; i++) {
      final box = fields[i].focus.context?.findRenderObject();
      if (box is RenderBox && box.attached && box.localToGlobal(Offset.zero).dy <= global.dy) best = i;
    }
    return best;
  }

  /// Posición global del carácter que está bajo [global] dentro del párrafo [i].
  int _globalAt(int i, Offset global) {
    final st = fields[i].focus.context?.findAncestorStateOfType<EditableTextState>();
    var off = body.paras[i].length;
    if (st != null) {
      off = (st.renderEditable.getPositionForPoint(global).offset - 1).clamp(0, body.paras[i].length);
    }
    return body.globalOf(i, off);
  }

  void pointerDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _anchor = null;
    // con el mouse arrastrar ya es seleccionar; con el dedo / lápiz hace falta mantener apretado
    _armed = e.kind == PointerDeviceKind.mouse;
    _holdTimer?.cancel();
    if (!_armed) _holdTimer = Timer(kHoldToSelect, () => _armed = true);
    if (across != null) {
      across = null; // un toque nuevo suelta la selección anterior
      _syncAll();
    }
    if (fields.isNotEmpty) _anchor = _globalAt(_paraAt(e.position), e.position);
  }

  void pointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || !_armed || _anchor == null || fields.length < 2) return;
    final i = _paraAt(e.position);
    // mientras no salga del párrafo de origen, el campo se arregla solo
    if (across == null && i == body.locate(_anchor!).para) return;
    selectAcross(_anchor!, _globalAt(i, e.position));
  }

  void pointerUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();
    final x = across;
    if (x == null) return;
    // el campo de origen quedó con su propia selección (y su menú nativo): se lo deja con el cursor
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (across != x) return;
      final l = body.locate(x.$1);
      final f = fields[l.para.clamp(0, fields.length - 1)];
      f.ctl.setSilently(f.ctl.value.copyWith(selection: TextSelection.collapsed(offset: l.offset + 1)));
    });
  }

  // ---- edición del usuario ----
  /// Una edición de [old] a [nv] en el campo [i]. Devuelve el valor a aplicar, o null si ya lo resolvió
  /// (partir con Enter, unir con retroceso).
  TextEditingValue? userEdit(int i, String old, TextEditingValue nv) {
    across = null;
    var text = nv.text;
    if (!text.startsWith(kGuide)) {
      if (old.length == 1 + text.length && old.substring(1) == text) {
        _backspaceAtStart(i); // se borró solo el guía: retroceso al principio
        _syncAll();
        return null;
      }
      text = kGuide + text; // se borró junto con otra cosa (seleccionar todo y escribir)
      nv = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: (nv.selection.extentOffset + 1).clamp(1, text.length)));
    }
    final o = old.substring(1), n = text.substring(1);
    var p = 0;
    while (p < o.length && p < n.length && o[p] == n[p]) {
      p++;
    }
    var s = 0;
    while (s < o.length - p && s < n.length - p && o[o.length - 1 - s] == n[n.length - 1 - s]) {
      s++;
    }
    final ins = n.substring(p, n.length - s);
    final from = body.globalOf(i, p), to = body.globalOf(i, o.length - s);
    if (ins.contains('\n')) {
      final before = fields.length;
      if (ins == '\n' && from == to) {
        final r = body.enter(from);
        _setBody(r.body);
        _afterStructure(i, before, r.caret);
      } else {
        _setBody(body.replaceRange(from, to, ins, style: pending));
        _afterStructure(i, before, from + ins.length);
      }
      pending = null;
      return null;
    }
    _setBody(body.replaceRange(from, to, ins, style: ins.isEmpty ? null : pending));
    if (ins.isNotEmpty) pending = null;
    onEdited();
    return nv;
  }

  void _backspaceAtStart(int i) {
    final before = fields.length;
    final r = body.backspaceAtStart(i);
    _setBody(r.body);
    _afterStructure(max(0, i - 1), before, r.caret);
  }

  /// Después de partir / unir párrafos: igualar la cantidad de campos, poner el cursor y avisar.
  void _afterStructure(int from, int before, int caretG) {
    final delta = body.paras.length - before;
    if (delta > 0) {
      for (var k = 0; k < delta; k++) {
        fields.insert(from + 1 + k, _newField(from + 1 + k));
      }
    } else if (delta < 0) {
      final gone = fields.sublist(from + 1, from + 1 - delta);
      fields.removeRange(from + 1, from + 1 - delta);
      _disposeLater(gone);
    }
    _numbers = null;
    _syncAll();
    final l = body.locate(caretG);
    focusAt(l.para, l.offset);
    onStructure();
    onEdited();
  }

  // ---- formato de carácter ----
  /// Formato del texto en el cursor / selección, para marcar los botones.
  bool fmtActive(Fmt f) {
    final (s, e) = globalSel;
    if (s != e) return body.allHave(s, e, f);
    return (pending ?? body.styleAt(s)).has(f);
  }

  int? get currentColor {
    final (s, e) = globalSel;
    return (pending ?? body.styleAt(s == e ? s : s + 1)).color;
  }

  int? get currentHighlight {
    final (s, e) = globalSel;
    return (pending ?? body.styleAt(s == e ? s : s + 1)).highlight;
  }

  void toggleFmt(Fmt f) {
    final (s, e) = globalSel;
    if (s == e) {
      pending = (pending ?? body.styleAt(s)).withFmt(f, !(pending ?? body.styleAt(s)).has(f));
      onFocus();
      return;
    }
    _apply(body.toggle(s, e, f));
  }

  void setColor(int? c) {
    final (s, e) = globalSel;
    if (s == e) {
      pending = (pending ?? body.styleAt(s)).withColor(c);
      onFocus();
      return;
    }
    _apply(body.setColor(s, e, c));
  }

  void setHighlight(int? c) {
    final (s, e) = globalSel;
    if (s == e) {
      pending = (pending ?? body.styleAt(s)).withHighlight(c);
      onFocus();
      return;
    }
    _apply(body.setHighlight(s, e, c));
  }

  // ---- formato de párrafo ----
  ParaStyle get paraStyle => body.paras[active].style;
  Para get activePara => body.paras[active];

  void setParaStyle(ParaStyle st) => _applyPara((s, e) => body.setParaStyle(s, e, st));
  void setList(ListKind k) => _applyPara((s, e) => body.setList(s, e, k));
  void setAlign(ParaAlign a) => _applyPara((s, e) => body.setAlign(s, e, a));
  void indentBy(int d) => _applyPara((s, e) => body.indent(s, e, d));

  void toggleChecked(int i) {
    _setBody(body.setChecked(i, !body.paras[i].checked));
    _syncAll();
    onStructure();
    onEdited();
  }

  void _applyPara(RichBody Function(int, int) f) {
    final (s, e) = globalSel;
    _apply(f(s, e));
    onStructure();
  }

  void _apply(RichBody b) {
    _setBody(b);
    _syncAll();
    onFocus();
    onEdited();
  }

  // ---- teclado de hardware ----
  /// Ctrl+B / I / U, Tab / Shift+Tab y flechas entre párrafos. true si se atendió la tecla.
  bool handleKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final k = e.logicalKey, hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    if (ctrl) {
      final f = k == LogicalKeyboardKey.keyB
          ? Fmt.bold
          : k == LogicalKeyboardKey.keyI
              ? Fmt.italic
              : k == LogicalKeyboardKey.keyU
                  ? Fmt.underline
                  : null;
      if (f == null) {
        if (across != null && k == LogicalKeyboardKey.keyC) {
          copyAcross();
          return true;
        }
        if (across != null && k == LogicalKeyboardKey.keyX) {
          cutAcross();
          return true;
        }
        return false;
      }
      toggleFmt(f);
      return true;
    }
    if (k == LogicalKeyboardKey.tab) {
      indentBy(hw.isShiftPressed ? -1 : 1);
      return true;
    }
    if (across != null && (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete)) {
      deleteAcross();
      return true;
    }
    final sel = fields[i].ctl.selection, len = fields[i].ctl.text.length;
    if (!sel.isCollapsed) return false;
    if ((k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp) && sel.extentOffset <= 1 && i > 0) {
      focusAt(i - 1, body.paras[i - 1].length);
      return true;
    }
    if ((k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown) &&
        sel.extentOffset >= len &&
        i < fields.length - 1) {
      focusAt(i + 1, 0);
      return true;
    }
    return false;
  }
}
