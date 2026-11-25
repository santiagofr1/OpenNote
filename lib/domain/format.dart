// Textos de fechas y duraciones que se muestran en pantalla.

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 'hoy 14:05', 'ayer 09:30', '03/11' o '03/11/2024' si es de otro año. Vacío si nunca se editó.
String fmtDate(L l, int ms, {DateTime? now}) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  now ??= DateTime.now();
  final hm = DateFormat(l.datePatternTime, l.localeName).format(d);
  if (d.year == now.year && d.month == now.month && d.day == now.day) return l.dateToday(hm);
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return l.dateYesterday(hm);
  return DateFormat(d.year != now.year ? l.datePatternDayMonthYear : l.datePatternDayMonth, l.localeName).format(d);
}

/// Título por defecto de una página nueva: 'dd/mm' de hoy.
String todayTitle({DateTime? now}) {
  final d = now ?? DateTime.now();
  return '${_pad2(d.day)}/${_pad2(d.month)}';
}

/// Duración en ms → 'm:ss'.
String fmtDuration(int ms) => '${ms ~/ 60000}:${_pad2((ms ~/ 1000) % 60)}';
