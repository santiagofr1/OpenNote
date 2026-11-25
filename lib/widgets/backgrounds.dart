import 'package:flutter/widgets.dart' show IconData;
import 'package:material_symbols_icons/symbols.dart';

import '../l10n/l10n.dart';

/// Fondos de hoja: valor guardado, ícono y nombre.
final backgrounds = <(String, IconData, String Function(L))>[
  ('lined', Symbols.format_align_justify, (L l) => l.paperLined),
  ('grid', Symbols.grid_4x4, (L l) => l.paperGrid),
  ('dots', Symbols.grid_goldenratio, (L l) => l.paperDots),
  ('mm', Symbols.grid_on, (L l) => l.paperMm),
  ('axes', Symbols.add, (L l) => l.paperAxes),
  ('blank', Symbols.crop_portrait, (L l) => l.paperBlank),
];

/// Plantillas que vienen con la app (también son valores de `bg`): valor guardado, ícono y nombre.
final templates = <(String, IconData, String Function(L))>[
  ('cornell', Symbols.view_sidebar, (L l) => l.paperCornell),
  ('todo', Symbols.checklist, (L l) => l.paperTodo),
  ('staff', Symbols.music_note, (L l) => l.paperStaff),
  ('weekly', Symbols.view_week, (L l) => l.paperWeekly),
  ('monthly', Symbols.calendar_month, (L l) => l.paperMonthly),
];
