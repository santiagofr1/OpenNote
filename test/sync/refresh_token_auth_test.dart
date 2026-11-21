import 'dart:convert';

import 'package:apuntes/sync/google_auth.dart';
import 'package:apuntes/sync/refresh_token_auth.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemTokens implements TokenStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

/// El refresh token propio del segundo plano en Android, con Google falso (MockClient).
void main() {
  late _MemTokens tokens;
  late List<http.Request> calls;
  late http.Response Function(http.Request) respond;
  var t = DateTime(2026, 11, 21, 10);

  RefreshTokenAuth auth({String secret = 'sec'}) => RefreshTokenAuth(
        tokens,
        clientId: 'web-id',
        clientSecret: secret,
        httpClient: MockClient((r) async {
          calls.add(r);
          return respond(r);
        }),
        now: () => t,
      );

  http.Response ok(Map j) => http.Response(jsonEncode(j), 200);

  setUp(() {
    tokens = _MemTokens();
    calls = [];
    t = DateTime(2026, 11, 21, 10);
    respond = (_) => ok({'access_token': 'acc1', 'expires_in': 3600, 'refresh_token': 'ref1'});
  });

  test('canje: el código de servidor se cambia por un refresh token y se guarda con la cuenta', () async {
    expect(await auth().exchangeCode('code123', 'a@b.c'), isTrue);
    expect(tokens.m[RefreshTokenAuth.kRefreshKey], 'ref1');
    expect(tokens.m[RefreshTokenAuth.kAccountKey], 'a@b.c');
    final body = calls.single.bodyFields;
    expect(body['grant_type'], 'authorization_code');
    expect(body['code'], 'code123');
    expect(body['client_id'], 'web-id');
    expect(body['client_secret'], 'sec');
  });

  test('canje sin refresh token en la respuesta: no guarda nada; con el canje rechazado lanza', () async {
    respond = (_) => ok({'access_token': 'x', 'expires_in': 3600});
    expect(await auth().exchangeCode('c', 'a@b.c'), isFalse);
    expect(tokens.m, isEmpty);
    respond = (_) => http.Response(jsonEncode({'error': 'invalid_request'}), 400);
    await expectLater(auth().exchangeCode('c', 'a@b.c'), throwsA(isA<RemoteException>()));
  });

  test('sin secreto del cliente Web no hace nada (el resto de la app sigue como siempre)', () async {
    final a = auth(secret: '');
    expect(a.configured, isFalse);
    expect(await a.exchangeCode('c', 'a@b.c'), isFalse);
    expect(await a.backgroundSession(), isNull);
    expect(calls, isEmpty);
  });

  test('fondo: usa el refresh token guardado para sacar el token de acceso y lo reutiliza hasta que vence', () async {
    tokens.m[RefreshTokenAuth.kRefreshKey] = 'ref1';
    tokens.m[RefreshTokenAuth.kAccountKey] = 'a@b.c';
    final a = auth();
    final s = await a.backgroundSession();
    expect(s, isNotNull);
    expect(s!.account, 'a@b.c');
    expect(calls.single.bodyFields['grant_type'], 'refresh_token');
    expect(calls.single.bodyFields['refresh_token'], 'ref1');
    expect(await a.accessToken(), 'acc1');
    expect(calls.length, 1, reason: 'sigue vigente: no vuelve a pedir');
    t = t.add(const Duration(minutes: 59, seconds: 30)); // falta menos de 1 min
    respond = (_) => ok({'access_token': 'acc2', 'expires_in': 3600});
    expect(await a.accessToken(), 'acc2');
    expect(calls.length, 2);
  });

  test('fondo sin refresh token guardado: sin sesión, sin llamar a Google', () async {
    expect(await auth().backgroundSession(), isNull);
    expect(calls, isEmpty);
  });

  test('invalid_grant: borra el token guardado y el fondo termina sin sesión', () async {
    tokens.m[RefreshTokenAuth.kRefreshKey] = 'viejo';
    tokens.m[RefreshTokenAuth.kAccountKey] = 'a@b.c';
    respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
    final a = auth();
    expect(await a.backgroundSession(), isNull);
    expect(tokens.m, isEmpty, reason: 'la app lo vuelve a pedir en primer plano');
    expect(await a.hasToken(), isFalse);
    await expectLater(a.accessToken(), throwsA(isA<RemoteAuthException>()));
  });

  test('otro error de Google no borra el token', () async {
    tokens.m[RefreshTokenAuth.kRefreshKey] = 'ref1';
    tokens.m[RefreshTokenAuth.kAccountKey] = 'a@b.c';
    respond = (_) => http.Response('oops', 500);
    await expectLater(auth().accessToken(), throwsA(isA<RemoteException>()));
    expect(tokens.m[RefreshTokenAuth.kRefreshKey], 'ref1');
  });

  test('desconectar: lo revoca en Google y lo borra', () async {
    tokens.m[RefreshTokenAuth.kRefreshKey] = 'ref1';
    tokens.m[RefreshTokenAuth.kAccountKey] = 'a@b.c';
    await auth().revokeAndClear();
    expect(tokens.m, isEmpty);
    expect(calls.single.url.path, '/revoke');
    expect(calls.single.bodyFields['token'], 'ref1');
  });
}
