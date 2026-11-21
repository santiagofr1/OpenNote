import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/e2e_crypto.dart';
import 'package:apuntes/sync/encrypted_remote_store.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/google_auth.dart' show TokenStore;
import 'package:apuntes/sync/remote_store.dart';
import 'package:apuntes/sync/sync_controller.dart';
import 'package:apuntes/sync/sync_crypto.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemTokens implements TokenStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

bool _contains(Uint8List hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_e2e');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<Notebook> create(Storage s, String name, {int n = 1}) async {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'secretotexto$k');
    }
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  Future<void> edit(Storage s, String nbId, int k, String text) async {
    final idx = await s.loadIndex();
    final nb = idx.notebooks.firstWhere((n) => n.id == nbId);
    final d = await s.loadNotebook(nb);
    d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, text);
    d.markDirtyAt(k * kSheetStep + 44);
    nb.touch();
    await s.saveNotebook(d);
    await s.saveIndex(idx);
  }

  Future<List<String>> texts(Storage s, String nbId, int k) async {
    final nb = (await s.loadIndex()).notebooks.firstWhere((n) => n.id == nbId);
    return [for (final t in await s.readSheetTexts(nb, nb.sheets[k])) t.text];
  }

  group('formato y clave', () {
    test('ida y vuelta: cifra, tiene la cabecera y descifra igual', () async {
      final v = Vault(Uint8List.fromList(List.generate(32, (i) => i)));
      final plain = Uint8List.fromList(utf8.encode('hola mundo ñandú'));
      final enc = await v.encrypt('index.json', plain);
      expect(hasEncryptedHeader(enc), isTrue);
      expect(enc.sublist(0, 4), utf8.encode('ONCR'));
      expect(enc[4], 1);
      expect(_contains(enc, utf8.encode('hola')), isFalse);
      expect(await v.decrypt('index.json', enc), plain);
      // vacío también
      expect(await v.decrypt('a', await v.encrypt('a', Uint8List(0))), isEmpty);
    });

    test('el nonce es al azar: dos cifrados del mismo texto difieren', () async {
      final v = Vault(Uint8List(32));
      final p = Uint8List.fromList([1, 2, 3]);
      expect(await v.encrypt('x', p), isNot(await v.encrypt('x', p)));
    });

    test('alterado, de otra ruta, de otra clave o sin cabecera: no descifra', () async {
      final v = Vault(Uint8List(32)), w = Vault(Uint8List.fromList(List.filled(32, 7)));
      final enc = await v.encrypt('a/b.sheet', Uint8List.fromList([9, 9, 9, 9]));
      final bad = Uint8List.fromList(enc)..[enc.length ~/ 2] ^= 1;
      await expectLater(v.decrypt('a/b.sheet', bad), throwsA(isA<CorruptEncryptedException>()));
      await expectLater(v.decrypt('otra.sheet', enc), throwsA(isA<CorruptEncryptedException>()));
      await expectLater(w.decrypt('a/b.sheet', enc), throwsA(isA<CorruptEncryptedException>()));
      await expectLater(v.decrypt('a', Uint8List.fromList(utf8.encode('{"texto":"en claro de sobra"}'))),
          throwsA(isA<CorruptEncryptedException>()));
    });

    test('frase correcta abre, incorrecta no; crypto.json va y viene', () async {
      final (v, info) = await Vault.create('frase larga de prueba', kdf: KdfParams.fast);
      final again = VaultInfo.parse(info.toBytes());
      expect(again.salt, info.salt);
      expect(again.kdf.memoryKiB, KdfParams.fast.memoryKiB);
      expect(again.migrating, isNull);
      final v2 = await Vault.open(again, 'frase larga de prueba');
      expect(v2.key, v.key);
      await expectLater(Vault.open(again, 'otra frase'), throwsA(isA<WrongPassphraseException>()));
      expect(VaultInfo.parse(info.withMigrating(CryptoMigration.encrypting).toBytes()).migrating, CryptoMigration.encrypting);
      expect(() => VaultInfo.parse(utf8.encode('{"basura":1}')), throwsA(isA<RemoteException>()));
    });

    test('la sal es al azar: la misma frase da otra clave en otra nube', () async {
      final (a, _) = await Vault.create('misma frase', kdf: KdfParams.fast);
      final (b, _) = await Vault.create('misma frase', kdf: KdfParams.fast);
      expect(a.key, isNot(b.key));
    });
  });

  group('EncryptedRemoteStore con el motor (dos dispositivos)', () {
    late FakeRemoteStore remote;
    late Vault vault;
    late VaultInfo info;
    setUp(() async {
      remote = FakeRemoteStore();
      (vault, info) = await Vault.create('una frase', kdf: KdfParams.fast);
    });

    // cada dispositivo tiene su caché de hashes (como en disco)
    final caches = <Storage, HashCache>{};
    EncryptedRemoteStore encFor(Storage s) =>
        EncryptedRemoteStore(remote, vault, info, cache: caches.putIfAbsent(s, HashCache.new));
    Future<SyncReport> sync(Storage s, {EncryptedRemoteStore? via}) =>
        SyncEngine(s, via ?? encFor(s), account: 'x').sync();

    test('subir, bajar y una segunda pasada no sube ni baja nada (los hashes no se rompen)', () async {
      final a = await device(), b = await device();
      final nb = await create(a, 'Cuaderno secreto', n: 3);
      final r1 = await sync(a);
      expect(r1.errors, isEmpty);
      await sync(b);
      expect(await texts(b, nb.id, 2), ['secretotexto2']);
      remote.clearCounters();
      for (final s in [a, b, a, b]) {
        final rep = await sync(s);
        expect(rep.nothingToDo, isTrue, reason: rep.toString());
      }
      expect(remote.uploads, 0, reason: 'el md5 del cifrado cambia en cada subida; el motor no debe verlo como cambio');
      // (b y a bajan el listado/ delta pero ningún archivo)
      expect(remote.downloads, lessThanOrEqualTo(4));
    });

    test('el remoto nunca contiene el texto en claro ni los nombres', () async {
      final a = await device();
      final nb = await create(a, 'Cuaderno secreto', n: 2);
      await sync(a);
      expect(remote.paths, isNotEmpty);
      for (final p in remote.paths) {
        final bytes = remote.bytesOf(p)!;
        expect(hasEncryptedHeader(bytes) || p == kCryptoFile, isTrue, reason: p);
        expect(_contains(bytes, utf8.encode('secretotexto')), isFalse, reason: p);
        expect(_contains(bytes, utf8.encode('Cuaderno secreto')), isFalse, reason: p);
        expect(_contains(bytes, utf8.encode(nb.id)), isFalse, reason: 'el id del cuaderno solo va en la ruta');
      }
      // lo que repone: crypto.json (sin secretos)
      expect(remote.has(kCryptoFile), isTrue);
      expect(_contains(remote.bytesOf(kCryptoFile)!, utf8.encode('Cuaderno')), isFalse);
    });

    test('editar en uno baja en el otro y solo se sube lo que cambió', () async {
      final a = await device(), b = await device();
      final nb = await create(a, 'Mate', n: 3);
      await sync(a);
      await sync(b);
      await edit(b, nb.id, 1, 'cambiada en B');
      remote.clearCounters();
      await sync(b);
      expect(remote.uploaded.where((p) => p.endsWith('.sheet')), [contains(nb.sheets[1].id)]);
      await sync(a);
      expect(await texts(a, nb.id, 1), ['cambiada en B']);
      expect(await texts(a, nb.id, 0), ['secretotexto0']);
    });

    test('conflicto: la misma hoja en los dos lados deja las dos versiones', () async {
      final a = await device(), b = await device();
      final nb = await create(a, 'Quimica', n: 2);
      await sync(a);
      await sync(b);
      await edit(a, nb.id, 0, 'version A');
      await edit(b, nb.id, 0, 'version B');
      await sync(b);
      final repA = await sync(a);
      expect(repA.conflicts, 1);
      await sync(b);
      await sync(a);
      for (final s in [a, b]) {
        final idx = await s.loadIndex();
        final n = idx.notebooks.firstWhere((x) => x.id == nb.id);
        expect(n.sheets, hasLength(3));
        expect(n.sheets[1].title, contains('(conflicto)'));
      }
      expect(await texts(a, nb.id, 0), ['version A']);
      expect(await texts(b, nb.id, 0), ['version A']);
    });

    test('borrado: borrar un cuaderno en A lo borra en B', () async {
      final a = await device(), b = await device();
      final nb = await create(a, 'Para borrar', n: 2);
      await create(a, 'Se queda');
      await sync(a);
      await sync(b);
      final idx = await a.loadIndex();
      idx.notebooks.removeWhere((n) => n.id == nb.id);
      await a.saveIndex(idx);
      await a.removeNotebookFiles(nb.id);
      final rep = await sync(a);
      expect(rep.errors, isEmpty);
      expect(remote.paths.where((p) => p.contains(nb.id)), isEmpty);
      await sync(b);
      expect((await b.loadIndex()).notebooks.map((n) => n.name), ['Se queda']);
    });

    test('un reinicio (caché de hashes vacía) no genera conflictos ni errores', () async {
      final a = await device();
      final nb = await create(a, 'Reinicio', n: 2);
      await sync(a);
      await edit(a, nb.id, 0, 'despues del reinicio');
      final rep = await sync(a, via: EncryptedRemoteStore(remote, vault, info, cache: HashCache()));
      expect(rep.errors, isEmpty, reason: rep.toString());
      expect(rep.uploaded, greaterThan(0));
      expect(rep.conflicts, 0);
    });

    test('un archivo de la nube sin cifrar corta la pasada y no borra nada local', () async {
      final a = await device();
      final nb = await create(a, 'Intacto', n: 1);
      await sync(a);
      remote.put('notebooks/${nb.id}/notebook.json', utf8.encode('{"format":1,"sheets":[]}'));
      await expectLater(sync(a), throwsA(isA<CorruptEncryptedException>()));
      expect(await texts(a, nb.id, 0), ['secretotexto0']);
    });

    test('si cambia crypto.json (otro dispositivo rehízo el cifrado) avisa', () async {
      final a = await device();
      await create(a, 'X');
      await sync(a);
      final (_, other) = await Vault.create('otra frase', kdf: KdfParams.fast);
      remote.put(kCryptoFile, other.toBytes());
      await expectLater(sync(a), throwsA(isA<VaultChangedException>()));
    });

    test('si borran la carpeta de la nube se repone crypto.json antes de subir nada', () async {
      final a = await device();
      await create(a, 'Y');
      await sync(a);
      remote.wipe();
      await sync(a);
      expect(remote.has(kCryptoFile), isTrue);
      for (final p in remote.paths.where((p) => p != kCryptoFile)) {
        expect(hasEncryptedHeader(remote.bytesOf(p)!), isTrue, reason: p);
      }
    });
  });

  group('SyncController: activar, frase y desactivar', () {
    late FakeRemoteStore remote;
    late _MemTokens tokensA, tokensB;
    final ctrls = <SyncController>[];
    tearDown(() {
      for (final c in ctrls) {
        c.dispose();
      }
      ctrls.clear();
    });

    Future<(SyncController, Storage, SyncCrypto)> dev(_MemTokens tokens) async {
      final s = await device();
      final crypto = SyncCrypto(store: s, tokens: tokens, kdf: KdfParams.fast);
      final c = SyncController(store: s, backend: FakeBackend(remote), crypto: crypto);
      ctrls.add(c);
      await c.connect();
      await c.whenIdle();
      return (c, s, crypto);
    }

    setUp(() {
      remote = FakeRemoteStore();
      tokensA = _MemTokens();
      tokensB = _MemTokens();
    });

    test('con datos en claro en la nube: activar re-sube todo cifrado; el otro dispositivo pide la frase', () async {
      final sa = await device();
      final nb = await create(sa, 'Vieja', n: 2);
      final crypto = SyncCrypto(store: sa, tokens: tokensA, kdf: KdfParams.fast);
      final a = SyncController(store: sa, backend: FakeBackend(remote), crypto: crypto);
      ctrls.add(a);
      await a.connect();
      await a.whenIdle();
      expect(a.error, isNull);
      expect(crypto.state, CryptoState.off);
      expect(remote.has(kCryptoFile), isFalse);
      expect(_contains(remote.bytesOf('index.json')!, utf8.encode('Vieja')), isTrue, reason: 'antes estaba en claro');

      expect(await a.enableEncryption('frase de prueba 1'), isNull);
      await a.whenIdle();
      expect(crypto.state, CryptoState.on);
      expect(tokensA.map, contains(SyncCrypto.keyName));
      expect(remote.has(kCryptoFile), isTrue);
      for (final p in remote.paths.where((p) => p != kCryptoFile)) {
        final b = remote.bytesOf(p)!;
        expect(hasEncryptedHeader(b), isTrue, reason: p);
        expect(_contains(b, utf8.encode('secretotexto')), isFalse, reason: p);
        expect(_contains(b, utf8.encode('Vieja')), isFalse, reason: p);
      }
      expect(VaultInfo.parse(remote.bytesOf(kCryptoFile)!).migrating, isNull);
      expect(a.error, isNull);

      // otro dispositivo: sin frase no sincroniza
      final (b, sb, cb) = await dev(tokensB);
      expect(cb.state, CryptoState.locked);
      expect(b.error, contains('cifrada'));
      expect((await sb.indexFile.exists()) && (await sb.loadIndex()).notebooks.any((n) => n.name == 'Vieja'), isFalse);
      // frase incorrecta: avisa y sigue bloqueado
      expect(await b.unlockEncryption('frase equivocada'), contains('incorrecta'));
      expect(cb.state, CryptoState.locked);
      expect(tokensB.map, isEmpty);
      // frase correcta: baja todo
      expect(await b.unlockEncryption('frase de prueba 1'), isNull);
      await b.syncNow(manual: true);
      await b.whenIdle();
      expect(b.error, isNull);
      expect(cb.state, CryptoState.on);
      expect((await sb.loadIndex()).notebooks.map((n) => n.name), contains('Vieja'));
      expect(await texts(sb, nb.id, 1), ['secretotexto1']);

      // un cambio en B llega a A cifrado y sin conflictos
      await edit(sb, nb.id, 0, 'desde B');
      await b.syncNow(manual: true);
      await b.whenIdle();
      await a.syncNow(manual: true);
      await a.whenIdle();
      expect(a.error, isNull);
      expect(await texts(sa, nb.id, 0), ['desde B']);
      expect(a.conflictCount, 0);
    });

    test('desactivar deja la nube en claro otra vez y borra la clave del dispositivo', () async {
      final (a, sa, crypto) = await dev(tokensA);
      await create(sa, 'Volver', n: 1);
      expect(await a.enableEncryption('otra frase bien larga'), isNull);
      await a.syncNow(manual: true);
      await a.whenIdle();
      expect(remote.has(kCryptoFile), isTrue);

      expect(await a.disableEncryption(), isNull);
      await a.whenIdle();
      expect(crypto.state, CryptoState.off);
      expect(remote.has(kCryptoFile), isFalse);
      expect(tokensA.map, isEmpty);
      for (final p in remote.paths) {
        expect(hasEncryptedHeader(remote.bytesOf(p)!), isFalse, reason: p);
      }
      expect(_contains(remote.bytesOf('index.json')!, utf8.encode('Volver')), isTrue);
      await a.syncNow(manual: true);
      await a.whenIdle();
      expect(a.error, isNull);
      expect(a.lastReport!.conflicts, 0);
    });

    test('un cambio de cifrado que se cortó a la mitad se retoma en la próxima pasada', () async {
      final (a, sa, crypto) = await dev(tokensA);
      await create(sa, 'Cortado', n: 3);
      await a.syncNow(manual: true);
      await a.whenIdle();
      // el remoto se corta después de unas pocas operaciones durante la activación
      remote.resetOps();
      remote.failAfter = 14;
      final err = await a.enableEncryption('frase cortada larga');
      expect(err, isNotNull);
      remote.failAfter = null;
      expect(VaultInfo.parse(remote.bytesOf(kCryptoFile)!).migrating, CryptoMigration.encrypting);
      // lo local sigue entero
      expect(await texts(sa, (await sa.loadIndex()).notebooks.last.id, 0), ['secretotexto0']);
      await a.syncNow(manual: true);
      await a.whenIdle();
      expect(a.error, isNull, reason: '${a.error}');
      expect(crypto.state, CryptoState.on);
      expect(VaultInfo.parse(remote.bytesOf(kCryptoFile)!).migrating, isNull);
      for (final p in remote.paths.where((p) => p != kCryptoFile)) {
        expect(hasEncryptedHeader(remote.bytesOf(p)!), isTrue, reason: p);
      }
      expect(remote.paths.where((p) => p.endsWith('.sheet')), hasLength(3));
    });

    test('desconectar olvida la clave del dispositivo', () async {
      final (a, sa, crypto) = await dev(tokensA);
      await create(sa, 'Z');
      expect(await a.enableEncryption('frase para desconectar'), isNull);
      expect(tokensA.map, isNotEmpty);
      await a.disconnect();
      expect(tokensA.map, isEmpty);
      expect(crypto.state, CryptoState.unknown);
    });
  });
}
