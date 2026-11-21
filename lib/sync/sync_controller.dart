import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'encrypted_remote_store.dart';
import 'remote_store.dart';
import 'sync_backend.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'sync_lock.dart';
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
///
/// SEGUNDO PLANO (Android): una tarea de WorkManager sincroniza cada 15 min con la app cerrada (background_sync.dart).
/// Para no pisarse con ella, si hay [lock] cada pasada lo toma antes de empezar (si lo tiene la de fondo, espera
/// [lockRetry] y reintenta) y, con [marks], avisa que la app está en primer plano (la tarea de fondo no hace nada) y
/// deja anotados los cuadernos abiertos al pasar a segundo plano. Si la tarea de fondo bajó cambios, al volver se llama
/// a [onBackgroundChanged] para releer el disco. Ambos ([lock] y [marks]) son opcionales (los tests y Linux no los usan).
class SyncController extends ChangeNotifier {
  SyncController({
    required this.store,
    required this.backend,
    this.pollInterval = const Duration(seconds: 45),
    this.debounce = const Duration(seconds: 5),
    this.maxWait = const Duration(seconds: 30),
    this.backoffBase = const Duration(seconds: 30),
    this.backoffMax = const Duration(minutes: 10),
    this.lockRetry = const Duration(seconds: 15),
    this.crypto,
  });
  final Storage store;
  final SyncBackend backend;
  final Duration pollInterval, debounce, maxWait, backoffBase, backoffMax, lockRetry;

  /// Candado y marcas con la tarea de fondo (se arman cuando ya se conoce la carpeta de datos).
  SyncLock? lock;
  SyncMarks? marks;

  /// Si esta plataforma tiene sincronización en segundo plano (la pantalla muestra el interruptor solo si es true).
  bool backgroundSupported = false;

  /// Interruptor "Sincronizar en segundo plano" (por defecto encendido). Se carga de las preferencias.
  bool backgroundEnabled = true;

  /// Registra o cancela la tarea de fondo: se llama con `conectado && backgroundEnabled` cada vez que cambia alguna de
  /// las dos cosas.
  Future<void> Function(bool wanted)? applyBackground;

  /// Cambió el interruptor (para guardarlo en las preferencias).
  void Function(bool enabled)? onBackgroundToggled;

  /// La tarea de fondo bajó cambios desde la última vez: hay que volver a leer lo del disco.
  void Function()? onBackgroundChanged;

