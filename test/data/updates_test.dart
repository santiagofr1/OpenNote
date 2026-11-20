import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/updates.dart';
import 'package:apuntes/domain/version.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/release_latest.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('release: versión, notas, APK y tamaño', () {
    final u = parseRelease(fixture())!;
    expect(u.version.toString(), '1.0.12');
    expect(u.notes, startsWith('- Arregla el zoom'));
    expect(u.apkUrl, endsWith('/OpenNote-v1.0.12.apk'));
    expect(u.size, 52428800);
  });

  test('release: se ignora prerelease, borrador, tag raro y sin APK', () {
    expect(parseRelease({...fixture(), 'prerelease': true}), isNull);
    expect(parseRelease({...fixture(), 'draft': true}), isNull);
    expect(parseRelease({...fixture(), 'tag_name': 'nightly'}), isNull);
    expect(parseRelease({...fixture(), 'tag_name': 'v1.0.12-rc1'}), isNull);
    expect(parseRelease({...fixture(), 'assets': []}), isNull);
    expect(parseRelease({...fixture(), 'assets': 'x'}), isNull);
    expect(parseRelease({'message': 'Not Found'}), isNull);
  });

  test('newerThan compara con la versión instalada', () {
    final u = parseRelease(fixture());
    expect(newerThan(u, AppVersion.tryParse('1.0.11')), isNotNull);
    expect(newerThan(u, AppVersion.tryParse('1.0.12')), isNull);
    expect(newerThan(u, AppVersion.tryParse('1.0.13')), isNull);
    expect(newerThan(u, null), isNull);
    expect(newerThan(null, AppVersion.tryParse('1.0.0')), isNull);
  });

  test('prefs: valores por defecto, ida y vuelta y plazo de 24 h', () {
    final p = UpdatePrefs.from(null);
    expect(p.auto, isTrue);
    expect(p.skipped, isNull);
    final now = DateTime(2026, 1, 10, 12);
    expect(p.due(now), isTrue); // nunca se buscó
    p.lastCheck = now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch;
    expect(p.due(now), isFalse);
    p.lastCheck = now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
    expect(p.due(now), isTrue);
    p.auto = false;
    expect(p.due(now), isFalse);
    final back = UpdatePrefs.from(p.toJson()..['updSkipped'] = '1.0.7');
    expect(back.auto, isFalse);
    expect(back.lastCheck, p.lastCheck);
    expect(back.skipped, '1.0.7');
  });
}
