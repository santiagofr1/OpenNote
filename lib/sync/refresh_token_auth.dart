import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'drive_remote_store.dart';
import 'google_auth.dart' show TokenStore;
import 'remote_store.dart';
import 'sync_backend.dart';

/// Refresh token propio para el segundo plano en Android.
///
/// `google_sign_in` en Android necesita una Activity para retomar la sesión, y en la tarea de fondo (otro isolate, sin UI)
/// no hay. Entonces, con la app en primer plano, se le pide a `google_sign_in` un `serverAuthCode`, se canjea por un
/// refresh token en el endpoint de Google con el cliente Web, y ese token se guarda en el almacenamiento seguro. La tarea
/// de fondo lo usa directo (sin `google_sign_in`) para sacar tokens de acceso y hablar con Drive.
///
/// Si falta el secreto del cliente Web ([clientSecret] vacío) no se hace nada de esto y el segundo plano no anda.
class RefreshTokenAuth {
  RefreshTokenAuth(
    this._tokens, {
    required this.clientId,
    required this.clientSecret,
    http.Client? httpClient,
    DateTime Function()? now,
  })  : _http = httpClient ?? http.Client(),
        _now = now ?? DateTime.now;
  final TokenStore _tokens;
  final String clientId, clientSecret;
  final http.Client _http;
  final DateTime Function() _now;

  static const kRefreshKey = 'opennote.google.android.refresh';
  static const kAccountKey = 'opennote.google.android.account';
  static final _tokenUrl = Uri.parse('https://oauth2.googleapis.com/token');
  static final _revokeUrl = Uri.parse('https://oauth2.googleapis.com/revoke');

  String? _access;
  DateTime _accessUntil = DateTime.utc(1970);

  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  Future<bool> hasToken() async => (await _tokens.read(kRefreshKey)) != null;

  /// Canjea el [serverAuthCode] por un refresh token y lo guarda junto con la [account]. Devuelve false si Google no
  /// devolvió refresh token (no se guarda nada). Lanza [RemoteException] si el canje falla.
  Future<bool> exchangeCode(String serverAuthCode, String account) async {
    if (!configured) return false;
    final res = await _post(_tokenUrl, {
      'code': serverAuthCode,
      'client_id': clientId,
      'client_secret': clientSecret,
      'grant_type': 'authorization_code',
      'redirect_uri': '', // los códigos de servidor de Android no llevan redirección
    });
    final j = _json(res);
    if (res.statusCode != 200) throw RemoteException('Google rechazó el canje del código (${j['error'] ?? res.statusCode})');
    final refresh = j['refresh_token'];
    if (refresh is! String || refresh.isEmpty) return false;
    await _tokens.write(kRefreshKey, refresh);
    await _tokens.write(kAccountKey, account);
    _cache(j);
    return true;
  }

  /// Un token de acceso vigente (renueva con el refresh token cuando falta poco). Si Google rechaza el refresh token
  /// (`invalid_grant`: revocado o vencido) lo borra y lanza [RemoteAuthException]: la app lo vuelve a pedir en primer plano.
  Future<String> accessToken() async {
    final a = _access;
    if (a != null && _now().isBefore(_accessUntil.subtract(const Duration(minutes: 1)))) return a;
    final refresh = await _tokens.read(kRefreshKey);
    if (refresh == null) throw const RemoteAuthException('No hay token para el segundo plano');
    final res = await _post(_tokenUrl, {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    final j = _json(res);
    if (res.statusCode == 200 && j['access_token'] is String) {
      _cache(j);
      return _access!;
    }
    if (j['error'] == 'invalid_grant') {
      await clear();
      throw const RemoteAuthException('El permiso de segundo plano venció');
    }
    throw RemoteException('No se pudo renovar el acceso a Google (${j['error'] ?? res.statusCode})');
  }

  /// La sesión para la tarea de fondo, o null si no hay refresh token o Google lo rechazó (se borra).
  Future<SyncSession?> backgroundSession() async {
    if (!configured) return null;
    final refresh = await _tokens.read(kRefreshKey);
    final account = await _tokens.read(kAccountKey);
    if (refresh == null || account == null) return null;
    try {
      await accessToken(); // si el token está rechazado se entera ya y no arma nada
    } on RemoteAuthException {
      return null;
    }
    return SyncSession(account, DriveRemoteStore(_AccessClient(this)));
  }

  /// Borra el token guardado.
  Future<void> clear() async {
    _access = null;
    _accessUntil = DateTime.utc(1970);
    await _tokens.delete(kRefreshKey);
    await _tokens.delete(kAccountKey);
  }

  /// Al desconectar: intenta revocarlo en Google (sin fallar si no hay red) y lo borra.
  Future<void> revokeAndClear() async {
    final refresh = await _tokens.read(kRefreshKey);
    await clear();
    if (refresh == null) return;
    try {
      await _http.post(_revokeUrl, body: {'token': refresh}).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _cache(Map j) {
    final a = j['access_token'];
    if (a is String) {
      _access = a;
      _accessUntil = _now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    }
  }

  Future<http.Response> _post(Uri url, Map<String, String> body) async {
    try {
      return await _http.post(url, body: body).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const RemoteOfflineException();
    } on http.ClientException {
      throw const RemoteOfflineException();
    }
  }

  static Map _json(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      return j is Map ? j : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// Cliente HTTP que pone el token de acceso (renovado con el refresh token propio) en cada pedido.
class _AccessClient extends http.BaseClient {
  _AccessClient(this._auth);
  final RefreshTokenAuth _auth;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer ${await _auth.accessToken()}';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
