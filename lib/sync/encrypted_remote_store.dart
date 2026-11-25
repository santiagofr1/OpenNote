import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'e2e_crypto.dart';
import 'remote_store.dart';
import 'sync_paths.dart';

/// `crypto.json` de la nube cambió (otro dispositivo activó, desactivó o rehízo el cifrado): hay que volver a leerlo.
class VaultChangedException extends RemoteException {
  const VaultChangedException([super.message = 'Cambió la configuración de cifrado de la nube']);
}

/// La nube está cifrada y acá no hay una clave que sirva: falta la frase.
class CryptoLockedException extends RemoteException {
  const CryptoLockedException([super.message = 'La nube está cifrada: ingresá la frase en Sincronización > Cifrado']);
}

/// ruta → (hash del archivo CIFRADO que hay en la nube, hash del CLARO que contiene). Es lo que permite que el motor
/// de sincronización siga comparando hashes de lo claro (ver [EncryptedRemoteStore]). Se guarda en disco para no tener
/// que bajar y descifrar todo cada vez que arranca la app.
class HashCache {
  final Map<String, ({String cipher, String plain})> entries = {};

  /// Se llama con el JSON nuevo cada vez que cambia (para guardarlo en disco).
  Future<void> Function(String json)? persist;
  bool _dirty = false;

  HashCache([Map? json]) {
    for (final e in (json ?? const {}).entries) {
      final v = e.value;
      if (v is List && v.length == 2) entries[e.key as String] = (cipher: v[0] as String, plain: v[1] as String);
    }
  }

  factory HashCache.parse(String? text) {
    try {
      return HashCache(text == null ? null : jsonDecode(text) as Map);
    } catch (_) {
      return HashCache();
    }
  }

  void set(String path, String cipher, String plain) {
    final cur = entries[path];
    if (cur != null && cur.cipher == cipher && cur.plain == plain) return;
    entries[path] = (cipher: cipher, plain: plain);
    _dirty = true;
  }

  void remove(String path) {
    if (entries.remove(path) != null) _dirty = true;
  }

  void retainOnly(Set<String> paths) {
    final before = entries.length;
    entries.removeWhere((k, _) => !paths.contains(k));
    if (entries.length != before) _dirty = true;
  }

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    await persist?.call(jsonEncode({for (final e in entries.entries) e.key: [e.value.cipher, e.value.plain]}));
  }
}

String _md5(List<int> b) => md5.convert(b).toString();

/// La nube todavía NO está cifrada y este dispositivo lo sabe: pasa todo tal cual, pero si aparece `crypto.json`
/// (otro dispositivo activó el cifrado) corta con [VaultChangedException], para no mezclar archivos en claro con
/// cifrados. Oculta `crypto.json` del listado.
class PlainRemoteStore implements RemoteStore, PurgingRemoteStore {
  PlainRemoteStore(this.inner);
  final RemoteStore inner;

  @override
  Future<RemoteChanges> changes(String? token) async {
    final ch = await inner.changes(token);
    if (ch.files.any((f) => f.path == kCryptoFile)) throw const VaultChangedException();
    return ch;
  }

  @override
  Future<Uint8List> download(String path) => inner.download(path);
  @override
  Future<RemoteFile> upload(String path, Uint8List bytes, {String? ifRemoteMd5}) =>
      inner.upload(path, bytes, ifRemoteMd5: ifRemoteMd5);
  @override
  Future<void> delete(String path) => inner.delete(path);
  @override
  Future<void> createFolder(String path) => inner.createFolder(path);

  @override
  Future<void> purge(String path) => purgeOrDelete(inner, path);
}

/// Decorador de [RemoteStore] que cifra al subir y descifra al bajar: lo de abajo ([inner], por ejemplo Drive) solo ve
/// archivos cifrados. Las RUTAS no se cifran (son ids al azar, ver docs/SYNC.md).
///
/// LOS HASHES. El motor compara el md5 de lo LOCAL (claro) con el md5 que dice el remoto. El del remoto sería el del
/// texto cifrado, que cambia en cada subida (nonce al azar) y nunca coincide con el claro: el motor vería conflictos
/// todo el tiempo. Por eso este decorador le habla al motor SIEMPRE en hashes del claro:
///  - al subir, calcula el md5 del claro y se acuerda de (md5 del cifrado que quedó en la nube → md5 del claro);
///  - al listar cambios, traduce el md5 del cifrado que informa la nube con ese recuerdo ([HashCache]). Si no lo conoce
///    (archivo subido por otro dispositivo) lo baja y lo descifra UNA vez, y lo deja anotado (y guardado en disco);
///  - el `ifRemoteMd5` que manda el motor (claro) se traduce al del cifrado antes de pasárselo a [inner].
/// Así una subida propia, que vuelve en el próximo delta con otro md5 cifrado, sigue figurando con el mismo hash claro.
/// Lo que se descifra al listar se guarda un rato (poco) para que el `download` del motor no lo baje dos veces.
///
/// Un archivo de la nube que no está cifrado o no descifra con esta clave corta la pasada con
/// [CorruptEncryptedException]: no se lo ignora, porque el motor lo tomaría por "borrado en la nube" y borraría el
/// archivo local.
///
/// `crypto.json` no se le muestra al motor. Si cambia ([VaultChangedException]) o la carpeta apareció vacía, se
/// repone (para no subir nunca nada sin cifrar).
class EncryptedRemoteStore implements RemoteStore, PurgingRemoteStore {
  EncryptedRemoteStore(this.inner, this.vault, this.info, {required this.cache, this.vaultMd5});
  final RemoteStore inner;
  final Vault vault;

