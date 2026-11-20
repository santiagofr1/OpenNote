import '../domain/domain.dart';

/// Una página del formato viejo (`pages/<id>.json`): varias hojas apiladas. Solo para migrar.
class LegacyPage {
  /// Versión del formato. 1: hojas pegadas; 2: con [kGap] entre hojas.
  static const layout = 2;

  final String id;
  double h;
  String bg, paper;
  final Map<String, Stroke> strokes;
  final Map<String, TextBlock> texts;
  final Map<String, Item> items;

  LegacyPage(this.id,
      {this.h = kSheetH, this.bg = 'lined', this.paper = '#fffefb', Map<String, Stroke>? strokes, Map<String, TextBlock>? texts, Map<String, Item>? items})
      : strokes = strokes ?? {},
        texts = texts ?? {},
        items = items ?? {};

  factory LegacyPage.fromJson(Map j) {
    final p = LegacyPage(
      j['id'] as String,
      h: jsonDouble(j['h'], kSheetH),
      bg: (j['bg'] ?? 'lined') as String,
      paper: (j['paper'] ?? '#fffefb') as String,
      items: {for (final i in ((j['items'] ?? {}) as Map).values) (i['id'] as String): Item.fromJson(i as Map)},
      strokes: {for (final s in ((j['strokes'] ?? {}) as Map).values) (s['id'] as String): Stroke.fromJson(s as Map)},
      texts: {for (final t in ((j['texts'] ?? {}) as Map).values) (t['id'] as String): TextBlock.fromJson(t as Map)},
    );
    if (((j['layout'] ?? 1) as int) < 2) p._addGaps();
    return p;
  }

  /// Páginas más viejas (hojas pegadas): corre todo para dejar el espacio entre hojas.
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
    for (final i in items.values) {
      i.y = shift(i.y);
    }
    h = heightFor((h / kSheetH).ceil());
  }
}
