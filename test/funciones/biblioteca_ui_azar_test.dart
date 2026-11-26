import 'dart:io';
import 'dart:math';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La biblioteca con la UI de verdad: una caminata al azar de acciones del usuario (entrar y salir de carpetas, crear,
/// renombrar, mover cuadernos y carpetas, borrar sacando o con todo, buscar) contra un modelo de mapas. Después de CADA
/// acción lo que se ve en pantalla es exactamente el contenido de la carpeta actual según el modelo (o los resultados de
/// la búsqueda), y al final el índice que quedó en disco es el del modelo (lo que se ve = lo que se guardó).
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_lib_azar');
  });
  tearDown(() async {
    Storage.useIsolates = true;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Finder k(String key) => find.byKey(Key(key));
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.tap(f);
    await settle(t);
  }

  Future<void> hold(WidgetTester t, Finder f) async {
    await t.longPress(f);
    await settle(t);
  }

  /// Nombres (después del prefijo) de las claves visibles que empiezan con [prefijo].
  Set<String> visibles(String prefijo) => {
        for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefijo)).evaluate())
          (e.widget.key! as ValueKey<String>).value.substring(prefijo.length)
      };

  for (final seed in [1, 2, 3]) {
    testWidgets('caminata al azar por la biblioteca (semilla $seed)', (t) async {
      final r = Random(seed);
      t.view.physicalSize = const Size(1600, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      // modelo: carpeta -> padre y cuaderno -> carpeta (null = inicio), todo por NOMBRE (los nombres son únicos)
      final padre = <String, String?>{};
      final carpetaDe = <String, String?>{for (var i = 0; i < 5; i++) 'N$i': null};
      var contador = 0;
      String? actual;

      await t.runAsync(() async {
        final s = Storage(root: root);
        await s.init();
        await s.saveIndex(NotesIndex(notebooks: [for (var i = 0; i < 5; i++) Notebook('n$i', 'N$i')]));
      });
      await t.pumpWidget(ApuntesApp(root: root));
      for (var i = 0; i < 100 && find.byKey(const Key('nb-N0')).evaluate().isEmpty; i++) {
        await settle(t, 100);
      }
      await settle(t, 600);

      Set<String> hijasDe(String? c) => {for (final e in padre.entries) if (e.value == c) e.key};
      Set<String> cuadernosDe(String? c) => {for (final e in carpetaDe.entries) if (e.value == c) e.key};
      Set<String> subarbol(String f) {
        final out = <String>{};
        final pend = [f];
        while (pend.isNotEmpty) {
          final p = pend.removeLast();
          for (final h in hijasDe(p)) {
            if (out.add(h)) pend.add(h);
          }
        }
        return out;
      }

      void pantalla(String donde) {
        expect(visibles('folder-'), hijasDe(actual), reason: '$donde: carpetas que se ven en "${actual ?? 'Inicio'}"');
        expect(visibles('nb-'), cuadernosDe(actual), reason: '$donde: cuadernos que se ven en "${actual ?? 'Inicio'}"');
      }

      pantalla('inicio');
      final acciones = <String>[];
      for (var paso = 0; paso < 60; paso++) {
        final hijas = hijasDe(actual).toList()..sort();
        final cuadernos = cuadernosDe(actual).toList()..sort();
        final total = padre.length + carpetaDe.length;
        var a = r.nextInt(9);
        // que todo entre en pantalla
        if (padre.length >= 8 && (a == 0)) a = 1;
        String log(String s) {
          acciones.add('$paso:$s');
          return 'semilla $seed, acciones: ${acciones.join(' | ')}';
        }

        switch (a) {
          case 0: // carpeta nueva
            final n = 'C${contador++}';
            await tap(t, k('new'));
            await tap(t, k('newFolder'));
            await t.enterText(k('askText'), n);
            await tap(t, k('askOk'));
            padre[n] = actual;
            pantalla(log('crear carpeta $n en ${actual ?? 'Inicio'}'));
          case 1: // entrar a una carpeta
            if (hijas.isEmpty) break;
            final n = hijas[r.nextInt(hijas.length)];
            await tap(t, k('folder-$n'));
            actual = n;
            pantalla(log('entrar a $n'));
          case 2: // subir
            if (actual == null) break;
            await tap(t, k('up'));
            actual = padre[actual];
            pantalla(log('subir'));
          case 3: // renombrar carpeta
            if (hijas.isEmpty) break;
            final n = hijas[r.nextInt(hijas.length)], nuevo = 'C${contador++}';
            await hold(t, k('folder-$n'));
            await tap(t, find.text('Renombrar'));
            await t.enterText(k('askText'), nuevo);
            await tap(t, k('askOk'));
            padre[nuevo] = padre.remove(n);
            for (final e in padre.entries.toList()) {
              if (e.value == n) padre[e.key] = nuevo;
            }
            for (final e in carpetaDe.entries.toList()) {
              if (e.value == n) carpetaDe[e.key] = nuevo;
            }
            pantalla(log('renombrar $n a $nuevo'));
          case 4: // mover un cuaderno
            if (cuadernos.isEmpty) break;
            final n = cuadernos[r.nextInt(cuadernos.length)];
            await hold(t, k('nb-$n'));
            await tap(t, k('moveTo'));
            final destinos = <String?>[null, ...padre.keys].where((d) => d != actual).toList();
            final d = destinos[r.nextInt(destinos.length)];
            final clave = k('moveTarget-${d ?? 'Inicio'}');
            expect(clave, findsOneWidget, reason: log('mover $n: el destino ${d ?? 'Inicio'} se ofrece'));
            await tap(t, clave);
            carpetaDe[n] = d;
            pantalla(log('mover cuaderno $n a ${d ?? 'Inicio'}'));
          case 5: // mover una carpeta
            if (hijas.isEmpty) break;
            final n = hijas[r.nextInt(hijas.length)];
            await hold(t, k('folder-$n'));
            await tap(t, k('moveTo'));
            final prohibidas = {n, ...subarbol(n)};
            for (final p in prohibidas) {
              if (p != n) expect(k('moveTarget-$p'), findsNothing, reason: log('mover $n: no puede ir adentro de su hija $p'));
            }
            final destinos = <String?>[null, ...padre.keys.where((x) => !prohibidas.contains(x))].where((d) => d != actual).toList();
            final d = destinos[r.nextInt(destinos.length)];
            final clave = k('moveTarget-${d ?? 'Inicio'}');
            expect(clave, findsOneWidget, reason: log('mover $n: el destino ${d ?? 'Inicio'} se ofrece'));
            await tap(t, clave);
            padre[n] = d;
            pantalla(log('mover carpeta $n a ${d ?? 'Inicio'}'));
          case 6: // borrar carpeta
            if (hijas.isEmpty || total < 3) break;
            final n = hijas[r.nextInt(hijas.length)];
            final todo = r.nextBool();
            await hold(t, k('folder-$n'));
            await tap(t, find.text('Borrar'));
            if (todo) {
              await tap(t, k('folderDeleteAll'));
              await tap(t, k('confirmDelete'));
              final fuera = {n, ...subarbol(n)};
              padre.removeWhere((c, _) => fuera.contains(c));
              carpetaDe.removeWhere((_, c) => fuera.contains(c));
            } else {
              await tap(t, k('folderKeep'));
              final arriba = padre.remove(n);
              for (final e in padre.entries.toList()) {
                if (e.value == n) padre[e.key] = arriba;
              }
              for (final e in carpetaDe.entries.toList()) {
                if (e.value == n) carpetaDe[e.key] = arriba;
              }
            }
            pantalla(log('borrar $n ${todo ? 'con todo' : 'sacando el contenido'}'));
          case 7: // buscar y limpiar
            final q = ['c', 'n', 'C1', 'n2', 'zz'][r.nextInt(5)];
            await t.enterText(k('librarySearch'), q);
            await settle(t, 300);
            final qq = q.toLowerCase();
            expect(visibles('folder-'), {for (final c in padre.keys) if (c.toLowerCase().contains(qq)) c}, reason: log('buscar "$q": carpetas'));
            expect(visibles('nb-'), {for (final c in carpetaDe.keys) if (c.toLowerCase().contains(qq)) c}, reason: log('buscar "$q": cuadernos'));
            await tap(t, k('librarySearchClear'));
            pantalla(log('limpiar la búsqueda "$q"'));
          default: // volver al inicio con las migas
            if (actual == null) break;
            await tap(t, k('crumb-inicio'));
            actual = null;
            pantalla(log('ir al Inicio'));
        }
      }

      // lo guardado en disco es el modelo (con reintentos: las escrituras van en segundo plano)
      Map<String, String?>? carpetasDisco, cuadernosDisco;
      for (var i = 0; i < 20; i++) {
        await settle(t, 300);
        final idx = (await t.runAsync(() async {
          final s = Storage(root: root);
          await s.init();
          return s.loadIndex();
        }))!;
        final porId = {for (final f in idx.folders) f.id: f.name};
        carpetasDisco = {for (final f in idx.folders) f.name: porId[f.parent]};
        cuadernosDisco = {for (final n in idx.notebooks) n.name: porId[n.folder]};
        if (mapEquals(carpetasDisco, padre) && mapEquals(cuadernosDisco, carpetaDe)) break;
      }
      expect(carpetasDisco, padre, reason: 'carpetas en disco (acciones: ${acciones.join(' | ')})');
      expect(cuadernosDisco, carpetaDe, reason: 'cuadernos en disco (acciones: ${acciones.join(' | ')})');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
