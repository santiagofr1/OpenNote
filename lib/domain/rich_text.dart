/// Texto con formato tipo Word: párrafos con estilo, lista, sangría y alineación, hechos de tramos
/// ("runs") con negrita, cursiva, subrayado, tachado, color y resaltado. Todo puro e inmutable:
/// cada operación devuelve un [RichBody] nuevo. Los rangos son posiciones globales de caracteres,
/// contando un salto de línea entre párrafo y párrafo.
library;

enum ParaStyle { normal, title, subtitle }

enum ListKind { none, bullet, numbered, checklist }

enum ParaAlign { left, center, right, justify }

/// Formatos de carácter que se prenden y apagan.
enum Fmt { bold, italic, underline, strike }

/// Formato de un tramo de texto. Los colores son ARGB (null = el de la tinta / sin resaltado).
/// [size] es el tamaño de letra en puntos (null = automático: el que da el interlineado de la hoja).
class RunStyle {
  final bool bold, italic, underline, strike;
  final int? color, highlight;
  final double? size;
  const RunStyle(
      {this.bold = false, this.italic = false, this.underline = false, this.strike = false, this.color, this.highlight, this.size});

  static const plain = RunStyle();

  bool has(Fmt f) => switch (f) {
        Fmt.bold => bold,
        Fmt.italic => italic,
        Fmt.underline => underline,
        Fmt.strike => strike,
      };

  RunStyle withFmt(Fmt f, bool on) => RunStyle(
        bold: f == Fmt.bold ? on : bold,
        italic: f == Fmt.italic ? on : italic,
        underline: f == Fmt.underline ? on : underline,
        strike: f == Fmt.strike ? on : strike,
        color: color,
        highlight: highlight,
        size: size,
      );

  RunStyle withColor(int? c) =>
      RunStyle(bold: bold, italic: italic, underline: underline, strike: strike, color: c, highlight: highlight, size: size);
  RunStyle withHighlight(int? c) =>
      RunStyle(bold: bold, italic: italic, underline: underline, strike: strike, color: color, highlight: c, size: size);
  RunStyle withSize(double? pt) =>
      RunStyle(bold: bold, italic: italic, underline: underline, strike: strike, color: color, highlight: highlight, size: pt);

  @override
  bool operator ==(Object other) =>
      other is RunStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.color == color &&
      other.highlight == highlight &&
      other.size == size;
  @override
  int get hashCode => Object.hash(bold, italic, underline, strike, color, highlight, size);
}

/// Tramo de texto con un solo formato.
class Run {
  final String text;
  final RunStyle style;
  const Run(this.text, [this.style = RunStyle.plain]);

  @override
  bool operator ==(Object other) => other is Run && other.text == text && other.style == style;
  @override
  int get hashCode => Object.hash(text, style);

  Map<String, dynamic> toJson() => {
        't': text,
        if (style.bold) 'b': 1,
        if (style.italic) 'i': 1,
        if (style.underline) 'u': 1,
        if (style.strike) 'k': 1,
        if (style.color != null) 'c': style.color,
        if (style.highlight != null) 'h': style.highlight,
        if (style.size != null) 'size': style.size,
      };

  factory Run.fromJson(Map j) => Run(
      (j['t'] ?? '') as String,
      RunStyle(
        bold: j['b'] != null,
        italic: j['i'] != null,
        underline: j['u'] != null,
        strike: j['k'] != null,
        color: (j['c'] as num?)?.toInt(),
        highlight: (j['h'] as num?)?.toInt(),
        size: (j['size'] as num?)?.toDouble(),
      ));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Junta tramos vecinos con el mismo formato y saca los vacíos. Un párrafo sin texto conserva
/// (si no es el formato común) un tramo vacío: es el formato con el que se sigue escribiendo.
List<Run> _normalize(Iterable<Run> runs) {
  final out = <Run>[];
  var emptyStyle = RunStyle.plain;
  for (final r in runs) {
    if (r.text.isEmpty) {
      emptyStyle = r.style;
      continue;
    }
    if (out.isNotEmpty && out.last.style == r.style) {
      out[out.length - 1] = Run(out.last.text + r.text, r.style);
    } else {
      out.add(r);
    }
  }
  if (out.isEmpty && emptyStyle != RunStyle.plain) out.add(Run('', emptyStyle));
  return out;
}

/// Un párrafo: tramos + atributos de párrafo.
class Para {
  final List<Run> runs;
  final ParaStyle style;
  final ListKind list;
  final bool checked; // solo en listas de tareas
  final int indent; // 0..kMaxIndent
  final ParaAlign align;
  Para(Iterable<Run> runs,
      {this.style = ParaStyle.normal, this.list = ListKind.none, this.checked = false, int indent = 0, this.align = ParaAlign.left})
      : runs = List.unmodifiable(_normalize(runs)),
        indent = indent.clamp(0, kMaxIndent);