  /// Lo que dice `crypto.json` (para reponerlo y para detectar que otro dispositivo lo cambió).
  final VaultInfo info;
  final HashCache cache;

  /// md5 del `crypto.json` que se conoce de la nube.
  String? vaultMd5;

  static const _prefetchMax = 16 * 1024 * 1024;
  final _prefetched = <String, Uint8List>{};
  int _prefetchedBytes = 0;

  void _keep(String path, Uint8List plain) {
    if (plain.length > _prefetchMax ~/ 2) return;
    while (_prefetchedBytes + plain.length > _prefetchMax && _prefetched.isNotEmpty) {
      final k = _prefetched.keys.first;
      _prefetchedBytes -= _prefetched.remove(k)!.length;
    }
    _prefetched[path] = plain;
    _prefetchedBytes += plain.length;
  }

  Future<void> _checkVaultFile(List<RemoteFile> files, bool full, List<String> removed) async {
    final mine = files.where((f) => f.path == kCryptoFile);
    final gone = removed.contains(kCryptoFile) || (full && mine.isEmpty);
    if (gone) {
      // la carpeta se borró (o alguien borró crypto.json): se repone el nuestro antes de subir cualquier cosa
      try {
        final rf = await inner.upload(kCryptoFile, info.toBytes(), ifRemoteMd5: null);
        vaultMd5 = rf.md5;
      } on RemoteConflictException {
        throw const VaultChangedException();
      }
      return;
    }
    if (mine.isEmpty) return;
    final f = mine.first;
    if (f.md5 == vaultMd5) return;
    final cur = VaultInfo.parse(await inner.download(kCryptoFile));
    final same = base64Encode(cur.salt) == base64Encode(info.salt) &&
        base64Encode(cur.verifier) == base64Encode(info.verifier) &&
        cur.migrating == info.migrating;
    if (!same) throw const VaultChangedException();
    vaultMd5 = f.md5;
  }

  @override
  Future<RemoteChanges> changes(String? token) async {
    final ch = await inner.changes(token);
    await _checkVaultFile(ch.files, ch.full, ch.removed);
    final out = <RemoteFile>[];
    for (final f in ch.files) {
      if (f.path == kCryptoFile) continue;
      if (!isSyncPath(f.path)) {
        out.add(f);
        continue;
      }
      final e = cache.entries[f.path];
      if (e != null && f.md5.isNotEmpty && e.cipher == f.md5) {
        out.add(RemoteFile(f.path, e.plain, f.modified));
        continue;
      }
      final raw = await inner.download(f.path);
      final plain = await vault.decrypt(f.path, raw);
      final h = _md5(plain);
      cache.set(f.path, _md5(raw), h);
      _keep(f.path, plain);
      out.add(RemoteFile(f.path, h, f.modified));
    }
    if (ch.full) cache.retainOnly({for (final f in ch.files) f.path});
    for (final p in ch.removed) {
      cache.remove(p);
      _prefetchedBytes -= _prefetched.remove(p)?.length ?? 0;
    }
    await cache.flush();
    return RemoteChanges(files: out, removed: [for (final p in ch.removed) if (p != kCryptoFile) p], nextToken: ch.nextToken, full: ch.full);
  }

  @override
  Future<Uint8List> download(String path) async {
    final kept = _prefetched.remove(path);
    if (kept != null) {
      _prefetchedBytes -= kept.length;
      return kept;
    }
    final raw = await inner.download(path);
    final plain = await vault.decrypt(path, raw);
    cache.set(path, _md5(raw), _md5(plain));
    await cache.flush();
    return plain;
  }

  /// El md5 del CIFRADO que corresponde a que en la nube haya, ahora, un claro con hash [plainMd5]; null si no se sabe.
  /// Si la caché no lo conoce, baja el archivo y lo descifra para saberlo.
  Future<String?> _cipherFor(String path, String plainMd5) async {
    var e = cache.entries[path];
    if (e == null || e.plain != plainMd5) {
      try {
        final raw = await inner.download(path);
        final plain = await vault.decrypt(path, raw);
        cache.set(path, _md5(raw), _md5(plain));
        e = cache.entries[path];
      } on RemoteNotFoundException {
        return null;
      }
    }
    return e != null && e.plain == plainMd5 ? e.cipher : null;
  }

  @override
  Future<RemoteFile> upload(String path, Uint8List bytes, {String? ifRemoteMd5}) async {
    String? innerExpect;
    if (ifRemoteMd5 != null) {
      innerExpect = await _cipherFor(path, ifRemoteMd5);
      if (innerExpect == null) throw const RemoteConflictException();
    }
    final rf = await inner.upload(path, await vault.encrypt(path, bytes), ifRemoteMd5: innerExpect);
    final plainMd5 = _md5(bytes);
    cache.set(path, rf.md5, plainMd5);
    await cache.flush();
    return RemoteFile(path, plainMd5, rf.modified);
  }

  @override
  Future<void> delete(String path) async {
    await inner.delete(path);
    cache.remove(path);
    await cache.flush();
  }

  @override
  Future<void> purge(String path) async {
    await purgeOrDelete(inner, path);
    cache.remove(path);
    await cache.flush();
  }

  @override
  Future<void> createFolder(String path) => inner.createFolder(path);
}
