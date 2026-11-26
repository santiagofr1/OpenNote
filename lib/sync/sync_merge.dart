/// Fusión de tres vías (base, local, remoto) de `notebook.json` e `index.json`. Funciones puras, sin disco ni red.
/// Las listas se fusionan por `id`: lo agregado en un lado se agrega; lo borrado en un lado se borra salvo que el otro
/// lado lo haya cambiado (editar le gana a borrar); si cambió en los dos lados queda el de `updated` más nuevo
/// (empate: el local). El orden es el local, y lo que llega del remoto se acomoda después de su vecino anterior.
library;

import 'dart:convert';

String _enc(Map m) => jsonEncode(m);
int _upd(Map m) => m['updated'] is num ? (m['updated'] as num).toInt() : 0;

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

/// Las entradas de la lista [k]: solo mapas con `id` de texto (la fusión es por id; una entrada rara de la nube no puede
/// tirar la fusión de ese archivo en cada pasada para siempre).
List<Map> _list(Map j, String k) => [for (final e in (j[k] is List ? j[k] as List : const [])) if (e is Map && e['id'] is String) e];

int _int(Object? v) => v is num ? v.toInt() : 0;

String mergeNotebookJson(String base, String local, String remote) {
  final b = _parse(base), l = _parse(local), r = _parse(remote);
  final sheets = _mergeHeads(mergeById(_list(b, 'sheets'), _list(l, 'sheets'), _list(r, 'sheets')), b, l, r);
  // las secciones se fusionan igual que las hojas; `active` (y el resto) queda el local. El `section` de cada hoja ya
  // viaja dentro de su objeto.
  final sections = mergeById(_list(b, 'sections'), _list(l, 'sections'), _list(r, 'sections'));
  return jsonEncode({...l, if (sections.isNotEmpty) 'sections': sections, 'sheets': sheets});
}

/// Títulos del índice de una hoja que cambió en los dos lados: la hoja que ganó se queda con sus datos, pero sus títulos
/// se fusionan por id con los del otro lado (si los dos marcaron un título distinto en la misma hoja, quedan los dos; si
/// tocaron el mismo, queda el de la hoja que ganó).
List<Map> _mergeHeads(List<Map> merged, Map b, Map l, Map r) {
  Map<String, Map> byId(Map j) => {for (final e in _list(j, 'sheets')) e['id'] as String: e};
  final bm = byId(b), lm = byId(l), rm = byId(r);
  return [
    for (final e in merged)
      if ((lm[e['id']], rm[e['id']]) case (final Map ls?, final Map rs?) when _enc(ls) != _enc(rs))
        _withHeads(e, mergeById(_list(bm[e['id']] ?? const {}, 'heads'), _list(e, 'heads'), _list(identical(e, rs) ? ls : rs, 'heads')))
      else
        e
  ];
}

Map _withHeads(Map sheet, List<Map> heads) => {
      for (final MapEntry(:key, :value) in sheet.entries)
        if (key != 'heads') key: value,
      if (heads.isNotEmpty) 'heads': heads,
    };

/// Lienzos: `canvas` es fijo desde que se crea y `canvasW` solo crece, así que queda el mayor de los dos lados
/// (la fusión se queda con la entrada entera de un lado).
List<Map> _keepCanvas(List<Map> merged, List<Map> local, List<Map> remote) {
  final others = <String, List<Map>>{};
  for (final e in [...local, ...remote]) {
    if (e['canvas'] == true) others.putIfAbsent(e['id'] as String, () => []).add(e);
  }
  return [
    for (final e in merged)
      if (others[e['id']] case final List<Map> l)
        {
          ...e,
          'canvas': true,
          'canvasW': l.map((x) => (x['canvasW'] as num?)?.toDouble() ?? 0.0).reduce((a, c) => a > c ? a : c),
        }
      else
        e
  ];
}

/// [keep]: ids de cuadernos que no se pueden borrar en esta pasada (se editaron en un lado y se borraron en el otro).
String mergeIndexJson(String base, String local, String remote, {Set<String> keep = const {}}) {
  final b = _parse(base), l = _parse(local), r = _parse(remote);
  final folders = mergeById(_list(b, 'folders'), _list(l, 'folders'), _list(r, 'folders'));
  final out = <String, dynamic>{
    ...l,
    'format': l['format'] ?? r['format'] ?? 3,
    'rev': [_int(l['rev']), _int(r['rev'])].reduce((a, c) => a > c ? a : c),
    'last': l['last'] ?? r['last'],
    'notebooks': _keepCanvas(mergeById(_list(b, 'notebooks'), _list(l, 'notebooks'), _list(r, 'notebooks'), keep: keep), _list(l, 'notebooks'), _list(r, 'notebooks')),
  };
  out.remove('folders');
  if (folders.isNotEmpty) out['folders'] = folders;
  return jsonEncode(out);
}

/// Forma "de nube" de `index.json`: sin los datos propios de cada dispositivo (la última hoja vista de cada cuaderno y
/// el último cuaderno abierto). Es lo que se compara, se sube y se fusiona; así abrir un cuaderno acá no cuenta como
/// un cambio que haya que mandar.
String normalizeIndex(String text) {
  final j = _parse(text);
  if (j.isEmpty) return text;
  j.remove('last');
  j['notebooks'] = [
    for (final e in _list(j, 'notebooks')) {...e}..remove('last'),
  ];
  return jsonEncode(j);
}

/// Lo contrario al bajar: a [cloud] (ya en forma de nube) se le devuelven los datos propios que tiene [local].
String restoreIndexLocal(String cloud, String local) {
  final c = _parse(cloud), l = _parse(local);
  if (c.isEmpty) return cloud;
  if (l['last'] != null) c['last'] = l['last'];
  final lasts = {for (final e in _list(l, 'notebooks')) e['id']: e['last']};
  c['notebooks'] = [
    for (final e in _list(c, 'notebooks')) lasts[e['id']] == null ? e : {...e, 'last': lasts[e['id']]},
  ];
  return jsonEncode(c);
}