  static const kMaxIndent = 4;

  String get text => runs.map((r) => r.text).join();
  int get length => runs.fold(0, (n, r) => n + r.text.length);
  bool get isEmpty => length == 0;

  Para copyWith({Iterable<Run>? runs, ParaStyle? style, ListKind? list, bool? checked, int? indent, ParaAlign? align}) => Para(
        runs ?? this.runs,
        style: style ?? this.style,
        list: list ?? this.list,
        checked: checked ?? this.checked,
        indent: indent ?? this.indent,
        align: align ?? this.align,
      );

  /// Tramos del rango local [s, e).
  List<Run> slice(int s, int e) {
    final out = <Run>[];
    var pos = 0;
    for (final r in runs) {
      final a = pos, b = pos + r.text.length;
      pos = b;
      final from = s > a ? s : a, to = e < b ? e : b;
      if (from < to) out.add(Run(r.text.substring(from - a, to - a), r.style));
    }
    return out;
  }

  /// Formato del carácter anterior a [off] (o el primero, al principio del párrafo).
  RunStyle styleAt(int off) {
    if (length == 0) return runs.isEmpty ? RunStyle.plain : runs.first.style;
    var pos = 0;
    final want = off <= 0 ? 0 : off - 1;
    for (final r in runs) {
      pos += r.text.length;
      if (want < pos) return r.style;
    }
    return runs.last.style;
  }

  @override
  bool operator ==(Object other) =>
      other is Para &&
      other.style == style &&
      other.list == list &&
      other.checked == checked &&
      other.indent == indent &&
      other.align == align &&
      _listEq(other.runs, runs);
  @override
  int get hashCode => Object.hash(style, list, checked, indent, align, Object.hashAll(runs));

  bool get isDefault => style == ParaStyle.normal && list == ListKind.none && indent == 0 && align == ParaAlign.left;

  Map<String, dynamic> toJson() => {
        if (style != ParaStyle.normal) 'style': style.name,
        if (list != ListKind.none) 'list': list.name,
        if (checked) 'checked': true,
        if (indent > 0) 'indent': indent,
        if (align != ParaAlign.left) 'align': align.name,
        'runs': [for (final r in runs) r.toJson()],
      };

  factory Para.fromJson(Map j) => Para(
        [for (final r in (j['runs'] as List? ?? [])) Run.fromJson(r as Map)],
        style: _enum(ParaStyle.values, j['style'], ParaStyle.normal),
        list: _enum(ListKind.values, j['list'], ListKind.none),
        checked: j['checked'] == true,
        indent: (j['indent'] as num?)?.toInt() ?? 0,
        align: _enum(ParaAlign.values, j['align'], ParaAlign.left),
      );
}

T _enum<T extends Enum>(List<T> values, Object? name, T d) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return d;
}

/// Contenido de un bloque de texto: uno o más párrafos.
class RichBody {
  final List<Para> paras;
  RichBody(Iterable<Para> paras) : paras = List.unmodifiable(paras.isEmpty ? [Para(const [])] : paras);

  /// Texto sin formato: un párrafo normal por cada línea (así se cargan los textos viejos).
  factory RichBody.plain(String s) => RichBody([for (final l in s.split('\n')) Para(l.isEmpty ? const [] : [Run(l)])]);

  String get plainText => paras.map((p) => p.text).join('\n');
  int get length => paras.fold(0, (n, p) => n + p.length) + paras.length - 1;
  bool get isBlank => paras.every((p) => p.text.trim().isEmpty);

  /// Sin ningún formato (solo texto): se guarda como antes.
  bool get isPlain =>
      paras.every((p) => p.isDefault && p.runs.every((r) => r.style == RunStyle.plain));

  @override
  bool operator ==(Object other) => other is RichBody && _listEq(other.paras, paras);
  @override
  int get hashCode => Object.hashAll(paras);

