import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';

/// Elegir adónde mover algo: árbol de carpetas con "Inicio" arriba.
/// Devuelve el id de la carpeta elegida dentro de un registro (`(id: null)` = Inicio),
/// o null si se canceló. [exclude]: carpetas que no se pueden elegir (la que se mueve y sus hijas).
/// [current]: donde está ahora (se marca). Cada fila tiene la key `moveTarget-<nombre>`.
Future<({String? id})?> askMoveTarget(BuildContext context, NotesIndex idx,
    {required String title, String? current, Set<String> exclude = const {}}) {
  final cs = Theme.of(context).colorScheme;
  final rows = <Widget>[];
  void row(String? id, String name, int depth) {
    final disabled = id != null && exclude.contains(id);
    final here = id == current;
    rows.add(ListTile(
      key: Key('moveTarget-$name'),
      enabled: !disabled,
      contentPadding: EdgeInsets.only(left: 12.0 + depth * 22, right: 12),
      leading: Icon(id == null ? Symbols.home : Symbols.folder, weight: 300, fill: id == null ? 0 : 1, color: disabled ? null : cs.primary),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: here ? Text('acá', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => Navigator.pop(context, (id: id)),
    ));
    if (disabled) return; // tampoco se muestran sus hijas
    for (final c in idx.childrenOf(id)) {
      row(c.id, c.name, depth + 1);
    }
  }

  row(null, 'Inicio', 0);
  return showDialog<({String? id})>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
    ),
  );
}
