import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';

/// Lo que se arrastra en la biblioteca: un cuaderno o una carpeta.
class LibraryDrag {
  final Notebook? nb;
  final Folder? folder;
  const LibraryDrag.notebook(Notebook this.nb) : folder = null;
  const LibraryDrag.folder(Folder this.folder) : nb = null;

  String get name => nb?.name ?? folder!.name;
  String get id => nb?.id ?? folder!.id;

  /// Carpeta donde está ahora (null = inicio).
  String? get parent => nb != null ? nb!.folder : folder!.parent;

  /// Se puede soltar en [target] (null = inicio): no donde ya está, y una carpeta tampoco adentro
  /// de sí misma ni de una descendiente.
  bool canDropOn(NotesIndex idx, String? target) {
    if (target == parent) return false;
    final f = folder;
    if (f == null) return true;
    return target != f.id && (target == null || !idx.descendantIds(f.id).contains(target));
  }
}

/// Más que esto (px) hay que mover el dedo, ya mantenido, para que sea arrastrar y no "abrir el menú".
const kDragSlop = 10.0;

/// Envuelve una tarjeta: a los 500 ms de mantener apretado llama a [onHold] (abre el menú de opciones, anclado
/// a la tarjeta, mientras el dedo sigue apoyado). Si después el dedo se mueve más de [kDragSlop] llama a
/// [onHoldCancel] (cierra el menú) y la tarjeta se arrastra; si suelta sin mover, el menú queda abierto.
/// Antes de los 500 ms, mover es scroll. [onMove] avisa dónde está el dedo (para el scroll automático) y
/// [onEnd] cuando se suelta.
class DragSource extends StatefulWidget {
  final LibraryDrag data;
  final Widget child;
  final void Function(BuildContext card) onHold;
  final VoidCallback? onHoldCancel;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onEnd;
  const DragSource(
      {super.key, required this.data, required this.child, required this.onHold, this.onHoldCancel, this.onMove, this.onEnd});

  @override
  State<DragSource> createState() => _DragSourceState();
}

class _DragSourceState extends State<DragSource> {
  Offset _down = Offset.zero;
  final _moved = ValueNotifier(false); // ya se movió más que el umbral: recién ahí se ve la tarjeta que viaja

  @override
  void dispose() {
    _moved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // clic derecho (PC): el mismo menú que mantener apretado
    return GestureDetector(
      onSecondaryTapUp: (_) => widget.onHold(context),
      child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _down = e.position,
      child: LongPressDraggable<LibraryDrag>(
        data: widget.data,
        dragAnchorStrategy: (_, _, _) => const Offset(90, 26), // el dedo en el centro de la tarjeta que viaja
        onDragStarted: () {
          _moved.value = false;
          widget.onHold(context);
        },
        onDragUpdate: (d) {
          if (!_moved.value && (d.globalPosition - _down).distance > kDragSlop) {
            _moved.value = true;
            widget.onHoldCancel?.call();
          }
          widget.onMove?.call(d.globalPosition);
        },
        onDragEnd: (_) {
          _moved.value = false;
          widget.onEnd?.call();
        },
        feedback: ValueListenableBuilder<bool>(
          valueListenable: _moved,
          builder: (_, moved, _) => AnimatedOpacity(
            opacity: moved ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Material(
              elevation: 8,
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 180,
                height: 52,
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(widget.data.folder != null ? Symbols.folder : Symbols.menu_book, fill: 1, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.data.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
          ),
        ),
        childWhenDragging: ValueListenableBuilder<bool>(
          valueListenable: _moved,
          builder: (_, moved, c) => Opacity(opacity: moved ? .35 : 1, child: c),
          child: widget.child,
        ),
        child: widget.child,
      ),
      ),
    );
  }
}

/// Zona donde se puede soltar lo arrastrado: [onDrop] recibe lo soltado; [builder] sabe si hay algo encima
/// que sí se aceptaría (para resaltar el destino).
class DropZone extends StatelessWidget {
  final bool Function(LibraryDrag) accepts;
  final ValueChanged<LibraryDrag> onDrop;
  final Widget Function(BuildContext, bool hovering) builder;
  const DropZone({super.key, required this.accepts, required this.onDrop, required this.builder});

  @override
  Widget build(BuildContext context) => DragTarget<LibraryDrag>(
        onWillAcceptWithDetails: (d) => accepts(d.data),
        onAcceptWithDetails: (d) => onDrop(d.data),
        builder: (ctx, candidates, _) => builder(ctx, candidates.isNotEmpty),
      );
}

/// Scroll automático mientras se arrastra cerca del borde de arriba o de abajo de la lista.
class AutoScroller {
  AutoScroller(this.controller, this.viewport);
  final ScrollController controller;

  /// Caja de la lista que se desplaza (para saber dónde están sus bordes).
  final GlobalKey viewport;

  /// Franja (px) de cada borde donde empieza a moverse, y velocidad máxima (px por cuadro de 16 ms).
  static const edge = 90.0, maxSpeed = 18.0;

  Timer? _timer;
  Offset? _pos;

  /// Velocidad con signo para un dedo a [y] px del tope de una lista de alto [h]: negativa sube, positiva baja.
  static double speedFor(double y, double h) {
    if (y < edge) return -maxSpeed * min(1.0, (edge - y) / edge);
    if (y > h - edge) return maxSpeed * min(1.0, (y - (h - edge)) / edge);
    return 0;
  }

  void moved(Offset global) {
    _pos = global;
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _pos = null;
  }

  void _tick() {
    final p = _pos;
    final box = viewport.currentContext?.findRenderObject();
    if (p == null || box is! RenderBox || !box.attached || !controller.hasClients) return;
    final v = speedFor(box.globalToLocal(p).dy, box.size.height);
    if (v == 0) return;
    final pos = controller.position;
    controller.jumpTo((pos.pixels + v).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }
}