  // ---- posiciones ----
  /// Posición global del carácter [off] del párrafo [para].
  int globalOf(int para, int off) {
    var g = 0;
    for (var i = 0; i < para; i++) {
      g += paras[i].length + 1;
    }
    return g + off;
  }

  /// Párrafo y posición local de la posición global [g] (se acota al texto).
  ({int para, int offset}) locate(int g) {
    var left = g.clamp(0, length);
    for (var i = 0; i < paras.length; i++) {
      final n = paras[i].length;
      if (left <= n) return (para: i, offset: left);
      left -= n + 1;
    }
    return (para: paras.length - 1, offset: paras.last.length);
  }

  /// Formato con el que se escribe en [g]: el del carácter anterior.
  RunStyle styleAt(int g) {
    final l = locate(g);
    return paras[l.para].styleAt(l.offset);
  }

  /// Párrafos que toca el rango [s, e] (uno solo si está colapsado). Un rango que termina justo
  /// al principio de un párrafo no lo incluye.
  (int, int) parasIn(int s, int e) {
    if (e < s) (s, e) = (e, s);
    final a = locate(s), b = locate(e);
    final last = (e > s && b.offset == 0 && b.para > a.para) ? b.para - 1 : b.para;
    return (a.para, last);
  }

  // ---- formato de carácter ----
  /// Todo el rango [s, e) tiene el formato [f].
  bool allHave(int s, int e, Fmt f) {
    var any = false;
    var ok = true;
    _eachRun(s, e, (p, st) {
      any = true;
      if (!st.has(f)) ok = false;
    });
    return any && ok;
  }

  void _eachRun(int s, int e, void Function(int para, RunStyle st) fn) {
    var base = 0;
    for (var i = 0; i < paras.length; i++) {
      var pos = base;
      for (final r in paras[i].runs) {
        final a = pos, b = pos + r.text.length;
        pos = b;
        if (r.text.isNotEmpty && a < e && b > s) fn(i, r.style);
      }
      base += paras[i].length + 1;
    }
  }

  /// Prende [f] en el rango [s, e); si ya estaba todo prendido, lo apaga.
  RichBody toggle(int s, int e, Fmt f) {
    final on = !allHave(s, e, f);
    return mapRuns(s, e, (st) => st.withFmt(f, on));
  }

  RichBody setColor(int s, int e, int? color) => mapRuns(s, e, (st) => st.withColor(color));
  RichBody setHighlight(int s, int e, int? color) => mapRuns(s, e, (st) => st.withHighlight(color));
  RichBody setSize(int s, int e, double? pt) => mapRuns(s, e, (st) => st.withSize(pt));

  /// Tamaño común (en pt) de los caracteres de [s, e); null si es automático o si hay mezcla.
  double? commonSize(int s, int e) {
    double? size;
    var first = true, mixed = false;
    _eachRun(s, e, (_, st) {
      if (first) {
        size = st.size;
        first = false;
      } else if (st.size != size) {
        mixed = true;
      }
    });
    return mixed ? null : size;
  }

  /// Cambia el formato de todos los caracteres de [s, e).
  RichBody mapRuns(int s, int e, RunStyle Function(RunStyle) fn) {
    if (e < s) (s, e) = (e, s);
    if (s == e) return this;
    var base = 0;
    final out = <Para>[];
    for (final p in paras) {
      final len = p.length;
      final from = (s - base).clamp(0, len), to = (e - base).clamp(0, len);
      if (from < to) {
        out.add(p.copyWith(runs: [
          ...p.slice(0, from),
          for (final r in p.slice(from, to)) Run(r.text, fn(r.style)),
          ...p.slice(to, len),
        ]));
      } else {
        out.add(p);
      }
      base += len + 1;
    }
    return RichBody(out);
  }

  // ---- formato de párrafo ----
  RichBody mapParas(int s, int e, Para Function(Para) fn) {
    final (a, b) = parasIn(s, e);
    return RichBody([for (var i = 0; i < paras.length; i++) i >= a && i <= b ? fn(paras[i]) : paras[i]]);
  }

  RichBody setParaStyle(int s, int e, ParaStyle st) => mapParas(s, e, (p) => p.copyWith(style: st));
  RichBody setAlign(int s, int e, ParaAlign a) => mapParas(s, e, (p) => p.copyWith(align: a));

