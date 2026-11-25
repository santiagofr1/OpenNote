import 'dart:async';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settleWrites espera a que terminen las escrituras en curso y no deja temporales', () async {
    final root = await Directory.systemTemp.createTemp('apuntes_settle');
    try {
      final store = Storage(root: root);
      await store.init();
      // dos guardados seguidos, sin esperarlos
      unawaited(store.savePrefs({'a': 1}));
      unawaited(store.savePrefs({'b': 2}));
      await Storage.settleWrites();
      final prefs = File('${root.path}/prefs.json');
      expect(prefs.existsSync(), isTrue);
      expect(prefs.readAsStringSync(), contains('"b"'));
      final tmps = root.listSync(recursive: true).where((e) => e.path.endsWith('.tmp'));
      expect(tmps, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('dos guardados de preferencias seguidos no se pisan, y loadPrefsSettled lee lo último', () async {
    final root = await Directory.systemTemp.createTemp('apuntes_prefs');
    try {
      final store = Storage(root: root);
      await store.init();
      unawaited(store.savePrefs({'a': 1}));
      unawaited(store.savePrefs({'b': 2}));
      unawaited(store.savePrefs({'exportBg': false}));
      final p = await store.loadPrefsSettled(); // sin esperar los guardados: tiene que ver los tres
      expect(p?['a'], 1);
      expect(p?['b'], 2);
      expect(p?['exportBg'], false);
    } finally {
      await Storage.settleWrites();
      await root.delete(recursive: true);
    }
  });
}
