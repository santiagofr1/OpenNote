import 'dart:math';
import 'dart:ui';

// Medidas lógicas de la hoja. Se escala para entrar en pantalla, así se ve
// igual en cualquier dispositivo (tablet, PC).
const double kW = 1000, kSheetH = 1414, kLine = 40, kFont = 21;

// Entre hoja y hoja queda un espacio. Hoja + espacio = 1480, múltiplo de kLine,
// así los renglones de todas las hojas caen en la misma grilla.
const double kGap = 66, kSheetStep = kSheetH + kGap;
int sheetCount(double h) => max(1, ((h + kGap) / kSheetStep).round());
double heightFor(int sheets) => sheets * kSheetH + (sheets - 1) * kGap;

final _rnd = Random.secure();
String newId(String prefix) =>
    prefix + List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

Color parseColor(String s) => Color(int.parse(s.substring(1), radix: 16) | 0xFF000000);
double _r1(double v) => (v * 10).round() / 10;
double _num(dynamic v, [double d = 0]) => v is num ? v.toDouble() : d;

/// Trazo: puntos guardados planos como [x, y, presión, x, y, presión, ...]
class Stroke {
  // k = punta: pen | fountain | pencil | fine | calli | hl
  final String id, k, c;
  final double w, o; // grosor y opacidad (0..1)
  final List<double> pts;
  late final Color color = parseColor(c);
  Rect? _bounds;

  Stroke(this.id, this.k, this.c, this.w, this.pts, [this.o = 1]);

  void invalidate() => _bounds = null;

  int get n => pts.length ~/ 3;

  Rect get bounds {
    if (_bounds != null) return _bounds!;
    double x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (var i = 0; i < pts.length; i += 3) {
      x0 = min(x0, pts[i]);
      x1 = max(x1, pts[i]);
      y0 = min(y0, pts[i + 1]);
      y1 = max(y1, pts[i + 1]);
    }
    final r = w * 1.6;
    return _bounds = Rect.fromLTRB(x0 - r, y0 - r, x1 + r, y1 + r);
  }

  factory Stroke.fromJson(Map j) => Stroke(
        j['id'] as String,
        (j['k'] ?? 'pen') as String,
        (j['c'] ?? '#22211e') as String,
        _num(j['w'], 2),
        [
          for (final p in (j['pts'] as List))
            ...[_num(p[0]), _num(p[1]), (p as List).length > 2 ? _num(p[2], .5) : .5]
        ],
        _num(j['o'], 1),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': k,
        'c': c,
        'w': w,
        if (o < 1) 'o': (o * 100).round() / 100,
        'pts': [
          for (var i = 0; i < pts.length; i += 3)
            [_r1(pts[i]), _r1(pts[i + 1]), (pts[i + 2] * 100).round() / 100]
        ],
      };
}

class TextBlock {
  final String id;
  double x, y, w;
  String text;
  TextBlock(this.id, this.x, this.y, this.w, this.text);

  factory TextBlock.fromJson(Map j) =>
      TextBlock(j['id'] as String, _num(j['x']), _num(j['y']), _num(j['w'], 800), (j['text'] ?? '') as String);
  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y, 'w': w, 'text': text};
}

class PageData {
  final String id;
  int rev;
  double h;
  String bg; // lined | grid | dots | blank
  int updated; // ms epoch, para sincronizar algún día
  final Map<String, Stroke> strokes; // mantiene orden de inserción
  final Map<String, TextBlock> texts;

  PageData(this.id, {this.rev = 0, this.h = kSheetH, this.bg = 'lined', this.updated = 0, Map<String, Stroke>? strokes, Map<String, TextBlock>? texts})
      : strokes = strokes ?? {},
        texts = texts ?? {};

  factory PageData.fromJson(Map j) {
    final p = PageData._fromJson(j);
    if (((j['layout'] ?? 1) as int) < 2) p._addGaps();
    return p;
  }

  /// páginas viejas (hojas pegadas): corre todo para dejar el espacio entre hojas
  void _addGaps() {
    double shift(double y) => y + (y ~/ kSheetH) * kGap;
    for (final s in strokes.values) {
      for (var i = 1; i < s.pts.length; i += 3) {
        s.pts[i] = shift(s.pts[i]);
      }
      s.invalidate();
    }
    for (final t in texts.values) {
      t.y = shift(t.y);
    }
    h = heightFor((h / kSheetH).ceil());
  }

  factory PageData._fromJson(Map j) => PageData(
        j['id'] as String,
        rev: (j['rev'] ?? 0) as int,
        h: _num(j['h'], kSheetH),
        bg: (j['bg'] ?? 'lined') as String,
        updated: (j['updated'] ?? 0) as int,
        strokes: {for (final s in ((j['strokes'] ?? {}) as Map).values) (s['id'] as String): Stroke.fromJson(s as Map)},
        texts: {for (final t in ((j['texts'] ?? {}) as Map).values) (t['id'] as String): TextBlock.fromJson(t as Map)},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rev': rev,
        'h': h,
        'bg': bg,
        'updated': updated,
        'layout': 2,
        'strokes': {for (final s in strokes.values) s.id: s.toJson()},
        'texts': {for (final t in texts.values) t.id: t.toJson()},
      };
}

class PageRef {
  final String id;
  String title;
  PageRef(this.id, this.title);
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

class Notebook {
  final String id;
  String name;
  final List<PageRef> pages;
  int updated; // última edición (ms)
  String? last; // última página abierta
  Notebook(this.id, this.name, this.pages, {this.updated = 0, this.last});
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'updated': updated,
        'last': last,
        'pages': pages.map((p) => p.toJson()).toList(),
      };
}

class NotesIndex {
  int rev;
  String? last;
  final List<Notebook> notebooks;
  NotesIndex({this.rev = 0, this.last, List<Notebook>? notebooks}) : notebooks = notebooks ?? [];

  factory NotesIndex.fromJson(Map j) => NotesIndex(
        rev: (j['rev'] ?? 0) as int,
        last: j['last'] as String?,
        notebooks: [
          for (final n in (j['notebooks'] as List? ?? []))
            Notebook(
              n['id'] as String,
              n['name'] as String,
              [for (final p in (n['pages'] as List? ?? [])) PageRef(p['id'] as String, p['title'] as String)],
              updated: (n['updated'] ?? 0) as int,
              last: n['last'] as String?,
            )
        ],
      );
  Map<String, dynamic> toJson() => {'rev': rev, 'last': last, 'notebooks': notebooks.map((n) => n.toJson()).toList()};

  ({Notebook nb, PageRef page})? find(String? id) {
    for (final nb in notebooks) {
      for (final p in nb.pages) {
        if (p.id == id) return (nb: nb, page: p);
      }
    }
    return null;
  }
}
