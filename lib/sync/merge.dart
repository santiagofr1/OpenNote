import 'dart:collection';
import 'dart:convert';

import '../domain/domain.dart';

/// Fusión de `notebook.json` e `index.json` cuando cambiaron en los dos lados desde la última sincronización
/// (funciones puras, sin disco). Siempre tres vías: base (la última versión sincronizada), local y remota.

String _enc(Object? o) => jsonEncode(_sorted(o));

Object? _sorted(Object? o) {
  if (o is Map) return SplayTreeMap<String, Object?>.from({for (final e in o.entries) e.key as String: _sorted(e.value)});
  if (o is List) return [for (final e in o) _sorted(e)];
  return o;
}

int _upd(Map m) => (m['updated'] ?? 0) as int;

/// Fusiona dos listas de entradas con `id` (cuadernos, carpetas u hojas):
///  - en los dos lados: el que cambió respecto a la base; si cambiaron los dos, el de `updated` más nuevo (empate: local);
///  - en un solo lado y no estaba en la base: es nueva, se queda;
///  - en un solo lado y estaba en la base: el otro lado la borró; si no se tocó se borra, si se tocó se queda.
///    [keepRemoved] puede salvar una entrada que se iba a borrar (el cuaderno todavía tiene archivos acá).
Map<String, Map<String, dynamic>> _mergeById(List<Map> b, List<Map> l, List<Map> r, {bool Function(String id)? keepRemoved}) {
  final bm = {for (final m in b) m['id'] as String: m};
  final lm = {for (final m in l) m['id'] as String: m};
  final rm = {for (final m in r) m['id'] as String: m};
  final out = <String, Map<String, dynamic>>{};
  bool same(Map? x, Map? y) => x != null && y != null && _enc(x) == _enc(y);
  Map<String, dynamic> cp(Map m) => Map<String, dynamic>.from(m);
  for (final id in {...lm.keys, ...rm.keys}) {
    final x = lm[id], y = rm[id], z = bm[id];
    if (x != null && y != null) {
      final Map pick;
      if (same(x, y) || same(y, z)) {
        pick = x; // iguales, o solo cambió el local
      } else if (same(x, z)) {
        pick = y; // solo cambió el remoto
      } else {
        pick = _upd(x) >= _upd(y) ? x : y; // cambiaron los dos: el más nuevo
      }
      out[id] = cp(pick);
    } else if (x != null) {
      // solo acá: ¿nueva o la borraron allá?
      if (z == null || !same(x, z) || (keepRemoved?.call(id) ?? false)) out[id] = cp(x);
    } else {
      if (z == null || !same(y, z) || (keepRemoved?.call(id) ?? false)) out[id] = cp(y!);
    }
  }
  return out;
}

// ---------------------------------------------------------------- notebook.json

List<Map> _sheets(String? text) {
  if (text == null) return [];
  return [for (final s in (jsonDecode(text) as Map)['sheets'] as List) s as Map];
}

String _nbJson(Iterable<Map> sheets) =>
    jsonEncode({'format': Notebook.kFormat, 'sheets': [for (final m in sheets) SheetMeta.fromJson(m).toJson()]});

/// `notebook.json` sin las hojas [drop] (las que se borran en la pasada).
String filterNotebookJson(String text, Set<String> drop) =>
    drop.isEmpty ? text : _nbJson(_sheets(text).where((m) => !drop.contains(m['id'])));

