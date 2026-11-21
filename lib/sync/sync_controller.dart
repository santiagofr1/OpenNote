import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'remote_store.dart';
import 'sync_backend.dart';
import 'sync_engine.dart';
import 'sync_state.dart';

enum SyncPhase { notConfigured, disconnected, connecting, idle, syncing }

/// Lo que muestra el indicadorcito de la barra: sin conectar, al día, sincronizando, hay algo por subir, sin red o con error.
enum SyncStatus { off, synced, syncing, pending, offline, error }

/// Lo que ve la interfaz de la sincronización: conectar y desconectar, CUÁNDO sincronizar y el estado. Nunca lanza
/// errores hacia afuera: los deja en [error].
///
/// CUÁNDO SINCRONIZA (si está conectado):
///  - al abrir la app ([init]) y al volver a primer plano ([setForeground] true);
///  - poco después de guardar: [notifySaved] (lo llama la `Storage` al terminar un guardado) espera [debounce] desde el
///    último guardado, pero nunca más de [maxWait] desde el primero si se sigue escribiendo sin parar;
///  - cada [pollInterval] con la app en primer plano (una sola consulta barata a la API de cambios; si no hay nada nuevo
///    no se baja nada). En segundo plano NO hay consultas periódicas;
///  - al cerrar un cuaderno y con "Sincronizar ahora" (la biblioteca llama a [syncNow]).
/// NUNCA corren dos pasadas a la vez: un pedido que llega mientras corre una marca [_again] y se hace UNA pasada más al
/// terminar. Si una pasada falla (sin red, error del servidor) se espera con retroceso (backoff) 30 s, 1 min, 2 min…
/// hasta 10 min antes de reintentar; volver a primer plano o "Sincronizar ahora" lo reinician.
/// Los cuadernos abiertos en el editor ([busyNotebooks]) los maneja el motor: solo sube, no escribe encima.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.store,
    required this.backend,
    this.pollInterval = const Duration(seconds: 45),
    this.debounce = const Duration(seconds: 5),
    this.maxWait = const Duration(seconds: 30),
    this.backoffBase = const Duration(seconds: 30),
    this.backoffMax = const Duration(minutes: 10),
  });
  final Storage store;
  final SyncBackend backend;
  final Duration pollInterval, debounce, maxWait, backoffBase, backoffMax;

  SyncPhase phase = SyncPhase.disconnected;
  String? account;
  DateTime? lastSync;
  String? error;
  SyncReport? lastReport;
  int conflictCount = 0;

  /// Sin red / el servidor no responde (hay un reintento programado).
  bool offline = false;

  /// Cuadernos abiertos que tienen cambios de la nube sin aplicar (ver [SyncReport.remoteWaiting]).
  Set<String> remoteWaiting = const {};

  /// Ids de los cuadernos abiertos en el editor (el motor solo sube lo suyo, no les escribe).
  Set<String> Function() busyNotebooks = () => const {};

  /// Se llama al terminar una pasada que cambió algo en el disco de acá (por ejemplo para releer el índice).
  void Function(SyncReport report)? onSynced;

  /// Solo para los tests con reloj falso: reemplaza la pasada real del motor.
  @visibleForTesting
  Future<SyncReport> Function(SyncSession s)? passOverride;

  SyncSession? _session;
  Timer? _debounceT, _maxWaitT, _pollT, _retryT;
  Future<void>? _running;
  bool _again = false, _pending = false, _foreground = true, _disposed = false;
  int _fails = 0;

  bool get connected => _session != null;
  bool get syncing => phase == SyncPhase.syncing;
  bool get foreground => _foreground;

  /// Hay algo guardado que todavía no se subió (esperando el debounce o una pasada).
  bool get pending => _pending;

  /// Cuántos fallos seguidos lleva (0 = bien).
  int get failures => _fails;

  SyncStatus get status {
    if (!connected) return SyncStatus.off;
    if (syncing) return SyncStatus.syncing;
    if (offline) return SyncStatus.offline;
    if (error != null) return SyncStatus.error;
    if (_pending) return SyncStatus.pending;
    return SyncStatus.synced;
  }

  /// Se completa cuando no hay una pasada en curso.
  Future<void> whenIdle() async {
    while (_running != null) {
      await _running;
    }
  }

  void _set(SyncPhase p) {
    phase = p;
    _changed();
  }

  void _changed() {
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
    _fails = 0;
    offline = false;
    _startPolling();
    _set(SyncPhase.idle);
  }

  void _startPolling() {
    _pollT?.cancel();
    _pollT = null;
    if (_session == null || !_foreground) return;
    _pollT = Timer.periodic(pollInterval, (_) {
      if (_retryT == null) _request(); // en retroceso se espera al reintento programado
    });
  }

  void _cancelTimers() {
    _debounceT?.cancel();
    _maxWaitT?.cancel();
    _pollT?.cancel();
    _retryT?.cancel();
    _debounceT = _maxWaitT = _pollT = _retryT = null;
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
    _cancelTimers();
    _session = null;
    account = null;
    lastReport = null;
    error = null;
    offline = false;
    _pending = false;
    _fails = 0;
    remoteWaiting = const {};
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

  /// La app pasó a primer plano ([fg] true: sincroniza ya y retoma las consultas periódicas) o a segundo plano (corta las
  /// consultas periódicas; si hay algo guardado sin subir, se sube ahora porque Android puede cerrar la app).
  void setForeground(bool fg) {
    if (_foreground == fg) return;
    _foreground = fg;
    if (_session == null) return;
    if (fg) {
      _startPolling();
      _resetBackoff();
      _request();
    } else {
      _pollT?.cancel();
      _pollT = null;
      if (_debounceT != null && _retryT == null) _fireAuto();
    }
  }

  /// Algo se guardó en disco (lo llama la `Storage`): programa una pasada [debounce] después del último guardado, y a
  /// lo sumo [maxWait] después del primero.
  void notifySaved() {
    if (_session == null || _disposed) return;
    final was = _pending;
    _pending = true;
    _debounceT?.cancel();
    _debounceT = Timer(debounce, _fireAuto);
    _maxWaitT ??= Timer(maxWait, _fireAuto);
    if (!was) _changed();
  }

  void _fireAuto() {
    _debounceT?.cancel();
    _maxWaitT?.cancel();
    _debounceT = _maxWaitT = null;
    if (_retryT != null) return; // en retroceso: lo levanta el reintento
    _request();
  }

  void _resetBackoff() {
    _retryT?.cancel();
    _retryT = null;
    _fails = 0;
  }

  /// Pide una pasada. [manual]: lo pidió el usuario (corta el retroceso). Devuelve cuando no queda nada en curso.
  /// Los pedidos que llegan mientras corre una pasada se juntan en UNA más.
  Future<void> syncNow({bool manual = false}) {
    if (_session == null) return Future.value();
    if (manual) {
      _resetBackoff();
    } else if (_retryT != null) {
      return _running ?? Future.value();
    }
    _request();
    return _running ?? Future.value();
  }

  void _request() {
    final s = _session;
    if (s == null || _disposed) return;
    if (_running != null) {
      _again = true;
      return;
    }
    _running = _loop(s).whenComplete(() => _running = null);
  }

  Future<void> _loop(SyncSession s) async {
    var ok = true;
    do {
      _again = false;
      ok = await _run(s);
    } while (_again && ok && _session != null && !_disposed);
  }

  Duration _delay() {
    var d = backoffBase * (1 << (_fails - 1).clamp(0, 20));
    if (d > backoffMax) d = backoffMax;
    return d;
  }

  void _failed(bool isOffline) {
    _fails++;
    offline = isOffline;
    _retryT?.cancel();
    _retryT = Timer(_delay(), () {
      _retryT = null;
      if (_foreground) _request(); // en segundo plano no se reintenta: se retoma al volver
    });
  }

  /// Una pasada. Devuelve false si falló del todo (se programa el reintento).
  Future<bool> _run(SyncSession s) async {
    // lo guardado hasta ahora entra en esta pasada (lo que se guarde durante ella vuelve a armar el debounce)
    _debounceT?.cancel();
    _maxWaitT?.cancel();
    _debounceT = _maxWaitT = null;
    _pending = false;
    error = null;
    _set(SyncPhase.syncing);
    try {
      final rep = await (passOverride?.call(s) ?? _enginePass(s));
      lastReport = rep;
      lastSync = DateTime.now();
      offline = false;
      _fails = 0;
      remoteWaiting = Set.of(rep.remoteWaiting);
      if (rep.errors.isNotEmpty) error = '${rep.errors.length} archivo(s) no se pudieron sincronizar; se reintenta en la próxima pasada';
      if (rep.localChanged) onSynced?.call(rep);
      _set(SyncPhase.idle);
      return true;
    } on RemoteAuthException catch (e) {
      error = e.message;
      _cancelTimers();
      _session = null;
      _pending = false;
      _set(SyncPhase.disconnected);
      return false;
    } catch (e) {
      error = e is RemoteOfflineException ? null : _msg(e);
      _failed(e is RemoteOfflineException);
      _set(SyncPhase.idle);
      return false;
    }
  }

  Future<SyncReport> _enginePass(SyncSession s) async {
    final rep = await SyncEngine(store, s.store, busy: busyNotebooks, account: s.account).sync();
    conflictCount = (await SyncState.load(store)).conflictCount;
    return rep;
  }

  String _msg(Object e) => e is RemoteException ? e.message : 'No se pudo sincronizar: $e';

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
