// Textos de fechas y duraciones que se muestran en pantalla.

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 'hoy 14:05', 'ayer 09:30', '03/11' o '03/11/2024' si es de otro año. Vacío si nunca se editó.
String fmtDate(int ms, {DateTime? now}) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  now ??= DateTime.now();
  final hm = '${_pad2(d.hour)}:${_pad2(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'hoy $hm';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'ayer $hm';
  return '${_pad2(d.day)}/${_pad2(d.month)}${d.year != now.year ? '/${d.year}' : ''}';
}

/// Título por defecto de una página nueva: 'dd/mm' de hoy.
String todayTitle({DateTime? now}) {
  final d = now ?? DateTime.now();
  return '${_pad2(d.day)}/${_pad2(d.month)}';
}

/// Duración en ms → 'm:ss'.
String fmtDuration(int ms) => '${ms ~/ 60000}:${_pad2((ms ~/ 1000) % 60)}';
