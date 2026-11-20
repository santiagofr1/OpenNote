import 'dart:math';

import 'package:flutter/material.dart';

import 'model.dart';
import 'painters.dart';

const kAccent = Color(0xFF2F5BD3);
const kPanel = Color(0xFFF6F5F1);
const kDesk = Color(0xFFECEBE6);
const kText = Color(0xFF22211E);
const kMuted = Color(0xFF7A776E);

enum Tool { pen, hl, text, select }

const tips = [
  ('pen', 'Bolígrafo'),
  ('fountain', 'Pluma'),
  ('pencil', 'Lápiz'),
  ('fine', 'Fibra'),
  ('calli', 'Caligrafía'),
];
const eraserSizes = [8.0, 16.0, 30.0];

/// Paleta: grises + 10 familias de color en 4 tonos (oscuro → claro)
const palette = [
  '#000000', '#22211e', '#4b4a46', '#7a776e', '#a8a59c', '#d4d1c8', '#ffffff',
  '#7f1d1d', '#b91c1c', '#ef4444', '#fca5a5',
  '#7c2d12', '#c2410c', '#f97316', '#fdba74',
  '#713f12', '#ca8a04', '#facc15', '#fde68a',
  '#14532d', '#15803d', '#22c55e', '#86efac',
  '#134e4a', '#0f766e', '#14b8a6', '#5eead4',
  '#1e3a8a', '#1d4ed8', '#3b82f6', '#93c5fd',
  '#312e81', '#4338ca', '#6366f1', '#a5b4fc',
  '#581c87', '#7e22ce', '#a855f7', '#d8b4fe',
  '#831843', '#be185d', '#ec4899', '#f9a8d4',
  '#3f2a1d', '#7c5a3c', '#a47551', '#d6b896',
];
const hlPalette = ['#f7d22c', '#ffb347', '#5ee08a', '#5bc8ff', '#ff86c8', '#c79bff', '#ff6b6b', '#b8f35d'];

class PenPreset {
  String tip, color;
  double width, opacity;
  PenPreset(this.tip, this.color, this.width, this.opacity);
  Map<String, dynamic> toJson() => {'tip': tip, 'color': color, 'width': width, 'opacity': opacity};
  void load(Map? j) {
    if (j == null) return;
    tip = (j['tip'] ?? tip) as String;
    color = (j['color'] ?? color) as String;
    width = ((j['width'] ?? width) as num).toDouble();
    opacity = ((j['opacity'] ?? opacity) as num).toDouble();
  }
}

/// Herramientas elegidas (se guardan en prefs.json)
class ToolState {
  Tool tool = Tool.pen;
  final pen = PenPreset('pen', '#22211e', 2.6, 1);
  final hl = PenPreset('hl', '#f7d22c', 22, .4);
  List<String> penRecent = ['#22211e', '#1d4ed8', '#b91c1c', '#15803d', '#c2410c', '#7e22ce'];
  List<String> hlRecent = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
  int eraserSize = 1;

  // portapapeles de la selección (sirve entre páginas)
  List<Stroke> clipStrokes = [];
  List<TextBlock> clipTexts = [];
  bool get hasClip => clipStrokes.isNotEmpty || clipTexts.isNotEmpty;

  PenPreset get current => tool == Tool.hl ? hl : pen;
  List<String> get recent => tool == Tool.hl ? hlRecent : penRecent;

  void pickColor(String c) {
    current.color = c;
    final r = recent..remove(c);
    r.insert(0, c);
    if (r.length > 7) r.removeLast();
  }

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'pen': pen.toJson(),
        'hl': hl.toJson(),
        'penRecent': penRecent,
        'hlRecent': hlRecent,
        'eraserSize': eraserSize,
      };

  void load(Map? j) {
    if (j == null) return;
    tool = Tool.values.firstWhere((t) => t.name == j['tool'], orElse: () => Tool.pen);
    pen.load(j['pen'] as Map?);
    hl.load(j['hl'] as Map?);
    if (j['penRecent'] is List) penRecent = List<String>.from(j['penRecent'] as List);
    if (j['hlRecent'] is List) hlRecent = List<String>.from(j['hlRecent'] as List);
    eraserSize = ((j['eraserSize'] ?? 1) as int).clamp(0, 2);
  }
}

/// Trazo de muestra (una ola con presión variable) para previsualizar una punta.
Stroke sampleStroke(String tip, String color, double w, double o, Size size) {
  final pts = <double>[];
  const n = 60;
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    final x = 8 + t * (size.width - 16);
    final y = size.height / 2 + sin(t * pi * 2) * size.height * .28;
    pts.addAll([x, y, .25 + .7 * sin(t * pi)]);
  }
  return Stroke('preview', tip, color, w, pts, o);
}

class _SamplePainter extends CustomPainter {
  final String tip, color;
  final double w, o;
  _SamplePainter(this.tip, this.color, this.w, this.o);
  @override
  void paint(Canvas c, Size size) => paintStroke(c, sampleStroke(tip, color, w, o, size));
  @override
  bool shouldRepaint(_SamplePainter x) => x.tip != tip || x.color != color || x.w != w || x.o != o;
}

Future<void> showPenPanel(BuildContext context, ToolState ts, VoidCallback onChange) {
  return showDialog(
    context: context,
    barrierColor: Colors.black12,
    builder: (ctx) => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 64),
        child: Material(
          color: kPanel,
          elevation: 12,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(ctx).size.height - 90),
            child: _PenPanel(ts: ts, onChange: onChange),
          ),
        ),
      ),
    ),
  );
}

