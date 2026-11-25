import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'e2e_crypto.dart';
import 'encrypted_remote_store.dart';
import 'google_auth.dart' show TokenStore, SecureTokenStore;
import 'remote_store.dart';
import 'sync_paths.dart';
import 'sync_state.dart';

enum CryptoState {
  /// Todavía no se miró la nube.
  unknown,

  /// La nube no está cifrada.
  off,

  /// La nube está cifrada y este dispositivo tiene la clave.
  on,

  /// La nube está cifrada y acá falta la frase (o la clave guardada ya no sirve).
  locked,
}

/// Lo que sabe este dispositivo del cifrado de extremo a extremo de la nube: si está activo, la clave (en el
/// almacenamiento seguro, nunca en texto plano en disco) y los cambios (activar, desactivar, desbloquear).
///
/// Cada pasada de sincronización pasa el remoto por [wrap]: devuelve el remoto que el motor tiene que usar (cifrado o
/// no). Las operaciones largas ([enable], [disable], [unlock]) las corre el [SyncController] cuando no hay ninguna
/// pasada en curso.
/// Paso de una operación larga de cifrado (ver [SyncCrypto.step]).
enum CryptoStep { deriving, syncBeforeEncrypt, syncBeforeDecrypt, encrypting, decrypting }

class SyncCrypto extends ChangeNotifier {
  SyncCrypto({required this.store, TokenStore? tokens, this.kdf = KdfParams.standard})
      : tokens = tokens ?? const SecureTokenStore();
  final Storage store;
  final TokenStore tokens;

  /// Parámetros de Argon2id para activar el cifrado (los tests usan [KdfParams.fast]).
  final KdfParams kdf;

  static const keyName = 'opennote.sync.e2e.key';

  CryptoState state = CryptoState.unknown;

  /// Texto de avance de una operación larga (null: no hay).
  String? progress;

  /// Paso de la operación larga en curso (para mostrarlo en el idioma de la app); [stepDone] de [stepTotal] al
  /// cifrar o descifrar archivos.
  CryptoStep? step;
  int stepDone = 0, stepTotal = 0;

  Vault? _vault;
  VaultInfo? _info;
  String? _vaultMd5;
  HashCache? _cache;

  bool get enabled => state == CryptoState.on;
  bool get locked => state == CryptoState.locked;

  void _set(CryptoState s, {String? progressText}) {
    state = s;
    progress = progressText;
    step = null;
    notifyListeners();
  }

  /// Borra el texto de avance (al terminar una operación, bien o mal).
  void clearProgress() {
    if (progress != null) _progress(null);
  }

  void _progress(String? t, {CryptoStep? step, int done = 0, int total = 0}) {
    progress = t;
    this.step = t == null ? null : step;
    stepDone = done;
    stepTotal = total;
    notifyListeners();
  }

  // ---------- el remoto de cada pasada ----------

  /// El remoto que tiene que usar el motor: el de la nube tal cual (si no está cifrada) o el decorador que cifra.
  /// [CryptoLockedException] si la nube está cifrada y falta la frase.
  Future<RemoteStore> wrap(RemoteStore raw) async {
    if (state == CryptoState.unknown || state == CryptoState.locked) await _detect(raw);
    if (state == CryptoState.locked) throw const CryptoLockedException();
    if (state == CryptoState.on && _info!.migrating != null) await _complete(raw);
    if (state == CryptoState.off) return PlainRemoteStore(raw);
    return EncryptedRemoteStore(raw, _vault!, _info!, cache: await _loadCache(), vaultMd5: _vaultMd5);
  }

  /// Hay que volver a mirar `crypto.json` en la próxima pasada (lo cambió otro dispositivo).
  void invalidate() {
    if (state != CryptoState.unknown) _set(CryptoState.unknown);
  }

  /// Al desconectar de Google: se olvida la clave de este dispositivo (la frase se vuelve a pedir al reconectar).
  Future<void> forget() async {
    try {
      await tokens.delete(keyName);
    } catch (_) {} // sin almacenamiento seguro (tests, Linux sin llavero): no hay nada guardado que borrar
    _vault = _info = null;
    _vaultMd5 = null;
    _cache = null;
    await _deleteCache();
    _set(CryptoState.unknown);
  }

  Future<void> _detect(RemoteStore raw) async {
    Uint8List? bytes;
    try {
      bytes = await raw.download(kCryptoFile);
    } on RemoteNotFoundException {
      bytes = null;
    }
    if (bytes == null) {
      _vault = _info = null;
      _vaultMd5 = null;
      return _set(CryptoState.off);
    }
    final info = VaultInfo.parse(bytes);
    _info = info;
    _vaultMd5 = md5.convert(bytes).toString();
    final v = await _storedVault();
    if (v != null && await v.checks(info)) {
      _vault = v;
      return _set(CryptoState.on);
    }
    _vault = null;
    _set(CryptoState.locked);
  }

  Future<Vault?> _storedVault() async {
    try {
      final raw = await tokens.read(keyName);
      if (raw == null) return null;
      return Vault(Uint8List.fromList(base64Decode(raw)));
    } catch (_) {
      return null;
    }
  }

  // ---------- caché de hashes (en disco, junto a sync_state.json) ----------

  Future<HashCache> _loadCache() async {
    if (_cache != null) return _cache!;
    String? text;
    try {
      text = await store.syncFile(kSyncCryptoCacheFile).readAsString();
    } catch (_) {}
    return _cache = HashCache.parse(text)..persist = (j) => store.writeSyncFile(kSyncCryptoCacheFile, utf8.encode(j));
  }

  Future<void> _deleteCache() async {
    try {
      await store.deleteSyncFile(kSyncCryptoCacheFile);
    } catch (_) {}
  }

