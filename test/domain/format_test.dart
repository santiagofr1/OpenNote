import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 3, 15, 18, 0);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  test('fmtDate', () {
    expect(fmtDate(0, now: now), '');
    expect(fmtDate(ms(DateTime(2026, 3, 15, 9, 5)), now: now), 'hoy 09:05');
    expect(fmtDate(ms(DateTime(2026, 3, 14, 23, 59)), now: now), 'ayer 23:59');
    expect(fmtDate(ms(DateTime(2026, 1, 2)), now: now), '02/01');
    expect(fmtDate(ms(DateTime(2025, 12, 31)), now: now), '31/12/2025');
  });

  test('todayTitle y fmtDuration', () {
    expect(todayTitle(now: now), '15/03');
    expect(fmtDuration(0), '0:00');
    expect(fmtDuration(65999), '1:05');
    expect(fmtDuration(600000), '10:00');
  });
}
