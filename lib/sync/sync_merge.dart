/// Fusión de tres vías (base, local, remoto) de `notebook.json` e `index.json`. Funciones puras, sin disco ni red.
/// Las listas se fusionan por `id`: lo agregado en un lado se agrega; lo borrado en un lado se borra salvo que el otro
/// lado lo haya cambiado (editar le gana a borrar); si cambió en los dos lados queda el de `updated` más nuevo
/// (empate: el local). El orden es el local, y lo que llega del remoto se acomoda después de su vecino anterior.
library;

import 'dart:convert';

String _enc(Map m) => jsonEncode(m);
int _upd(Map m) => (m['updated'] ?? 0) is int ? (m['updated'] ?? 0) as int : 0;

List<Map> mergeById(List<Map> base, List<Map> local, List<Map> remote, {Set<String> keep = const {}}) {
  final bm = {for (final e in base) e['id'] as String: e};
  final lm = {for (final e in local) e['id'] as String: e};
  final rm = {for (final e in remote) e['id'] as String: e};
  final out = <Map>[];
  for (final e in local) {
    final id = e['id'] as String;
    final b = bm[id], r = rm[id];
    if (r != null) {
      final lc = b == null || _enc(e) != _enc(b);
      final rc = b == null || _enc(r) != _enc(b);
      out.add(!lc ? r : (!rc ? e : (_upd(r) > _upd(e) ? r : e)));
    } else if (b == null || _enc(e) != _enc(b) || keep.contains(id)) {
      out.add(e); // nuevo acá, o cambiado acá y borrado allá: se queda
    }
  }
  String? last;
  for (final r in remote) {
    final id = r['id'] as String;
    if (lm.containsKey(id)) {
      last = id;
      continue;
    }
    final b = bm[id];
    if (b != null && _enc(r) == _enc(b) && !keep.contains(id)) continue; // borrado acá y sin cambios allá
    final at = last == null ? 0 : out.indexWhere((e) => e['id'] == last) + 1;
    out.insert(at, r);
    last = id;
  }
  return out;
}

Map _parse(String s) {
  try {
    final j = jsonDecode(s);
    return j is Map ? j : {};
  } catch (_) {
    return {};
  }
}

List<Map> _list(Map j, String k) => [for (final e in (j[k] as List? ?? const [])) if (e is Map) e];

String mergeNotebookJson(String base, String local, String remote) {
  final b = _parse(base), l = _parse(local), r = _parse(remote);
  final sheets = mergeById(_list(b, 'sheets'), _list(l, 'sheets'), _list(r, 'sheets'));
  return jsonEncode({...l, 'sheets': sheets});
}

/// [keep]: ids de cuadernos que no se pueden borrar en esta pasada (se editaron en un lado y se borraron en el otro).
String mergeIndexJson(String base, String local, String remote, {Set<String> keep = const {}}) {
  final b = _parse(base), l = _parse(local), r = _parse(remote);
  final folders = mergeById(_list(b, 'folders'), _list(l, 'folders'), _list(r, 'folders'));
  final out = <String, dynamic>{
    ...l,
    'format': l['format'] ?? r['format'] ?? 3,
    'rev': [(l['rev'] ?? 0) as int, (r['rev'] ?? 0) as int].reduce((a, c) => a > c ? a : c),
    'last': l['last'] ?? r['last'],
    'notebooks': mergeById(_list(b, 'notebooks'), _list(l, 'notebooks'), _list(r, 'notebooks'), keep: keep),
  };
  out.remove('folders');
  if (folders.isNotEmpty) out['folders'] = folders;
  return jsonEncode(out);
}
