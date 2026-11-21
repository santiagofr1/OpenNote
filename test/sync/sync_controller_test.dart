import 'dart:async';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:apuntes/sync/sync_controller.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// El planificador de la sincronización (cuándo corre una pasada), con reloj falso: la pasada real del motor se
/// reemplaza por una que cuenta y tarda [passTime] de reloj falso.
void main() {
  late SyncController c;
  late FakeAsync fa;
  var passes = 0, running = 0, maxRunning = 0;
  var passTime = const Duration(seconds: 1);
  Object? failWith;
  var waiting = <String>{};

  /// Arma el controlador conectado (la conexión corre dentro del reloj falso) y deja pasar la primera pasada.
  void setUp0(void Function() body) {
    passes = running = maxRunning = 0;
    passTime = const Duration(seconds: 1);
    failWith = null;
    waiting = {};
    fakeAsync((a) {
      fa = a;
      c = SyncController(store: Storage(root: Directory.systemTemp), backend: FakeBackend(FakeRemoteStore()))
        ..passOverride = (s) async {
          passes++;
          running++;
          if (running > maxRunning) maxRunning = running;
          await Future<void>.delayed(passTime);
          running--;
          if (failWith != null) throw failWith!;
          return SyncReport()..remoteWaiting.addAll(waiting);
        };
      unawaited(c.connect());
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 2)); // la pasada de la conexión
      expect(passes, 1);
      body();
      c.dispose();
    });
  }

  void tick(int seconds) => fa.elapse(Duration(seconds: seconds));

  test('debounce: tras guardar espera 5 s desde el último guardado y hace UNA pasada', () {
    setUp0(() {
      c.notifySaved();
      expect(c.status, SyncStatus.pending);
      tick(3);
      c.notifySaved(); // sigue escribiendo: el reloj de 5 s arranca de nuevo
      tick(3);
      expect(passes, 1, reason: 'a los 6 s del primer guardado todavía no, el último fue hace 3 s');
      tick(3); // 6 s desde el último
      expect(passes, 2);
      tick(1);
      expect(c.status, SyncStatus.synced);
    });
  });

  test('espera máxima: escribiendo sin parar se sube a los 30 s del primer guardado', () {
    setUp0(() {
      for (var i = 0; i < 40; i++) {
        c.notifySaved();
        tick(1); // un guardado por segundo: el debounce de 5 s nunca vence
        if (i < 28) expect(passes, 1, reason: 'segundo $i');
      }
      expect(passes, greaterThanOrEqualTo(2), reason: 'a los 30 s se sube igual');
      expect(passes, lessThanOrEqualTo(3));
    });
  });

  test('consulta cada 45 s en primer plano y NO en segundo plano', () {
    setUp0(() {
      tick(46);
      expect(passes, 2);
      tick(45);
      expect(passes, 3);
      c.setForeground(false);
      final p = passes;
      tick(600);
      expect(passes, p, reason: 'en segundo plano no hay consultas periódicas');
    });
  });

  test('al volver a primer plano sincroniza enseguida y retoma las consultas', () {
    setUp0(() {
      c.setForeground(false);
      tick(300);
      final p = passes;
      c.setForeground(true);
      fa.flushMicrotasks();
      expect(passes, p + 1, reason: 'resumed dispara una pasada');
      tick(50);
      expect(passes, p + 2, reason: 'y vuelve la consulta periódica');
    });
  });

  test('al pasar a segundo plano con algo guardado sin subir, se sube ya', () {
    setUp0(() {
      c.notifySaved();
      c.setForeground(false);
      fa.flushMicrotasks();
      expect(passes, 2);
    });
  });

  test('nunca dos pasadas a la vez: lo que llega mientras corre se junta en UNA más', () {
    setUp0(() {
      passTime = const Duration(seconds: 10);
      final p = passes;
      unawaited(c.syncNow(manual: true));
      fa.flushMicrotasks();
      tick(2);
      c.syncNow(manual: true);
      c.syncNow(manual: true);
      c.notifySaved();
      tick(5); // el debounce vence con la pasada todavía en curso
      expect(maxRunning, 1);
      expect(passes, p + 1);
      tick(25); // (antes de la próxima consulta periódica)
      expect(maxRunning, 1, reason: 'jamás dos juntas');
      expect(passes, p + 2, reason: 'los pedidos de mientras se juntaron en una sola pasada más');
    });
  });

  test('backoff: 30 s, 1 min, 2 min... hasta 10 min; una pasada buena lo reinicia', () {
    setUp0(() {
      failWith = const RemoteOfflineException();
      var p = passes;
      unawaited(c.syncNow(manual: true));
      fa.flushMicrotasks();
      tick(1);
      expect(c.status, SyncStatus.offline);
      p = passes;
      // reintentos a 30 s, 60 s, 120 s, 240 s, 480 s, 600 s, 600 s
      var waited = 0;
      for (final d in [30, 60, 120, 240, 480, 600, 600]) {
        tick(d - 2); // todavía no
        expect(passes, p, reason: 'antes de $d s no reintenta');
        tick(2 + 1); // pasa el reintento (+ lo que tarda la pasada)
        waited += d;
        expect(passes, p + 1, reason: 'a los $d s reintenta');
        p = passes;
      }
      expect(waited, 30 + 60 + 120 + 240 + 480 + 600 + 600);
      // el poll y los guardados no rompen el retroceso
      c.notifySaved();
      tick(10);
      expect(passes, p, reason: 'en retroceso, ni el debounce ni el poll fuerzan otra pasada');
      // vuelve la red: "volver a primer plano" o "Sincronizar ahora" cortan la espera
      failWith = null;
      c.syncNow(manual: true);
      tick(2);
      expect(passes, p + 1);
      expect(c.failures, 0);
      expect(c.status, SyncStatus.synced);
    });
  });

  test('con error de red, al volver a primer plano reintenta ya (sin esperar el retroceso)', () {
    setUp0(() {
      failWith = const RemoteOfflineException();
      unawaited(c.syncNow(manual: true));
      tick(2);
      expect(c.status, SyncStatus.offline);
      c.setForeground(false);
      failWith = null;
      final p = passes;
      tick(3600);
      expect(passes, p, reason: 'en segundo plano no se reintenta');
      c.setForeground(true);
      tick(2);
      expect(passes, p + 1);
      expect(c.status, SyncStatus.synced);
    });
  });

  test('sesión vencida: queda desconectado y no programa nada', () {
    setUp0(() {
      failWith = const RemoteAuthException();
      unawaited(c.syncNow(manual: true));
      tick(2);
      expect(c.phase, SyncPhase.disconnected);
      expect(c.status, SyncStatus.off);
      final p = passes;
      tick(3600);
      expect(passes, p);
    });
  });

  test('los cambios de la nube que esperan por un cuaderno abierto se exponen y se limpian', () {
    setUp0(() {
      waiting = {'nb1'};
      unawaited(c.syncNow(manual: true));
      tick(2);
      expect(c.remoteWaiting, {'nb1'});
      waiting = {};
      unawaited(c.syncNow(manual: true));
      tick(2);
      expect(c.remoteWaiting, isEmpty);
    });
  });
}