  /// Pone el tipo de lista; si todos ya la tienen, la saca.
  RichBody setList(int s, int e, ListKind k) {
    final (a, b) = parasIn(s, e);
    final all = [for (var i = a; i <= b; i++) paras[i]].every((p) => p.list == k);
    return mapParas(s, e, (p) => p.copyWith(list: all ? ListKind.none : k, checked: false));
  }

  RichBody setChecked(int para, bool v) =>
      RichBody([for (var i = 0; i < paras.length; i++) i == para ? paras[i].copyWith(checked: v) : paras[i]]);

  RichBody indent(int s, int e, int delta) => mapParas(s, e, (p) => p.copyWith(indent: p.indent + delta));

  // ---- edición ----
  /// Reemplaza [s, e) por [text] (puede traer '\n'). Lo escrito toma [style], o el del texto de al lado.
  RichBody replaceRange(int s, int e, String text, {RunStyle? style}) {
    if (e < s) (s, e) = (e, s);
    s = s.clamp(0, length);
    e = e.clamp(0, length);
    final a = locate(s), b = locate(e);
    final pa = paras[a.para], pb = paras[b.para];
    final st = style ?? ((s < e && a.offset < pa.length) ? pa.styleAt(a.offset + 1) : pa.styleAt(a.offset));
    final lines = text.split('\n');
    final head = pa.slice(0, a.offset), tail = pb.slice(b.offset, pb.length);
    final out = <Para>[...paras.sublist(0, a.para)];
    for (var i = 0; i < lines.length; i++) {
      final runs = <Run>[
        if (i == 0) ...head,
        if (lines[i].isNotEmpty) Run(lines[i], st) else if (lines.length == 1 && head.isEmpty && tail.isEmpty) Run('', st),
        if (i == lines.length - 1) ...tail,
      ];
      out.add(i == 0 ? pa.copyWith(runs: runs) : pa.copyWith(runs: runs, checked: false));
    }
    out.addAll(paras.sublist(b.para + 1));
    return RichBody(out);
  }

  /// Enter en [g]. En un renglón de lista vacío termina la lista en vez de partir. Al partir al final
  /// de un título, el párrafo nuevo vuelve a ser normal. [caret] es la posición global resultante.
  ({RichBody body, int caret}) enter(int g) {
    final l = locate(g), p = paras[l.para];
    if (p.isEmpty && p.list != ListKind.none) {
      return (body: mapParas(g, g, (q) => q.copyWith(list: ListKind.none, indent: 0, checked: false)), caret: g);
    }
    var r = replaceRange(g, g, '\n');
    if (p.style != ParaStyle.normal && l.offset == p.length) {
      r = r.mapParas(g + 1, g + 1, (q) => q.copyWith(style: ParaStyle.normal));
    }
    return (body: r, caret: g + 1);
  }

  /// Retroceso al principio del párrafo [para]: primero saca la lista / sangría; si no, se une con el anterior.
  ({RichBody body, int caret}) backspaceAtStart(int para) {
    final g = globalOf(para, 0), p = paras[para];
    if (p.list != ListKind.none || p.indent > 0) {
      return (body: mapParas(g, g, (q) => q.copyWith(list: ListKind.none, indent: 0, checked: false)), caret: g);
    }
    if (para == 0) return (body: this, caret: 0);
    return (body: replaceRange(g - 1, g, ''), caret: g - 1);
  }

  // ---- listas ----
  /// Número de cada párrafo numerado (0 en los demás). La cuenta sigue entre renglones del mismo nivel,
  /// se reinicia al salir a un nivel menor y la corta un párrafo que no es numerado de ese nivel.
  List<int> numbering() {
    final counters = List<int>.filled(Para.kMaxIndent + 1, 0);
    final out = <int>[];
    for (final p in paras) {
      for (var i = p.indent + 1; i <= Para.kMaxIndent; i++) {
        counters[i] = 0;
      }
      if (p.list == ListKind.numbered) {
        counters[p.indent]++;
        out.add(counters[p.indent]);
      } else {
        counters[p.indent] = 0;
        out.add(0);
      }
    }
    return out;
  }

  // ---- JSON ----
  List<Map<String, dynamic>> toJson() => [for (final p in paras) p.toJson()];
  factory RichBody.fromJson(List j) => RichBody([for (final p in j) Para.fromJson(p as Map)]);
}
