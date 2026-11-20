import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Hoja nueva: al final de la página, tirar hacia arriba y mantener hasta que se llene el círculo.
class PullToAddSheet {
  PullToAddSheet({required TickerProvider vsync, required this.onComplete})
      : progress = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 750)) {
    progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _completed();
    });
  }

  final VoidCallback onComplete;
  final AnimationController progress;
  final justAdded = ValueNotifier(false); // muestra "Hoja agregada" un ratito
  double _pulled = 0;
  Timer? _reset;

  /// Va en un NotificationListener del scroll vertical. [touching]: hay algún dedo apoyado
  /// (el rebote de una fling no cuenta).
  bool onScroll(ScrollNotification n, {required bool touching}) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification && n.overscroll > 0 && n.dragDetails != null && touching) {
      _pulled += n.overscroll;
      if (_pulled > 28 && !progress.isAnimating && progress.value == 0) {
        HapticFeedback.selectionClick();
        progress.forward();
      }
    } else if (n is ScrollUpdateNotification && n.metrics.extentAfter > 4 && progress.value > 0 && !justAdded.value) {
      cancel(); // volvió a subir
    }
    return false;
  }

  /// Soltó (o empezó un pellizco) antes de completar: el círculo vuelve.
  void cancel() {
    _pulled = 0;
    if (progress.value > 0 && progress.value < 1) progress.reverse();
  }

  void _completed() {
    HapticFeedback.mediumImpact();
    justAdded.value = true;
    onComplete();
    _reset = Timer(const Duration(milliseconds: 900), () {
      progress.value = 0;
      _pulled = 0;
      justAdded.value = false;
    });
  }

  void dispose() {
    _reset?.cancel();
    progress.dispose();
    justAdded.dispose();
  }
}

/// Píldora con el círculo de progreso de [PullToAddSheet].
class PullIndicator extends StatelessWidget {
  final PullToAddSheet pull;
  const PullIndicator(this.pull, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([pull.progress, pull.justAdded]),
      builder: (context, _) {
        final done = pull.justAdded.value;
        final visible = pull.progress.value > 0 || done;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedScale(
              scale: visible ? 1 : .8,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutQuart,
              child: Material(
                color: cs.surfaceContainerHigh,
                elevation: 3,
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: done ? 1 : pull.progress.value,
                          strokeWidth: 3,
                          strokeCap: StrokeCap.round,
                          backgroundColor: cs.outlineVariant.withValues(alpha: .5),
                          color: cs.primary,
                        ),
                        Icon(done ? Symbols.check : Symbols.note_add, size: 18, weight: 400, color: cs.primary),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      done ? 'Hoja agregada' : 'Mantené para agregar una hoja',
                      style: TextStyle(color: cs.onSurface, fontSize: 14),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
