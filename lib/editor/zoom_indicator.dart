import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../l10n/l10n.dart';

/// Píldora "150% · fijo" que aparece arriba mientras cambia el zoom.
class ZoomIndicator extends StatelessWidget {
  final bool visible, locked;
  final double zoom;
  const ZoomIndicator({super.key, required this.visible, required this.zoom, required this.locked});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Material(
          color: cs.inverseSurface.withValues(alpha: .88),
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(locked ? Symbols.lock : Symbols.zoom_in, size: 16, weight: 400, color: cs.onInverseSurface),
              const SizedBox(width: 6),
              Text(
                locked ? context.l10n.zoomIndicatorLocked((zoom * 100).round()) : context.l10n.zoomIndicator((zoom * 100).round()),
                style: TextStyle(
                    color: cs.onInverseSurface, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
