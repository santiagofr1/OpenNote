import 'dart:ui';

import 'elements.dart';
import 'stroke.dart';

/// Algo que se dibuja en la hoja (trazo, texto, imagen/nota/audio) y tiene lugar en el orden de dibujo.
///
/// Un solo orden para todo el cuaderno: se dibuja de menor a mayor [z]. Con el mismo [z] (archivos
/// viejos, que no lo guardaban) se desempata por tipo y por orden de carga: imágenes/notas/audio,
/// tinta y textos, que es como se veía antes. Los elementos nuevos toman el [z] más alto.
abstract class Layered {
  int z = 0;
  String get id;
}

/// Desempate entre tipos con el mismo [z].
int _kindRank(Layered e) => e is Item ? 0 : (e is Stroke ? 1 : 2);

/// Ordena [els] por [Layered.z] (estable; con [z] igual, por tipo y luego por el orden recibido).
List<Layered> sortByZ(Iterable<Layered> els) {
  final list = els.toList();
  final idx = List<int>.generate(list.length, (i) => i)
    ..sort((a, b) {
      final x = list[a], y = list[b];
      final c = x.z != y.z ? x.z.compareTo(y.z) : _kindRank(x).compareTo(_kindRank(y));
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final i in idx) list[i]];
}

/// Tramo del orden de dibujo: una tanda de trazos seguidos, o un solo texto / elemento.
///
/// Regla del resaltador: dentro de una tanda de trazos seguidos, los resaltadores se dibujan primero,
/// así nunca tapan la tinta que se escribió "al mismo tiempo" (sin nada en el medio). Si entre el
/// resaltador y la tinta hay una imagen o un texto, vale el orden tal cual.
class ZRun {
  final List<Stroke>? strokes;
  final Layered? single;
  const ZRun.ink(List<Stroke> this.strokes) : single = null;
  const ZRun.one(Layered this.single) : strokes = null;
}

/// Agrupa un orden de dibujo en tramos: cada tanda de trazos seguidos es un tramo (se dibuja y cachea junta).
List<ZRun> zRuns(Iterable<Layered> order) {
  final out = <ZRun>[];
  List<Stroke>? cur;
  for (final e in order) {
    if (e is Stroke) {
      if (cur == null) {
        cur = [];
        out.add(ZRun.ink(cur));
      }
      cur.add(e);
    } else {
      cur = null;
      out.add(ZRun.one(e));
    }
  }
  return out;
}

/// Cómo cambiar el lugar de lo seleccionado en el orden de dibujo.
enum ZMove { front, up, down, back }

/// Cambio de orden ya calculado: [z] de cada elemento que cambió, antes y después (para deshacer).
class ZChange {
  final Map<String, int> before, after;
  const ZChange(this.before, this.after);
}

/// Calcula cómo queda el orden al mover los elementos [sel] de [order] (ya ordenado por [Layered.z]).
/// Devuelve null si no hay nada que cambiar.
///
/// - [ZMove.front] / [ZMove.back]: lo seleccionado pasa arriba de todo / abajo de todo.
/// - [ZMove.up] / [ZMove.down]: lo seleccionado pasa por encima / por debajo del próximo elemento no
///   seleccionado cuyo rectángulo ([rectOf]) se superpone con el de la selección; los que no se tocan se saltean.
///   Con varios seleccionados se mueven juntos, conservando su orden entre sí.
///
/// Solo se reacomodan los [z] de ese tramo (los mismos valores, en otro orden), así el cambio es chico.
/// Si hay [z] repetidos (archivos viejos) primero se numera todo 0..n-1.
ZChange? computeReorder(List<Layered> order, Set<String> sel, ZMove move, Rect Function(Layered) rectOf) {
  final n = order.length;
  int? minS, maxS;
  for (var i = 0; i < n; i++) {
    if (sel.contains(order[i].id)) {
      minS ??= i;
      maxS = i;
    }
  }
  if (minS == null || maxS == null) return null;

  int lo, hi;
  switch (move) {
    case ZMove.front:
      lo = minS;
      hi = n - 1;
    case ZMove.back:
      lo = 0;
      hi = maxS;
    case ZMove.up:
    case ZMove.down:
      Rect? b;
      for (var i = minS; i <= maxS; i++) {
        if (sel.contains(order[i].id)) {
          final r = rectOf(order[i]);
          b = b == null ? r : b.expandToInclude(r);
        }
      }
      var t = -1;
      if (move == ZMove.up) {
        for (var i = maxS + 1; i < n && t < 0; i++) {
          if (rectOf(order[i]).overlaps(b!)) t = i;
        }
        lo = minS;
        hi = t;
      } else {
        for (var i = minS - 1; i >= 0 && t < 0; i--) {
          if (rectOf(order[i]).overlaps(b!)) t = i;
        }
        lo = t;
        hi = maxS;
      }
      if (t < 0) return null;
  }

  final range = order.sublist(lo, hi + 1);
  final picked = [for (final e in range) if (sel.contains(e.id)) e];
  final others = [for (final e in range) if (!sel.contains(e.id)) e];
  final arranged = move == ZMove.front || move == ZMove.up ? [...others, ...picked] : [...picked, ...others];
  var same = true;
  for (var k = 0; k < range.length; k++) {
    if (!identical(range[k], arranged[k])) same = false;
  }
  if (same) return null;

  var tied = false;
  for (var i = 1; i < n; i++) {
    if (order[i].z == order[i - 1].z) tied = true;
  }
  final slot = [for (var i = 0; i < n; i++) tied ? i : order[i].z];
  final before = <String, int>{}, after = <String, int>{};
  void set(Layered e, int z) {
    if (e.z != z) {
      before[e.id] = e.z;
      after[e.id] = z;
    }
  }

  if (tied) {
    for (var i = 0; i < n; i++) {
      if (i < lo || i > hi) set(order[i], i);
    }
  }
  for (var k = 0; k < arranged.length; k++) {
    set(arranged[k], slot[lo + k]);
  }
  return ZChange(before, after);
}
