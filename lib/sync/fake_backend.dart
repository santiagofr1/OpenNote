import 'remote_store.dart';
import 'sync_backend.dart';

/// [SyncBackend] sin Google: la "cuenta" es de mentira y el remoto es el que se le pasa (por ejemplo un
/// [FakeRemoteStore] en memoria). Lo usan los tests y los casos de integración.
class FakeBackend implements SyncBackend {
  FakeBackend(this.remote, {this.configured = true, this.account = 'prueba@opennote.test'});
  final RemoteStore remote;
  final String account;
  @override
  final bool configured;
  bool _signedIn = false;
  int signIns = 0;

  @override
  String get missingConfig => 'GOOGLE_WEB_CLIENT_ID';

  @override
  Future<SyncSession?> restore() async => _signedIn ? SyncSession(account, remote) : null;

  @override
  Future<SyncSession?> restoreInBackground() => restore();

  @override
  Future<SyncSession> signIn() async {
    signIns++;
    _signedIn = true;
    return SyncSession(account, remote);
  }

  @override
  Future<void> signOut() async => _signedIn = false;
}
