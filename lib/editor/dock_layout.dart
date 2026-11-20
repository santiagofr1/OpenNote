import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Barra acoplable arriba / izquierda / derecha. Se mueve arrastrando su agarradera:
/// mientras tanto se resalta dónde va a quedar y una mini barra sigue al dedo.
class DockLayout extends StatefulWidget {
  final String dock; // top | left | right
  final bool hideToolbar; // modo lectura
  final Widget canvas;
  final Widget Function(bool vertical, Widget grip) toolbar;
  final ValueChanged<String> onDock;
  const DockLayout({
    super.key,
    required this.dock,
    required this.hideToolbar,
    required this.canvas,
    required this.toolbar,
    required this.onDock,
  });

  @override
  State<DockLayout> createState() => _DockLayoutState();
}

class _DockLayoutState extends State<DockLayout> {
  final _key = GlobalKey();
  String? _preview; // dónde quedaría si se suelta ahora
  Offset? _dragPos; // dónde está el dedo (coordenadas de este widget)

  RenderBox get _box => _key.currentContext!.findRenderObject() as RenderBox;

  String _dockFor(Offset global) {
    final p = _box.globalToLocal(global), s = _box.size;
    if (p.dy < s.height * .22 && p.dx > s.width * .2 && p.dx < s.width * .8) return 'top';
    return p.dx < s.width / 2 ? 'left' : 'right';
  }

  void _dragTo(Offset global) {
    final t = _dockFor(global);
    if (_preview != null && t != _preview) HapticFeedback.selectionClick();
    setState(() {
      _preview = t;
      _dragPos = _box.globalToLocal(global);
    });
  }

  void _endDrag({required bool drop}) {
    final t = _preview;
    setState(() {
      _preview = null;
      _dragPos = null;
    });
    if (drop && t != null) widget.onDock(t);
  }

  @override
  Widget build(BuildContext context) {
    final dock = widget.dock;
    // misma forma de árbol con y sin barra: así el lienzo no se reconstruye al entrar al modo lectura
    if (widget.hideToolbar) return Stack(key: _key, children: [Column(children: [Expanded(child: widget.canvas)])]);
    final bar = TweenAnimationBuilder<double>(
      key: ValueKey(dock),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutQuart,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: FractionalTranslation(
          translation: switch (dock) {
            'left' => Offset(-(1 - t) * .5, 0),
            'right' => Offset((1 - t) * .5, 0),
            _ => Offset(0, -(1 - t) * .5)
          },
          child: child,
        ),
      ),
      child: AnimatedOpacity(
        opacity: _preview != null ? .3 : 1,
        duration: const Duration(milliseconds: 150),
        child: widget.toolbar(dock != 'top', _grip(dock != 'top')),
      ),
    );
    final canvas = Expanded(child: widget.canvas);
    final body = dock == 'top'
        ? Column(children: [bar, canvas])
        : Row(children: dock == 'left' ? [bar, canvas] : [canvas, bar]);
    return Stack(key: _key, children: [
      body,
      if (_preview != null) Positioned.fill(child: IgnorePointer(child: _DockZone(_preview!))),
      if (_dragPos != null)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 60),
          left: _dragPos!.dx - (_preview == 'top' ? 120 : 30),
          top: _dragPos!.dy - (_preview == 'top' ? 30 : 110),
          child: IgnorePointer(child: _BarGhost(vertical: _preview != 'top')),
        ),
    ]);
  }

  /// Agarradera para mover la barra (arrastrala a un costado o arriba).
  Widget _grip(bool vertical) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Arrastrá para mover la barra',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          HapticFeedback.lightImpact();
          _dragTo(d.globalPosition);
        },
        onPanUpdate: (d) => _dragTo(d.globalPosition),
        onPanEnd: (_) => _endDrag(drop: true),
        onPanCancel: () => _endDrag(drop: false),
        child: SizedBox(
          width: vertical ? 60 : 26,
          height: vertical ? 26 : 56,
          child: RotatedBox(
            quarterTurns: vertical ? 1 : 0,
            child: Icon(Symbols.drag_indicator, size: 18, weight: 300, color: cs.onSurfaceVariant.withValues(alpha: .6)),
          ),
        ),
      ),
    );
  }
}

/// Mini barra que sigue al dedo mientras se mueve la barra.
class _BarGhost extends StatelessWidget {
  final bool vertical;
  const _BarGhost({required this.vertical});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Flex(direction: vertical ? Axis.vertical : Axis.horizontal, mainAxisSize: MainAxisSize.min, children: [
          for (final i in [Symbols.stylus, Symbols.ink_highlighter, Symbols.keyboard, Symbols.highlight_alt])
            Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 20, weight: 300, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Zona resaltada donde va a quedar la barra al soltarla.
class _DockZone extends StatelessWidget {
  final String dock;
  const _DockZone(this.dock);

  @override
  Widget build(BuildContext context) {
    final zone = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: switch (dock) {
        'top' => Align(alignment: Alignment.topCenter, child: SizedBox(height: 56, width: double.infinity, child: zone)),
        'left' => Align(alignment: Alignment.centerLeft, child: SizedBox(width: 64, height: double.infinity, child: zone)),
        _ => Align(alignment: Alignment.centerRight, child: SizedBox(width: 64, height: double.infinity, child: zone)),
      },
    );
  }
}