  // ---------- operaciones ----------

  /// Activa el cifrado con [passphrase]: pasada normal (para tener todo al día), `crypto.json` con la marca de "cifrando",
  /// y cada archivo de la nube se baja, se borra de verdad y se vuelve a subir cifrado. [syncPass] corre una pasada
  /// del motor con el remoto que se le dé.
  Future<void> enable(RemoteStore raw, String passphrase, Future<void> Function(RemoteStore) syncPass) async {
    await _detect(raw);
    if (state == CryptoState.on) return;
    if (state == CryptoState.locked) throw const CryptoLockedException();
    _progress('Derivando la clave (puede tardar unos segundos)…', step: CryptoStep.deriving);
    final (vault, info0) = await Vault.create(passphrase, kdf: kdf);
    _progress('Sincronizando antes de cifrar…', step: CryptoStep.syncBeforeEncrypt);
    await syncPass(PlainRemoteStore(raw));
    final info = info0.withMigrating(CryptoMigration.encrypting);
    try {
      final rf = await raw.upload(kCryptoFile, info.toBytes(), ifRemoteMd5: null);
      _vaultMd5 = rf.md5;
    } on RemoteConflictException {
      invalidate();
      throw const RemoteException('Otro dispositivo activó el cifrado al mismo tiempo. Ingresá su frase.',
          kind: SyncError.cryptoOtherDevice);
    }
    await tokens.write(keyName, base64Encode(vault.key));
    _vault = vault;
    _info = info;
    _cache = HashCache()..persist = (j) => store.writeSyncFile(kSyncCryptoCacheFile, utf8.encode(j));
    _set(CryptoState.on);
    await _complete(raw);
  }

  /// Desactiva el cifrado: pasada (cifrada), `crypto.json` con la marca de "descifrando", y cada archivo se baja,
  /// se descifra, se borra de verdad y se sube en claro; al final se borra `crypto.json` y la clave de este dispositivo.
  Future<void> disable(RemoteStore raw, Future<void> Function(RemoteStore) syncPass) async {
    await _detect(raw);
    if (state == CryptoState.off) return;
    if (state == CryptoState.locked) throw const CryptoLockedException();
    _progress('Sincronizando antes de descifrar…', step: CryptoStep.syncBeforeDecrypt);
    await syncPass(await wrap(raw));
    final info = _info!.withMigrating(CryptoMigration.decrypting);
    final rf = await raw.upload(kCryptoFile, info.toBytes(), ifRemoteMd5: _vaultMd5);
    _vaultMd5 = rf.md5;
    _info = info;
    await _complete(raw);
  }

  /// La nube está cifrada y se tiene la frase: arma la clave, la verifica y la guarda.
  Future<void> unlock(RemoteStore raw, String passphrase) async {
    await _detect(raw);
    if (state == CryptoState.off) throw const RemoteException('La nube no está cifrada', kind: SyncError.cloudNotEncrypted);
    if (state == CryptoState.on) return;
    _progress('Derivando la clave (puede tardar unos segundos)…', step: CryptoStep.deriving);
    final v = await Vault.open(_info!, passphrase); // WrongPassphraseException si no es
    await tokens.write(keyName, base64Encode(v.key));
    _vault = v;
    _set(CryptoState.on);
  }

  /// Termina el cambio que marca `crypto.json` (`migrating`): convierte los archivos que falten. Se puede repetir
  /// (si se cortó a la mitad, la próxima pasada lo retoma).
  Future<void> _complete(RemoteStore raw) async {
    final vault = _vault!;
    var info = _info!;
    final dir = info.migrating!;
    // Si algo falla a la mitad, un archivo puede haber quedado borrado de la nube: la base de la sincronización ya no
    // vale (si no, el motor lo tomaría por un borrado en la nube y borraría el local). Sin base, se vuelve a subir.
    await SyncState.clear(store);
    try {
      final cache = dir == CryptoMigration.encrypting ? (_cache ??= await _loadCache()) : null;
      final enc = cache == null ? null : EncryptedRemoteStore(raw, vault, info, cache: cache, vaultMd5: _vaultMd5);
      final paths = [for (final f in (await raw.changes(null)).files) if (isSyncPath(f.path)) f.path]..sort();
      for (var i = 0; i < paths.length; i++) {
        final p = paths[i];
        _progress('${dir == CryptoMigration.encrypting ? 'Cifrando' : 'Descifrando'} ${i + 1}/${paths.length}…',
            step: dir == CryptoMigration.encrypting ? CryptoStep.encrypting : CryptoStep.decrypting, done: i + 1, total: paths.length);
        final bytes = await raw.download(p);
        final isEnc = hasEncryptedHeader(bytes);
        if (dir == CryptoMigration.encrypting) {
          if (isEnc) continue;
          await purgeOrDelete(raw, p);
          await enc!.upload(p, bytes, ifRemoteMd5: null);
        } else {
          if (!isEnc) continue;
          final plain = await vault.decrypt(p, bytes);
          await purgeOrDelete(raw, p);
          await raw.upload(p, plain, ifRemoteMd5: null);
        }
      }
      if (dir == CryptoMigration.encrypting) {
        info = info.withMigrating(null);
        final rf = await raw.upload(kCryptoFile, info.toBytes(), ifRemoteMd5: _vaultMd5);
        _vaultMd5 = rf.md5;
        _info = info;
        _set(CryptoState.on);
      } else {
        await purgeOrDelete(raw, kCryptoFile);
        await tokens.delete(keyName);
        _vault = _info = null;
        _vaultMd5 = null;
        _cache = null;
        await _deleteCache();
        _set(CryptoState.off);
      }
    } catch (e) {
      await SyncState.clear(store);
      _progress(null);
      rethrow;
    }
  }
}
