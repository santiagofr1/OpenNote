import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/l10n/app_localizations_es.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final now = DateTime(2026, 3, 15, 18, 0);
  int ms(DateTime d) => d.millisecondsSinceEpoch;
  final es = LEs();
  setUpAll(() => initializeDateFormatting('es'));

  test('fmtDate', () {
    expect(fmtDate(es, 0, now: now), '');
    expect(fmtDate(es, ms(DateTime(2026, 3, 15, 9, 5)), now: now), 'hoy 09:05');
    expect(fmtDate(es, ms(DateTime(2026, 3, 14, 23, 59)), now: now), 'ayer 23:59');
    expect(fmtDate(es, ms(DateTime(2026, 1, 2)), now: now), '02/01');
    expect(fmtDate(es, ms(DateTime(2025, 12, 31)), now: now), '31/12/2025');
  });

  test('todayTitle y fmtDuration', () {
    expect(todayTitle(now: now), '15/03');
    expect(fmtDuration(0), '0:00');
    expect(fmtDuration(65999), '1:05');
    expect(fmtDuration(600000), '10:00');
  });
}
