import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'remote_store.dart';
import 'sync_backend.dart';
import 'sync_engine.dart';
import 'sync_state.dart';

enum SyncPhase { notConfigured, disconnected, connecting, idle, syncing }

/// Lo que ve la interfaz de la sincronización: conectar y desconectar, cuándo sincronizar y el estado. Nunca lanza
/// errores hacia afuera: los deja en [error].
///
/// CUÁNDO SINCRONIZA (si está conectado): al abrir la app ([init]), al cerrar un cuaderno (la biblioteca llama a
/// [syncNow]), cada [interval] con la app abierta, y con "Sincronizar ahora". Un solo [syncNow] a la vez. Si hay un cuaderno
/// abierto ([canRun] false) las pasadas automáticas esperan; igual el motor saltea los cuadernos de [busyNotebooks].
class SyncController extends ChangeNotifier {
  SyncController({required this.store, required this.backend, this.interval = const Duration(minutes: 10)});
  final Storage store;
  final SyncBackend backend;
  final Duration interval;

  SyncPhase phase = SyncPhase.disconnected;
  String? account;
  DateTime? lastSync;
  String? error;
  SyncReport? lastReport;
  int conflictCount = 0;

  /// Ids de los cuadernos abiertos en el editor (el motor no los toca).
  Set<String> Function() busyNotebooks = () => const {};

  /// Si es false, las pasadas automáticas no corren (hay un cuaderno abierto).
  bool Function() canRun = () => true;

  /// Se llama al terminar una pasada que cambió algo en el disco de acá (por ejemplo para releer el índice).
  void Function(SyncReport report)? onSynced;

  SyncSession? _session;
  Timer? _timer;
  Future<void>? _running;
  bool _disposed = false;

  bool get connected => _session != null;
  bool get syncing => phase == SyncPhase.syncing;

  /// Se completa cuando no hay una pasada en curso.
  Future<void> whenIdle() async {
    while (_running != null) {
      await _running;
    }
  }

  void _set(SyncPhase p) {
    phase = p;
    if (!_disposed) notifyListeners();
  }

  /// Al abrir la app: lee el estado guardado y retoma la sesión sin preguntar nada.
  Future<void> init() async {
    final st = await SyncState.load(store);
    lastSync = st.lastSync > 0 ? DateTime.fromMillisecondsSinceEpoch(st.lastSync) : null;
    conflictCount = st.conflictCount;
    if (!backend.configured) {
      _set(SyncPhase.notConfigured);
      return;
    }
    try {
      final s = await backend.restore();
      if (s == null) {
        _set(SyncPhase.disconnected);
        return;
      }
      _attach(s);
      unawaited(syncNow());
    } catch (e) {
      error = _msg(e);
      _set(SyncPhase.disconnected);
    }
  }

  void _attach(SyncSession s) {
    _session = s;
    account = s.account;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => syncNow());
    _set(SyncPhase.idle);
  }

  Future<void> connect() async {
    if (!backend.configured || phase == SyncPhase.connecting || syncing) return;
    error = null;
    _set(SyncPhase.connecting);
    try {
      _attach(await backend.signIn());
      unawaited(syncNow(manual: true));
    } catch (e) {
      error = _msg(e);
      _set(SyncPhase.disconnected);
    }
  }

  Future<void> disconnect() async {
    await whenIdle();
    _timer?.cancel();
    _session = null;
    account = null;
    lastReport = null;
    error = null;
    try {
      await backend.signOut();
      await SyncState.clear(store); // la próxima conexión empieza de cero; los cuadernos de acá no se tocan
    } catch (e) {
      error = _msg(e);
    }
    lastSync = null;
    conflictCount = 0;
    _set(SyncPhase.disconnected);
  }

  /// Una pasada. [manual]: lo pidió el usuario (corre aunque haya un cuaderno abierto; los abiertos se saltean).
  Future<void> syncNow({bool manual = false}) {
    if (_running != null) return _running!;
    final s = _session;
    if (s == null || (!manual && !canRun())) return Future.value();
    final run = _run(s);
    _running = run.whenComplete(() => _running = null);
    return _running!;
  }

  Future<void> _run(SyncSession s) async {
    error = null;
    _set(SyncPhase.syncing);
    try {
      final rep = await SyncEngine(store, s.store, busy: busyNotebooks, account: s.account).sync();
      lastReport = rep;
      lastSync = DateTime.now();
      conflictCount = (await SyncState.load(store)).conflictCount;
      if (rep.errors.isNotEmpty) error = '${rep.errors.length} archivo(s) no se pudieron sincronizar; se reintenta en la próxima pasada';
      if (rep.localChanged) onSynced?.call(rep);
      _set(SyncPhase.idle);
    } on RemoteAuthException catch (e) {
      error = e.message;
      _session = null;
      _timer?.cancel();
      _set(SyncPhase.disconnected);
    } catch (e) {
      error = _msg(e);
      _set(SyncPhase.idle);
    }
  }

  String _msg(Object e) => e is RemoteException ? e.message : 'No se pudo sincronizar: $e';

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
