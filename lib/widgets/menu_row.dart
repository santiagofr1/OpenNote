import 'package:flutter/material.dart';

/// Fila de menú: ícono + texto (rojo si borra algo).
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const MenuRow(this.icon, this.label, {super.key, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = danger ? cs.error : cs.onSurfaceVariant;
    return Row(children: [
      Icon(icon, size: 20, weight: 300, color: c),
      const SizedBox(width: 14),
      Text(label, style: TextStyle(color: danger ? cs.error : cs.onSurface)),
    ]);
  }
}
