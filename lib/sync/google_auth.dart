import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'drive_remote_store.dart';
import 'google_config.dart';
import 'remote_store.dart';
import 'secret_service.dart';
import 'sync_backend.dart';

/// Con `drive.file` la app solo ve lo que ella misma crea (la carpeta `OpenNote` y su contenido).
const kDriveScope = 'https://www.googleapis.com/auth/drive.file';

/// Dónde se guardan los tokens. La implementación real usa el almacenamiento seguro del sistema (Keystore en Android,
/// libsecret en Linux).
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _s = FlutterSecureStorage();
  // Sin llavero en Linux (ver SecretService) no se toca el plugin: leer da null, borrar no hace nada y guardar
  // avisa con un error que la pantalla muestra.
  @override
  Future<String?> read(String key) async => await SecretService.available() ? _s.read(key: key) : null;
  @override
  Future<void> write(String key, String value) async {
    if (!await SecretService.available()) throw const RemoteException(kNoSecretServiceMessage);
    await _s.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    if (await SecretService.available()) await _s.delete(key: key);
  }
}

/// Login con Google, con dos caminos:
///  - Android: `google_sign_in` (selector de cuentas del sistema), permiso `drive.file`. El token de acceso lo maneja
///    Google Play services; la app no guarda ninguno.
///  - Linux / escritorio: `googleapis_auth`, flujo de app instalada (navegador + servidor local en 127.0.0.1 + PKCE).
///    El refresh token se guarda en el almacenamiento seguro y el token de acceso se renueva solo.
/// En otras plataformas [configured] es false.
class GoogleBackend implements SyncBackend {
  GoogleBackend([this._tokens = const SecureTokenStore()]);
  final TokenStore _tokens;

  static const _kDesktopKey = 'opennote.google.desktop.credentials';
  static const _kDesktopMail = 'opennote.google.desktop.account';
  static bool _androidInit = false;

  @override
  bool get configured => GoogleConfig.ready;

  @override
  String get missingConfig => GoogleConfig.missing;

  bool get _android => Platform.isAndroid;

  @override
  Future<SyncSession?> restore() async {
    if (!configured) return null;
    return _android ? _restoreAndroid() : _restoreDesktop();
  }

  @override
  Future<SyncSession> signIn() async {
    if (!configured) throw const RemoteException('Falta configurar el proyecto de Google');
    return _android ? _signInAndroid() : _signInDesktop();
  }

  @override
  Future<void> signOut() async {
    if (_android) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    } else {
      await _tokens.delete(_kDesktopKey);
      await _tokens.delete(_kDesktopMail);
    }
  }

  // ------------------------------------------------------------------ Android

  Future<void> _initAndroid() async {
    if (_androidInit) return;
    await GoogleSignIn.instance.initialize(serverClientId: GoogleConfig.webClientId);
    _androidInit = true;
  }

  Future<SyncSession?> _restoreAndroid() async {
    await _initAndroid();
    final acc = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (acc == null) return null;
    // ¿ya está dado el permiso? Si haría falta preguntar, se pide al conectar a mano
    if (await acc.authorizationClient.authorizationForScopes([kDriveScope]) == null) return null;
    return _androidSession(acc);
  }

  Future<SyncSession> _signInAndroid() async {
    await _initAndroid();
    try {
      final acc = await GoogleSignIn.instance.authenticate(scopeHint: [kDriveScope]);
      await acc.authorizationClient.authorizeScopes([kDriveScope]);
      return _androidSession(acc);
    } on GoogleSignInException catch (e) {
      throw RemoteException(e.code == GoogleSignInExceptionCode.canceled ? 'Se canceló el inicio de sesión' : 'No se pudo iniciar sesión con Google (${e.code.name})');
    }
  }

  SyncSession _androidSession(GoogleSignInAccount acc) {
    final client = _HeadersClient(() async {
      final h = await acc.authorizationClient.authorizationHeaders([kDriveScope]);
      if (h == null) throw const RemoteAuthException();
      return h;
    });
    return SyncSession(acc.email, DriveRemoteStore(client));
  }

  // ------------------------------------------------------------------ Linux / escritorio

  auth.ClientId get _desktopId => auth.ClientId(GoogleConfig.desktopClientId, GoogleConfig.desktopClientSecret);

  Future<SyncSession?> _restoreDesktop() async {
    final raw = await _tokens.read(_kDesktopKey);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map;
    final creds = auth.AccessCredentials(
      // vencido a propósito: en el primer pedido se renueva con el refresh token
      auth.AccessToken('Bearer', '', DateTime.utc(1970)),
      j['refreshToken'] as String,
      [kDriveScope],
    );
    final client = auth.autoRefreshingClient(_desktopId, creds, http.Client());
    final mail = await _tokens.read(_kDesktopMail) ?? 'cuenta de Google';
    return SyncSession(mail, DriveRemoteStore(client));
  }

  Future<SyncSession> _signInDesktop() async {
    final client = await auth.clientViaUserConsent(_desktopId, [kDriveScope], (url) async {
      // abre el navegador; Google vuelve a http://localhost:<puerto> y googleapis_auth termina el canje (con PKCE)
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw const RemoteException('No se pudo abrir el navegador');
      }
    });
    final refresh = client.credentials.refreshToken;
    if (refresh == null) {
      client.close();
      throw const RemoteException('Google no devolvió un token de renovación. Probá de nuevo.');
    }
    await _tokens.write(_kDesktopKey, jsonEncode({'refreshToken': refresh}));
    final mail = await _emailOf(client);
    await _tokens.write(_kDesktopMail, mail);
    return SyncSession(mail, DriveRemoteStore(client));
  }

  Future<String> _emailOf(http.Client client) async {
    try {
      final about = await drive.DriveApi(client).about.get($fields: 'user(emailAddress)');
      return about.user?.emailAddress ?? 'cuenta de Google';
    } catch (_) {
      return 'cuenta de Google';
    }
  }
}

/// Cliente HTTP que agrega, en cada pedido, los encabezados de autorización que da [_headers] (en Android, un token
/// de acceso fresco de Google Play services).
class _HeadersClient extends http.BaseClient {
  _HeadersClient(this._headers);
  final Future<Map<String, String>> Function() _headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(await _headers());
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