  /// Cifrado de extremo a extremo opcional (null: sin esa función). Ver sync_crypto.dart.
  final SyncCrypto? crypto;

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
  Timer? _debounceT, _maxWaitT, _pollT, _retryT, _lockT;
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
    unawaited(marks?.clearBusy()); // recién abierta: no hay cuadernos abiertos (puede quedar una marca vieja)
    unawaited(marks?.beatForeground());
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
    _applyBackground();
  }

  void _applyBackground() {
    final f = applyBackground;
    if (f != null) unawaited(f(connected && backgroundEnabled).catchError((_) {}));
  }

  /// El usuario prendió o apagó el interruptor del segundo plano.
  void setBackgroundEnabled(bool v) {
    if (backgroundEnabled == v) return;
    backgroundEnabled = v;
    onBackgroundToggled?.call(v);
    _applyBackground();
    _changed();
  }

  void _startPolling() {
    _pollT?.cancel();
    _pollT = null;
    if (_session == null || !_foreground) return;
    _pollT = Timer.periodic(pollInterval, (_) {
      unawaited(marks?.beatForeground());
      if (_retryT == null) _request(); // en retroceso se espera al reintento programado
    });
  }

  void _cancelTimers() {
    _debounceT?.cancel();
    _maxWaitT?.cancel();
    _pollT?.cancel();
    _retryT?.cancel();
    _lockT?.cancel();
    _debounceT = _maxWaitT = _pollT = _retryT = _lockT = null;
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
      await crypto?.forget(); // la clave del cifrado no queda guardada en este dispositivo
      await backend.signOut();
      await SyncState.clear(store); // la próxima conexión empieza de cero; los cuadernos de acá no se tocan
    } catch (e) {
      error = _msg(e);
    }
    lastSync = null;
    conflictCount = 0;
    _applyBackground();
    _set(SyncPhase.disconnected);
  }

  /// La app pasó a primer plano ([fg] true: sincroniza ya y retoma las consultas periódicas) o a segundo plano (corta las
  /// consultas periódicas; si hay algo guardado sin subir, se sube ahora porque Android puede cerrar la app).
  void setForeground(bool fg) {
    if (_foreground == fg) return;
    _foreground = fg;
    if (fg) {
      unawaited(marks?.clearBusy());
      unawaited(marks?.beatForeground());
    } else {
      unawaited(marks?.clearForeground());
      unawaited(marks?.writeBusy(busyNotebooks()));
    }
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

  /// Una pasada con el candado tomado. Si lo tiene la tarea de fondo se reintenta en [lockRetry] (no cuenta como fallo).
  Future<bool> _run(SyncSession s) async {
    final l = lock;
    if (l == null) return _runLocked(s);
    if (!await l.tryAcquire()) {
      _lockT?.cancel();
      _lockT = Timer(lockRetry, () {
        _lockT = null;
        if (_foreground) _request();
      });
      return true;
    }
    try {
      // la tarea de fondo bajó cambios mientras la app no miraba: se relee el disco
      if (await marks?.takeBackgroundChanged() ?? false) onBackgroundChanged?.call();
      return await _runLocked(s);
    } finally {
      await l.release();
    }
  }

  /// Una pasada. Devuelve false si falló del todo (se programa el reintento).
  Future<bool> _runLocked(SyncSession s) async {
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
    } on CryptoLockedException catch (e) {
      error = e.message; // falta la frase: no se reintenta solo, se pide en la pantalla de sincronización
      _set(SyncPhase.idle);
      return false;
    } on RemoteAuthException catch (e) {
      error = e.message;
      _cancelTimers();
      _session = null;
      _pending = false;
      _applyBackground();
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
    for (var tries = 0;; tries++) {
      try {
        final remote = await (crypto?.wrap(s.store) ?? Future.value(s.store));
        final rep = await SyncEngine(store, remote, busy: busyNotebooks, account: s.account).sync();
        conflictCount = (await SyncState.load(store)).conflictCount;
        return rep;
      } on VaultChangedException {
        if (tries >= 2) rethrow;
        crypto?.invalidate(); // otro dispositivo cambió el cifrado: se vuelve a leer crypto.json y se repite
      }
    }
  }

  // ---------- cifrado (activar / desactivar / frase): corren solos, sin pasada en curso ----------

  /// Activa el cifrado de la nube con [passphrase]. Devuelve el error para mostrar (null: salió bien).
  Future<String?> enableEncryption(String passphrase) =>
      _cryptoOp((c, s) => c.enable(s.store, passphrase, (r) => _plainPass(s, r)));

  /// Desactiva el cifrado (deja la nube en claro otra vez).
  Future<String?> disableEncryption() => _cryptoOp((c, s) => c.disable(s.store, (r) => _plainPass(s, r)));

  /// Da la frase de una nube que ya estaba cifrada (otro dispositivo la activó).
  Future<String?> unlockEncryption(String passphrase) => _cryptoOp((c, s) => c.unlock(s.store, passphrase));

  Future<void> _plainPass(SyncSession s, RemoteStore r) => SyncEngine(store, r, busy: busyNotebooks, account: s.account).sync();

  Future<String?> _cryptoOp(Future<void> Function(SyncCrypto c, SyncSession s) op) async {
    final c = crypto;
    if (c == null) return null;
    await whenIdle();
    final s = _session;
    if (s == null) return 'Conectá con Google primero';
    final done = Completer<void>();
    _running = done.future; // los pedidos de pasada que lleguen mientras tanto esperan (_again)
    error = null;
    _set(SyncPhase.syncing);
    String? problem;
    try {
      await op(c, s);
    } catch (e) {
      problem = _msg(e);
      if (e is RemoteAuthException) {
        error = e.message;
      }
    } finally {
      c.clearProgress();
      _running = null;
      done.complete();
    }
    _again = false;
    _set(SyncPhase.idle);
    if (_session != null) unawaited(syncNow(manual: true));
    return problem;
  }

  String _msg(Object e) => e is RemoteException ? e.message : 'No se pudo sincronizar: $e';

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