/// Fusiona el `notebook.json` de los dos lados. Los datos de cada hoja (título, marcador, fondo, rev...) se toman por
/// hoja; el orden es el del lado que lo cambió (si cambiaron los dos, el local) y las hojas nuevas del otro lado se
/// meten después de su vecina anterior. Las hojas [drop] se sacan.
String mergeNotebookJson({String? base, required String local, required String remote, Set<String> drop = const {}}) {
  final b = _sheets(base), l = _sheets(local), r = _sheets(remote);
  final merged = _mergeById(b, l, r);
  merged.removeWhere((id, _) => drop.contains(id));
  final bIds = [for (final m in b) m['id'] as String];
  final lIds = [for (final m in l) m['id'] as String];
  final rIds = [for (final m in r) m['id'] as String];
  List<String> common(List<String> x, List<String> y) => [for (final i in x) if (y.contains(i)) i];
  final localReordered = common(lIds, bIds).join(',') != common(bIds, lIds).join(',');
  final remoteReordered = common(rIds, bIds).join(',') != common(bIds, rIds).join(',');
  final useRemote = remoteReordered && !localReordered;
  final primary = useRemote ? rIds : lIds, other = useRemote ? lIds : rIds;
  final order = [for (final id in primary) if (merged.containsKey(id)) id];
  for (var i = 0; i < other.length; i++) {
    final id = other[i];
    if (!merged.containsKey(id) || order.contains(id)) continue;
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final k = order.indexOf(other[j]);
      if (k >= 0) {
        at = k + 1;
        break;
      }
    }
    order.insert(at, id);
  }
  return _nbJson([for (final id in order) merged[id]!]);
}

// ---------------------------------------------------------------- index.json

/// El `index.json` en su forma canónica, la que se sube: sin lo que es de cada dispositivo (`rev`, el cuaderno abierto
/// por última vez, la última hoja vista de cada cuaderno), con las claves y las entradas ordenadas. Así dos
/// dispositivos con lo mismo producen exactamente los mismos bytes.
String canonicalIndex(String text) {
  final j = jsonDecode(text) as Map;
  List<Map> entries(String key, {bool dropLast = false}) {
    final l = [
      for (final e in (j[key] as List? ?? []))
        {for (final kv in (e as Map).entries) if (!(dropLast && kv.key == 'last')) kv.key: kv.value}
    ];
    l.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return l;
  }

  return _enc({'format': Notebook.kFormat, 'notebooks': entries('notebooks', dropLast: true), 'folders': entries('folders')});
}

/// Fusiona dos índices canónicos. [keepRemovedNotebook] dice si un cuaderno que el otro lado borró todavía tiene
/// archivos en este dispositivo (en ese caso se queda). Las carpetas borradas se respetan siempre.
String mergeIndexCanon({String? base, required String local, required String remote, required bool Function(String id) keepRemovedNotebook}) {
  List<Map> list(String? t, String k) => t == null ? [] : [for (final e in ((jsonDecode(t) as Map)[k] as List? ?? [])) e as Map];
  final nbs = _mergeById(list(base, 'notebooks'), list(local, 'notebooks'), list(remote, 'notebooks'), keepRemoved: keepRemovedNotebook);
  final fs = _mergeById(list(base, 'folders'), list(local, 'folders'), list(remote, 'folders'));
  return _enc({'format': Notebook.kFormat, 'notebooks': nbs.values.toList(), 'folders': fs.values.toList()});
}

/// Convierte el índice canónico [canon] en el `index.json` local: conserva de [localRaw] lo propio de este dispositivo
/// (`last` de cada cuaderno y del índice) y sube `rev`.
String indexForLocal(String canon, String? localRaw) {
  final c = jsonDecode(canon) as Map;
  final loc = localRaw == null ? <String, dynamic>{} : (jsonDecode(localRaw) as Map).cast<String, dynamic>();
  final lastOf = {for (final n in (loc['notebooks'] as List? ?? [])) (n as Map)['id'] as String: n['last'] ?? 0};
  final nbs = [
    for (final n in (c['notebooks'] as List)) {...(n as Map).cast<String, dynamic>(), 'last': lastOf[n['id']] ?? 0}
  ];
  final ids = {for (final n in nbs) n['id'] as String};
  final lastNb = loc['last'] as String?;
  final idx = NotesIndex.fromJson({
    'format': Notebook.kFormat,
    'rev': ((loc['rev'] ?? 0) as int) + 1,
    'last': lastNb != null && ids.contains(lastNb) ? lastNb : null,
    'notebooks': nbs,
    'folders': c['folders'],
  });
  return jsonEncode(idx.toJson());
}
