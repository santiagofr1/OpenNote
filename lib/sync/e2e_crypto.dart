import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'remote_store.dart';

/// Cifrado de extremo a extremo de los archivos que se suben a la nube (ver docs/SYNC.md, "End-to-end encryption").
///
///  - Clave: Argon2id sobre la frase del usuario con una sal al azar (guardada en `crypto.json`, no es secreta).
///  - Cada archivo: XChaCha20-Poly1305 con un nonce al azar de 24 bytes (no se repite en la práctica).
///  - Formato de un archivo cifrado: `ONCR` + versión (1 byte) + nonce (24) + texto cifrado + etiqueta de 16 bytes.
///  - Datos asociados (AAD): versión + ruta del archivo, así un archivo cifrado no sirve movido a otra ruta.

/// Nombre del archivo de la nube con la sal, los parámetros del KDF y el verificador (va en claro, no es secreto).
const kCryptoFile = 'crypto.json';

const _magic = [0x4F, 0x4E, 0x43, 0x52]; // "ONCR"
const _formatVersion = 1;
const _headerLen = 5;
const _nonceLen = 24;
const _macLen = 16;

/// La frase no sirve para abrir la nube (o el archivo no se pudo descifrar con esta clave).
class WrongPassphraseException extends RemoteException {
  const WrongPassphraseException([super.message = 'La frase de cifrado es incorrecta']);
}

/// Un archivo de la nube no está cifrado como se esperaba o está dañado.
class CorruptEncryptedException extends RemoteException {
  const CorruptEncryptedException(super.message);
}

/// Parámetros de Argon2id. [memoryKiB] en KiB. Los de fábrica ([KdfParams.standard]) se fijaron midiendo en Dart puro
/// (ver docs/SYNC.md).
class KdfParams {
  final int memoryKiB, iterations, parallelism;
  const KdfParams(this.memoryKiB, this.iterations, this.parallelism);
  static const standard = KdfParams(65536, 3, 1); // 64 MiB, 3 pasadas, 1 hilo (RFC 9106, segunda opción)

  /// Para los tests (rápido, nada seguro).
  static const fast = KdfParams(8, 1, 1);

  factory KdfParams.fromJson(Map j) => KdfParams(j['memoryKiB'] as int, j['iterations'] as int, j['parallelism'] as int);
  Map<String, dynamic> toJson() => {'memoryKiB': memoryKiB, 'iterations': iterations, 'parallelism': parallelism};
}

/// Hacia dónde va un cambio de cifrado que quedó a medias (ver `crypto.json`, campo `migrating`).
enum CryptoMigration { encrypting, decrypting }

/// El contenido de `crypto.json`: lo que hace falta (además de la frase) para armar la clave en otro dispositivo.
class VaultInfo {
  final int version;
  final KdfParams kdf;
  final Uint8List salt;

  /// Un texto conocido cifrado con la clave: descifrarlo bien prueba que la frase es la correcta.
  final Uint8List verifier;

  /// Si hay un cambio de cifrado a medias (se están subiendo los archivos cifrados / descifrados de a uno).
  final CryptoMigration? migrating;
  const VaultInfo({required this.version, required this.kdf, required this.salt, required this.verifier, this.migrating});

  factory VaultInfo.fromJson(Map j) {
    if (j['app'] != 'opennote' || j['kdf'] is! Map) throw const CorruptEncryptedException('crypto.json inválido');
    final k = j['kdf'] as Map;
    if (k['name'] != 'argon2id' || j['cipher'] != 'xchacha20-poly1305') {
      throw const CorruptEncryptedException('La nube usa un cifrado que esta versión de Vynote no conoce');
    }
    final v = j['version'] as int;
    if (v > _formatVersion) throw const CorruptEncryptedException('La nube se cifró con una versión más nueva de Vynote');
    final m = j['migrating'];
    return VaultInfo(
      version: v,
      kdf: KdfParams.fromJson(k),
      salt: base64Decode(j['salt'] as String),
      verifier: base64Decode(j['verifier'] as String),
      migrating: m == null ? null : CryptoMigration.values.byName(m as String),
    );
  }

  static VaultInfo parse(List<int> bytes) {
    try {
      return VaultInfo.fromJson(jsonDecode(utf8.decode(bytes)) as Map);
    } on RemoteException {
      rethrow;
    } catch (_) {
      throw const CorruptEncryptedException('crypto.json inválido');
    }
  }

