import 'package:apuntes/domain/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea tags y versiones', () {
    expect(AppVersion.tryParse('v1.0.12').toString(), '1.0.12');
    expect(AppVersion.tryParse('1.0.0')!.patch, 0);
    expect(AppVersion.tryParse(' v2.10.3 ')!.minor, 10);
  });

  test('rechaza tags mal formados y prereleases', () {
    for (final s in ['', 'v1.0', '1.0.12.1', 'v1.0.x', 'latest', 'v1.0.12-beta', '1.0.0+1', 'vv1.0.1', 'v-1.0.1']) {
      expect(AppVersion.tryParse(s), isNull, reason: s);
    }
    expect(AppVersion.tryParse(null), isNull);
  });

  test('compara numéricamente, no como texto', () {
    final a = AppVersion.tryParse('1.0.9')!, b = AppVersion.tryParse('1.0.12')!;
    expect(b > a, isTrue);
    expect(a > b, isFalse);
    expect(AppVersion.tryParse('1.1.0')! > b, isTrue);
    expect(AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.99.99')!, isTrue);
    expect(AppVersion.tryParse('v1.0.5'), AppVersion.tryParse('1.0.5'));
    expect(a > a, isFalse);
  });
}
