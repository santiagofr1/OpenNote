import 'remote_store.dart';

/// Una sesión abierta con un servicio de nube: la cuenta y el almacén remoto ya autenticado.
class SyncSession {
  final String account;
  final RemoteStore store;
  const SyncSession(this.account, this.store);
}

/// Cómo se conecta la app con la nube (login, sesión guardada, cierre). La implementación real es
/// [GoogleBackend] (google_auth.dart); los tests y la pantalla de prueba usan una falsa.
abstract class SyncBackend {
  /// Si están los datos del proyecto de Google (ver google_config.dart). Si no, no se puede conectar.
  bool get configured;

  /// Qué le falta, para mostrarle al usuario.
  String get missingConfig;

  /// Retoma la sesión guardada sin pedir nada (null si no hay o hay que volver a conectar).
  Future<SyncSession?> restore();

  /// Login interactivo (abre el selector de cuentas o el navegador).
  Future<SyncSession> signIn();

  /// Cierra la sesión y borra lo guardado (los cuadernos de acá no se tocan).
  Future<void> signOut();
}