  VaultInfo withMigrating(CryptoMigration? m) =>
      VaultInfo(version: version, kdf: kdf, salt: salt, verifier: verifier, migrating: m);

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert({
        'app': 'opennote',
        'version': version,
        'cipher': 'xchacha20-poly1305',
        'kdf': {'name': 'argon2id', ...kdf.toJson()},
        'salt': base64Encode(salt),
        'verifier': base64Encode(verifier),
        'migrating': migrating?.name,
      })));
}

/// ¿Estos bytes tienen la cabecera de un archivo cifrado de Vynote?
bool hasEncryptedHeader(List<int> b) =>
    b.length >= _headerLen + _nonceLen + _macLen && b[0] == _magic[0] && b[1] == _magic[1] && b[2] == _magic[2] && b[3] == _magic[3];

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
}

/// Deriva la clave de 32 bytes. Argon2id en Dart puro tarda: va en otro isolate para no trabar la interfaz.
Future<Uint8List> deriveKey(String passphrase, Uint8List salt, KdfParams p) => Isolate.run(() async {
      final k = await Argon2id(parallelism: p.parallelism, memory: p.memoryKiB, iterations: p.iterations, hashLength: 32)
          .deriveKeyFromPassword(password: passphrase, nonce: salt);
      return Uint8List.fromList(await k.extractBytes());
    });

/// Una clave ya derivada, con la que se cifra y descifra archivo por archivo.
class Vault {
  Vault(this.key) : assert(key.length == 32);

  /// La clave de 32 bytes (es lo que se guarda en el almacenamiento seguro).
  final Uint8List key;
  static final _algo = Xchacha20.poly1305Aead();
  static const _verifierText = 'opennote-e2e-ok';

  /// Crea una nube cifrada nueva: sal al azar, clave de [passphrase] y verificador.
  static Future<(Vault, VaultInfo)> create(String passphrase, {KdfParams kdf = KdfParams.standard}) async {
    final salt = _randomBytes(16);
    final vault = Vault(await deriveKey(passphrase, salt, kdf));
    final verifier = await vault.encrypt(kCryptoFile, Uint8List.fromList(utf8.encode(_verifierText)));
    return (vault, VaultInfo(version: _formatVersion, kdf: kdf, salt: salt, verifier: verifier));
  }

  /// Abre con la frase; [WrongPassphraseException] si no es la de [info].
  static Future<Vault> open(VaultInfo info, String passphrase) async {
    final v = Vault(await deriveKey(passphrase, info.salt, info.kdf));
    if (!await v.checks(info)) throw const WrongPassphraseException();
    return v;
  }

  /// ¿Esta clave abre la nube de [info]? (Barato: no vuelve a derivar nada.)
  Future<bool> checks(VaultInfo info) async {
    try {
      return utf8.decode(await decrypt(kCryptoFile, info.verifier)) == _verifierText;
    } catch (_) {
      return false;
    }
  }

  List<int> _aad(String path) => utf8.encode('opennote-e2e/$_formatVersion\n$path');

  /// Cifra [plain] para guardarlo en [path]. Cada llamada usa un nonce nuevo al azar.
  Future<Uint8List> encrypt(String path, Uint8List plain) async {
    final nonce = _randomBytes(_nonceLen);
    final box = await _algo.encrypt(plain, secretKey: SecretKey(key), nonce: nonce, aad: _aad(path));
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_formatVersion)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.takeBytes();
  }

  /// Descifra lo que [encrypt] guardó en [path]. [CorruptEncryptedException] si no es un archivo cifrado o fue
  /// alterado / es de otra ruta / es de otra clave.
  Future<Uint8List> decrypt(String path, Uint8List data) async {
    if (!hasEncryptedHeader(data)) throw CorruptEncryptedException('$path no está cifrado');
    if (data[4] != _formatVersion) throw CorruptEncryptedException('$path: versión de cifrado desconocida');
    final nonce = data.sublist(_headerLen, _headerLen + _nonceLen);
    final cipher = data.sublist(_headerLen + _nonceLen, data.length - _macLen);
    final mac = Mac(data.sublist(data.length - _macLen));
    try {
      final plain = await _algo.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(key), aad: _aad(path));
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw CorruptEncryptedException('$path no se pudo descifrar (dañado o de otra clave)');
    }
  }
}
