import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/storage.dart';
import 'encrypted_remote_store.dart';
import 'google_auth.dart';
import 'remote_store.dart';
import 'sync_backend.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'sync_lock.dart';

/// Sincronización en segundo plano (solo Android): una tarea periódica de WorkManager (cada 15 min, el mínimo de
/// Android, y con red) que corre aunque la app esté cerrada. La lógica está en [runBackgroundPass], que no sabe nada
/// de WorkManager y se prueba sola.

/// Clave en `prefs.json` del interruptor "Sincronizar en segundo plano" (por defecto encendido).
const kBgSyncPref = 'bgSync';

bool bgSyncEnabled(Map? prefs) => prefs?[kBgSyncPref] != false;

const _kTaskName = 'opennote.sync.background';
const _kTaskTag = 'opennote-sync';

enum BackgroundOutcome { synced, disabled, notConfigured, appInForeground, locked, noSession, cryptoLocked, failed }

class BackgroundResult {
  const BackgroundResult(this.outcome, {this.report, this.error});
  final BackgroundOutcome outcome;
  final SyncReport? report;
  final Object? error;
}

/// Una pasada de fondo, sin errores hacia afuera: respeta el interruptor, no corre si la app está en primer plano ni si
/// otro tiene el candado ([SyncLock]), retoma la sesión en silencio (si hace falta interacción termina sin hacer nada) y
/// sincroniza. Si bajó cambios deja la marca para que la app relea el disco al volver a primer plano.
Future<BackgroundResult> runBackgroundPass(
  Storage store,
  SyncBackend backend, {
  DateTime Function()? now,
  Duration lockTtl = const Duration(minutes: 10),
  SyncCrypto? crypto,
}) async {
  if (!bgSyncEnabled(await store.loadPrefs())) return const BackgroundResult(BackgroundOutcome.disabled);
  if (!backend.configured) return const BackgroundResult(BackgroundOutcome.notConfigured);
  final marks = SyncMarks(store.dir, now: now);
  if (await marks.foregroundFresh()) return const BackgroundResult(BackgroundOutcome.appInForeground);
  final lock = SyncLock(store.dir, owner: 'fondo', ttl: lockTtl, now: now);
  if (!await lock.tryAcquire()) return const BackgroundResult(BackgroundOutcome.locked);
  try {
    final SyncSession? s;
    try {
      s = await backend.restoreInBackground();
    } catch (e) {
      // por ejemplo google_sign_in sin Activity: sin sesión usable en segundo plano, no es un error de la tarea
      return BackgroundResult(BackgroundOutcome.noSession, error: e);
    }
    if (s == null) return const BackgroundResult(BackgroundOutcome.noSession);
    // los cuadernos que quedaron abiertos en el editor cuando la app pasó a segundo plano: solo se les sube
    final busy = await marks.readBusy();
    // misma capa de cifrado que la app: con la nube cifrada y sin la clave guardada no se toca nada
    final RemoteStore remote;
    try {
      remote = await (crypto ?? SyncCrypto(store: store)).wrap(s.store);
    } on CryptoLockedException catch (e) {
      return BackgroundResult(BackgroundOutcome.cryptoLocked, error: e);
    }
    final rep = await SyncEngine(store, remote, busy: () => busy, account: s.account).sync();
    if (rep.localChanged) await marks.markBackgroundChanged();
    return BackgroundResult(BackgroundOutcome.synced, report: rep);
  } catch (e) {
    return BackgroundResult(BackgroundOutcome.failed, error: e);
  } finally {
    await lock.release();
  }
}

/// Punto de entrada de WorkManager: corre en otro isolate, sin UI.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final store = Storage();
      await store.init();
      final r = await runBackgroundPass(store, GoogleBackend());
      debugPrint('Vynote sync de fondo: ${r.outcome.name}${r.error != null ? ' (${r.error})' : ''}${r.report != null ? ' ${r.report}' : ''}');
      // "failed" devuelve false para que WorkManager reintente con su retroceso; lo demás es un final normal
      return r.outcome != BackgroundOutcome.failed;
    } catch (_) {
      return false;
    }
  });
}

/// Registra y cancela la tarea periódica. En otras plataformas no hace nada.
class BackgroundSync {
  const BackgroundSync._();
  static bool get supported => !kIsWeb && Platform.isAndroid;
  static bool _inited = false;

  static Future<void> _init() async {
    if (_inited) return;
    await Workmanager().initialize(backgroundSyncDispatcher);
    _inited = true;
  }

  /// Se asegura de que la tarea esté registrada (se llama al conectar y al abrir la app con sesión). `update`: si ya
  /// existe se actualiza sin reiniciar el reloj de la próxima ejecución.
  static Future<void> ensureRegistered() async {
    if (!supported) return;
    try {
      await _init();
      await Workmanager().registerPeriodicTask(
        _kTaskName,
        _kTaskName,
        tag: _kTaskTag,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('BackgroundSync.ensureRegistered: $e');
    }
  }

  static Future<void> cancel() async {
    if (!supported) return;
    try {
      await _init();
      await Workmanager().cancelByUniqueName(_kTaskName);
    } catch (e) {
      debugPrint('BackgroundSync.cancel: $e');
    }
  }
}