class _PenPanel extends StatefulWidget {
  final ToolState ts;
  final VoidCallback onChange;
  const _PenPanel({required this.ts, required this.onChange});
  @override
  State<_PenPanel> createState() => _PenPanelState();
}

class _PenPanelState extends State<_PenPanel> {
  ToolState get ts => widget.ts;
  bool custom = false;
  late HSVColor hsv = HSVColor.fromColor(parseColor(ts.current.color));

  bool get isHl => ts.tool == Tool.hl;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = ts.current;
    final minW = isHl ? 6.0 : .6, maxW = isHl ? 60.0 : 16.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isHl ? 'Resaltador' : 'Lápiz', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        if (!isHl) ...[
          _label('Punta'),
          Row(children: [
            for (final (id, name) in tips)
              Expanded(
                child: GestureDetector(
                  onTap: () => _set(() => p.tip = id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: p.tip == id ? Colors.white : const Color(0x08000000),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.tip == id ? kAccent : Colors.transparent, width: 1.5),
                    ),
                    child: Column(children: [
                      SizedBox(
                        height: 34,
                        width: double.infinity,
                        child: CustomPaint(painter: _SamplePainter(id, p.color, id == 'fine' ? 2.5 : 3.2, 1)),
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: TextStyle(fontSize: 11.5, color: p.tip == id ? kAccent : kText), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 14),
        ],

        // vista previa con los valores actuales
        Container(
          height: 64,
          decoration: BoxDecoration(color: const Color(0xFFFFFEFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCD9D0))),
          child: CustomPaint(painter: _SamplePainter(p.tip, p.color, p.width, p.opacity), size: Size.infinite),
        ),
        const SizedBox(height: 10),

        _sliderRow('Grosor', p.width.toStringAsFixed(p.width < 10 ? 1 : 0), Slider(
          value: p.width.clamp(minW, maxW),
          min: minW,
          max: maxW,
          onChanged: (v) => _set(() => p.width = (v * 10).round() / 10),
        )),
        _sliderRow('Opacidad', '${(p.opacity * 100).round()}%', Slider(
          value: p.opacity,
          min: .1,
          max: 1,
          onChanged: (v) => _set(() => p.opacity = (v * 100).round() / 100),
        )),
        const SizedBox(height: 6),

        _label('Color'),
        if (isHl)
          Wrap(spacing: 6, runSpacing: 6, children: [for (final c in hlPalette) _swatch(c, c == p.color)])
        else ...[
          // grises arriba; abajo cada columna es una familia, de oscuro a claro
          Wrap(spacing: 6, children: [for (final c in palette.take(7)) _swatch(c, c == p.color)]),
          const SizedBox(height: 8),
          for (var tone = 0; tone < 4; tone++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, children: [
                for (var fam = 0; fam < 10; fam++) _swatch(palette[7 + fam * 4 + tone], palette[7 + fam * 4 + tone] == p.color),
              ]),
            ),
        ],
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => setState(() {
            custom = !custom;
            hsv = HSVColor.fromColor(parseColor(p.color));
          }),
          icon: Icon(custom ? Icons.expand_less : Icons.palette_outlined, size: 18),
          label: const Text('Color personalizado'),
        ),
        if (custom) ...[
          _GradientBar(
            colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
            value: hsv.hue / 360,
            onChanged: (v) => _custom(hsv.withHue(v * 360)),
          ),
          const SizedBox(height: 10),
          _GradientBar(
            colors: [hsv.withSaturation(0).toColor(), hsv.withSaturation(1).toColor()],
            value: hsv.saturation,
            onChanged: (v) => _custom(hsv.withSaturation(v)),
          ),
          const SizedBox(height: 10),
          _GradientBar(
            colors: [Colors.black, hsv.withValue(1).toColor()],
            value: hsv.value,
            onChanged: (v) => _custom(hsv.withValue(v)),
          ),
        ],

        if (!isHl) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _label('Goma (apretá el botón del lápiz)'),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(['Chica', 'Mediana', 'Grande'][i]),
                  selected: ts.eraserSize == i,
                  onSelected: (_) => _set(() => ts.eraserSize = i),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  void _custom(HSVColor c) {
    setState(() => hsv = c);
    final hex = _hex(c.toColor());
    _set(() => ts.current.color = hex);
  }

  @override
  void dispose() {
    // el color personalizado entra a "recientes" al cerrar
    ts.pickColor(ts.current.color);
    widget.onChange();
    super.dispose();
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w600)),
      );

  Widget _sliderRow(String label, String value, Widget slider) => Row(children: [
        SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w600))),
        Expanded(child: slider),
        SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
      ]);

  Widget _swatch(String c, bool on) => GestureDetector(
        onTap: () => _set(() {
          ts.pickColor(c);
          hsv = HSVColor.fromColor(parseColor(c));
        }),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: parseColor(c),
            shape: BoxShape.circle,
            border: Border.all(color: on ? Colors.white : const Color(0x22000000), width: on ? 3 : 1),
            boxShadow: on ? const [BoxShadow(color: kAccent, spreadRadius: 2)] : null,
          ),
        ),
      );
}

/// Barra con degradé que se arrastra (para tono, saturación, brillo)
class _GradientBar extends StatelessWidget {
  final List<Color> colors;
  final double value;
  final ValueChanged<double> onChanged;
  const _GradientBar({required this.colors, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      void at(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0));
      return GestureDetector(
        onTapDown: (d) => at(d.localPosition),
        onHorizontalDragUpdate: (d) => at(d.localPosition),
        child: SizedBox(
          height: 30,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
            Container(
              height: 22,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), gradient: LinearGradient(colors: colors)),
            ),
            Positioned(
              left: (value * w - 13).clamp(-2.0, w - 24),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
