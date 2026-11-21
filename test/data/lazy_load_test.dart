import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Red de seguridad de la carga perezosa de hojas. REGLA DE ORO: una hoja sin cargar nunca se escribe, y nunca se
/// pierde nada al cargar, descargar, mover, borrar o insertar hojas.
///
/// Método: un MODELO DE REFERENCIA (un documento con todo cargado) al que se le aplican las mismas operaciones
/// que al documento perezoso. Después de cada paso (y de cada guardado) se compara hoja por hoja, en memoria y en
/// disco, y al final se reabre todo con otra `Storage`.
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('apuntes_lazy');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.deleteSync(recursive: true));

  // Forma canónica de una hoja para comparar: mover hojas suma y resta múltiplos de kSheetStep a los decimales de
  // textos y notas, y eso deja ruido de 1e-13 en el JSON; acá se redondea (los trazos ya se guardan en décimas).
  Object? round6(Object? v) => switch (v) {
        double d => (d * 1e6).round() / 1e6,
        Map m => {for (final e in m.entries) e.key: round6(e.value)},
        List l => [for (final e in l) round6(e)],
        _ => v,
      };
  String enc(SheetContent c) => jsonEncode(round6({
        'order': [
          for (final e in sortByZ([...c.items, ...c.strokes, ...c.texts]))
            switch (e) {
              Stroke s => {
                  'id': s.id,
                  'k': s.k,
                  'c': s.c,
                  'w': s.w,
                  'o': s.o,
                  'pts': [for (var i = 0; i < s.pts.length; i++) i % 3 == 2 ? (s.pts[i] * 255).round() : (s.pts[i] * 10).round()],
                },
              TextBlock t => {'t': t.toJson()..remove('z')},
              Item i => {'i': i.toJson()..remove('z')},
              _ => null,
            }
        ],
      }));
  String encFile(File f) => enc(decodeSheet(f.readAsBytesSync()));
  Uint8List bytesOf(Notebook nb, String sheetId) => store.sheetFile(nb.id, sheetId).readAsBytesSync();

  // coordenadas en décimas exactas: lo que se lee de disco es idéntico a lo que se escribió
  double tenth(Random r, int max) => r.nextInt(max * 10) / 10;

  Stroke stroke(Random r, String id, double y0) {
    final x0 = 50 + tenth(r, 600);
    final pts = <double>[];
    for (var i = 0; i < 6; i++) {
      pts.addAll([x0 + i * 12, y0 + tenth(r, 90), .5]);
    }
    return Stroke(id, 'pen', '#22211e', 2.6, pts);
  }

  /// Un documento de [n] hojas con contenido en cada una (todo cargado).
  NotebookDoc build(Random r, int n) {
    final nb = Notebook.create('T');
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    var e = 0;
    for (var k = 0; k < n; k++) {
      final top = k * kSheetStep;
      for (var i = 0; i < 2 + r.nextInt(3); i++) {
        final id = 's${e++}';
        d.strokes[id] = stroke(r, id, top + 80 + tenth(r, 1000))..z = d.nextZ();
      }
      d.texts['t$k'] = TextBlock('t$k', 90, d.snapTextY(top + 200 + r.nextInt(500)), 800, 'hoja $k')..z = d.nextZ();
      if (r.nextBool()) d.items['i$k'] = Item('i$k', 'sticky', 100, top + 700, 200, 150, text: 'nota $k')..z = d.nextZ();
    }
    return d;
  }

  /// Escribe [ref] en disco con [store] y abre otro documento perezoso del mismo cuaderno.
  Future<NotebookDoc> openLazy(NotebookDoc ref, {int around = 0, int radius = 1}) async {
    await store.saveNotebook(ref);
    return store.openNotebook(Notebook(ref.id, 'T'), around: around, radius: radius);
  }

  Future<Storage> fresh() async {
    final s = Storage(root: root);
    await s.init();
    return s;
  }

  List<String> files(Notebook nb) => Directory('${store.nbDir(nb.id).path}/sheets')
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .where((n) => n.endsWith('.sheet'))
      .toList()
    ..sort();

  String metaKey(SheetMeta m) => '${m.id}|${m.title}|${m.bookmark}|${m.bg}|${m.paper}|${m.spacing}';

  group('carga perezosa: lo básico', () {
    test('openNotebook carga solo las hojas cercanas y las demás quedan sin cargar', () async {
      final ref = build(Random(1), 10);
      final lazy = await openLazy(ref, around: 5, radius: 1);
      expect(lazy.sheetCount, 10, reason: 'todas las SheetMeta están siempre');
      expect([for (var k = 0; k < 10; k++) lazy.isLoadedAt(k)], [for (var k = 0; k < 10; k++) k >= 4 && k <= 6]);
      expect(lazy.texts.keys.toSet(), {'t4', 't5', 't6'});
      expect(lazy.hasDirty, isFalse);
    });

    test('un guardado con todo sucio escribe solo las cargadas, y las demás quedan intactas en disco', () async {
      final ref = build(Random(2), 8);
      final lazy = await openLazy(ref, around: 0, radius: 1);
      final before = {for (final m in lazy.sheets) m.id: bytesOf(lazy.nb, m.id)};
      final written = <String>[];
      store.onSheetWrite = (_, id) {
        written.add(id);
        expect(lazy.isLoaded(id), isTrue, reason: 'se escribió una hoja sin cargar');
      };
      lazy.markAllDirty();
      lazy.texts['t0']!.text = 'cambió';
      lazy.markDirtyElement(lazy.texts['t0']!);
      await store.saveNotebook(lazy);
      expect(written, [lazy.sheets[0].id], reason: 'solo cambió la hoja 0 (las demás cargadas codifican igual)');
      for (var k = 2; k < 8; k++) {
        expect(bytesOf(lazy.nb, lazy.sheets[k].id), before[lazy.sheets[k].id], reason: 'la hoja $k sin cargar cambió en disco');
      }
    });

    test('el primer guardado de un documento sin estado en disco no escribe hojas sin cargar', () async {
      final ref = build(Random(3), 5);
      await store.saveNotebook(ref);
      final lazy = NotebookDoc.lazy(Notebook(ref.id, 'T')..sheets.addAll(ref.sheets.map((m) => m.copy())));
      final store2 = Storage(root: root);
      await store2.init();
      final before = {for (final m in ref.sheets) m.id: bytesOf(ref.nb, m.id)};
      final w = <String>[];
      store2.onSheetWrite = (_, id) => w.add(id);
      lazy.markAllDirty();
      await store2.saveNotebook(lazy);
      expect(w, isEmpty);
      for (final m in ref.sheets) {
        expect(bytesOf(ref.nb, m.id), before[m.id]);
      }
    });

    test('attachSheet no pisa lo que ya está en memoria; detachSheet se niega si está sucia', () async {
      final ref = build(Random(4), 4);
      final lazy = await openLazy(ref, around: 0, radius: 0);
      final t = lazy.texts['t0']!;
      expect(lazy.attachSheet(lazy.sheets[0].id, SheetContent()), isFalse);
      expect(identical(lazy.texts['t0'], t), isTrue);
      t.text = 'sin guardar';
      lazy.markDirtyElement(t);
      expect(lazy.detachSheet(lazy.sheets[0].id), isFalse, reason: 'sucia: soltarla perdería lo escrito');
      expect(lazy.texts['t0']!.text, 'sin guardar');
    });

    test('las mallas de los trazos vienen armadas al cargar una hoja y se sueltan al descargarla', () async {
      final ref = build(Random(6), 4);
      final lazy = await openLazy(ref, around: 0, radius: 0);
      final id = lazy.sheets[2].id;
      expect(lazy.isLoaded(id), isFalse);
      await store.loadSheets(lazy, [id]);
      final strokes = [for (final s in lazy.strokes.values) if (lazy.sheetOfY(s.bounds.top) == 2) s];
      expect(strokes, isNotEmpty);
      expect(strokes.every((s) => s.mesh != null && s.mesh!.vertexCount > 0), isTrue, reason: 'armadas fuera del hilo de la UI');
      final r = await store.unloadSheets(lazy, [id]);
      expect(r.unloaded, [id]);
      expect(strokes.every((s) => s.mesh == null && s.batchCache == null), isTrue, reason: 'se soltaron con la hoja');
    });

    test('unloadSheets: se niega con cambios sin guardar, sin archivo conocido o si lo prohíbe canUnload', () async {
      final ref = build(Random(5), 6);
      final lazy = await openLazy(ref, around: 0, radius: 5);
      final id = lazy.sheets[3].id;
      lazy.texts['t3']!.text = 'otra cosa';
      lazy.markDirtyElement(lazy.texts['t3']!);
      var r = await store.unloadSheets(lazy, [id]);
      expect(r.unloaded, isEmpty, reason: 'sucia');
      r = await store.unloadSheets(lazy, [lazy.sheets[4].id], canUnload: (_) => false);
      expect(r.unloaded, isEmpty, reason: 'fijada por el editor');
      await store.saveNotebook(lazy);
      r = await store.unloadSheets(lazy, [id, lazy.sheets[4].id]);
      expect(r.unloaded.toSet(), {id, lazy.sheets[4].id});
      expect(lazy.texts.containsKey('t3'), isFalse);
      await store.loadSheets(lazy, [id]);
      expect(lazy.texts['t3']!.text, 'otra cosa', reason: 'lo guardado antes de soltarla vuelve al cargarla');
      // un documento que nunca se guardó no se puede soltar (no hay archivo que lo respalde)
      final nuevo = build(Random(6), 3);
      expect((await store.unloadSheets(nuevo, nuevo.sheets.map((m) => m.id))).unloaded, isEmpty);
      expect(nuevo.allLoaded, isTrue);
    });

    test('un cambio que se olvidó de marcar sucio se detecta al soltar: no se suelta y se marca para guardar', () async {
      final ref = build(Random(7), 4);
      final lazy = await openLazy(ref, around: 0, radius: 3);
      lazy.texts['t2']!.text = 'cambio mudo'; // sin markDirtyElement: el bug que la verificación atrapa
      final r = await store.unloadSheets(lazy, [lazy.sheets[2].id]);
      expect(r.unloaded, isEmpty);
      expect(r.healed, [lazy.sheets[2].id]);
      expect(lazy.isSheetDirty(lazy.sheets[2].id), isTrue);
      await store.saveNotebook(lazy);
      expect((await store.unloadSheets(lazy, [lazy.sheets[2].id])).unloaded, [lazy.sheets[2].id]);
      await store.loadSheets(lazy, [lazy.sheets[2].id]);
      expect(lazy.texts['t2']!.text, 'cambio mudo', reason: 'no se perdió');
    });

    test('soltar mientras se guarda espera al guardado: lo escrito se ve al volver a cargar', () async {
      final ref = build(Random(8), 5);
      final lazy = await openLazy(ref, around: 0, radius: 4);
      final id = lazy.sheets[4].id;
      lazy.texts['t4']!.text = 'en vuelo';
      lazy.markDirtyElement(lazy.texts['t4']!);
      final guardando = store.saveNotebook(lazy); // ya tomó lo sucio: la hoja ya no figura sucia
      final soltando = store.unloadSheets(lazy, [id]);
      await Future.wait([guardando, soltando]);
      await store.loadSheets(lazy, [id]);
      expect(lazy.isLoaded(id), isTrue);
      expect(lazy.texts['t4']!.text, 'en vuelo');
    });

    test('un elemento que cae en una hoja sin cargar se anota, y al cargarla se guarda sin perder nada', () async {
      final ref = build(Random(9), 6);
      final lazy = await openLazy(ref, around: 0, radius: 0);
      final t = lazy.texts['t0']!;
      lazy.markDirtyElement(t);
      t.y += 4 * kSheetStep; // a la hoja 4, que no está cargada
      lazy.markDirtyElement(t);
      final target = lazy.sheets[4].id;
      expect(lazy.misplacedSheets, {target});
      await store.saveNotebook(lazy); // hoja 4: no se escribe (no está cargada)
      expect(bytesOf(lazy.nb, target), isNotEmpty);
      await store.loadSheets(lazy, [target]);
      expect(lazy.misplacedSheets, isEmpty);
      expect(lazy.isSheetDirty(target), isTrue, reason: 'al cargarla se marca: tiene algo que el disco no tiene');
      expect(lazy.texts.keys.toSet(), {'t0', 't4'}, reason: 'lo del disco y lo que cayó, juntos');
      await store.saveNotebook(lazy);
      final back = await (await fresh()).openNotebook(Notebook(lazy.id, 'T'), radius: 6);
      expect(back.texts['t0']!.y, t.y);
    });

    test('operaciones de hojas con hojas sin cargar: borrar, mover e insertar no pierden nada', () async {
      final ref = build(Random(10), 8);
      final lazy = await openLazy(ref, around: 0, radius: 1);
      // se borra una hoja sin cargar: su archivo desaparece, las demás conservan su contenido
      final gone = lazy.sheets[5].id;
      ref.deleteSheet(5);
      lazy.deleteSheet(5);
      lazy.moveSheet(0, 3);
      ref.moveSheet(0, 3);
      final nueva = lazy.nb.newSheet();
      lazy.insertSheet(2, meta: nueva);
      ref.insertSheet(2, meta: nueva.copy());
      await store.saveNotebook(lazy);
      expect(files(lazy.nb).contains('$gone.sheet'), isFalse);
      expect(() => lazy.duplicateSheet(6), throwsStateError, reason: 'duplicar una hoja sin cargar pide cargarla antes');
      await store.loadSheets(lazy, lazy.sheets.map((m) => m.id));
      for (var k = 0; k < lazy.sheetCount; k++) {
        final id = lazy.sheets[k].id;
        final refK = ref.sheets.indexWhere((m) => m.id == id);
        expect(refK, isNonNegative);
        expect(enc(lazy.splitSheets({id})[id]!), enc(ref.splitBySheet()[refK]), reason: 'hoja ${k + 1} distinta');
      }
    });
  });

  group('carga perezosa: secuencias aleatorias contra un modelo de referencia', () {
    for (final seed in List.generate(12, (i) => 31 + i)) {
      test('semilla $seed: edición + operaciones de hojas + cargas y descargas + guardados', () async {
        final r = Random(seed);
        final ref = build(r, 9 + r.nextInt(5));
        var lazy = await openLazy(ref, around: r.nextInt(ref.sheetCount), radius: 1);
        var counter = 0;
        var healedTotal = 0, unloadCount = 0, loadCount = 0, dupCount = 0;
        String nid(String p) => '$p${seed}_${counter++}';
        final writes = <String>[];
        void hook(String nbId, String id) {
          writes.add(id);
          expect(lazy.isLoaded(id), isTrue, reason: 'semilla $seed: se escribió la hoja $id sin cargar');
        }

        store.onSheetWrite = hook;

        void both(void Function(NotebookDoc d) f) {
          f(lazy);
          f(ref);
        }

        List<int> loadedIdx() => [for (var k = 0; k < lazy.sheetCount; k++) if (lazy.isLoadedAt(k)) k];
        int? pickLoaded() {
          final l = loadedIdx();
          return l.isEmpty ? null : l[r.nextInt(l.length)];
        }

        String? pickEl(Map m) => m.isEmpty ? null : m.keys.elementAt(r.nextInt(m.length)) as String;

        /// Lo de memoria igual al modelo en cada hoja cargada, y nada de lo de las no cargadas.
        void checkMemory(String ctx) {
          expect(lazy.sheets.map(metaKey).toList(), ref.sheets.map(metaKey).toList(), reason: '$ctx: metas');
          final full = ref.splitBySheet();
          var expected = 0;
          for (var k = 0; k < lazy.sheetCount; k++) {
            final id = lazy.sheets[k].id;
            if (!lazy.isLoaded(id)) continue;
            expected += full[k].strokes.length + full[k].texts.length + full[k].items.length;
            expect(enc(lazy.splitSheets({id})[id]!), enc(full[k]), reason: '$ctx: la hoja $k en memoria no es igual al modelo');
          }
          expect(lazy.strokes.length + lazy.texts.length + lazy.items.length, expected,
              reason: '$ctx: hay elementos de hojas sin cargar en memoria (o faltan)');
        }

        /// Después de guardar: cada .sheet en disco == el modelo (las no cargadas no cambiaron en el modelo).
        Future<void> saveAndCheck(String ctx) async {
          final unloaded = {for (final m in lazy.sheets) if (!lazy.isLoaded(m.id) && store.sheetFile(lazy.id, m.id).existsSync()) m.id: bytesOf(lazy.nb, m.id)};
          await store.saveNotebook(lazy);
          for (final e in unloaded.entries) {
            if (lazy.indexOfSheet(e.key) < 0) continue;
            if (!lazy.isLoaded(e.key)) expect(bytesOf(lazy.nb, e.key), e.value, reason: '$ctx: la hoja sin cargar ${e.key} cambió en disco');
          }
          final full = ref.splitBySheet();
          for (var k = 0; k < lazy.sheetCount; k++) {
            final f = store.sheetFile(lazy.id, lazy.sheets[k].id);
            expect(f.existsSync(), isTrue, reason: '$ctx: falta el archivo de la hoja $k');
            expect(encFile(f), enc(full[k]), reason: '$ctx: la hoja $k en disco no es igual al modelo');
          }
          expect(files(lazy.nb), [for (final m in lazy.sheets) '${m.id}.sheet']..sort(), reason: '$ctx: sobran o faltan archivos');
          final j = jsonDecode(File('${store.nbDir(lazy.id).path}/notebook.json').readAsStringSync()) as Map;
          expect(jsonEncode(j), jsonEncode(lazy.nb.sheetsJson()), reason: '$ctx: notebook.json');
        }

        for (var step = 0; step < 160; step++) {
          final op = r.nextInt(20);
          var name = 'op$op';
          final k = pickLoaded();
          switch (op) {
            case 0 || 1: // trazo nuevo en una hoja cargada
              name = 'trazo';
              if (k == null) continue;
              final id = nid('s');
              final y = k * kSheetStep + 60 + tenth(r, 1200);
              final s1 = stroke(Random(counter), id, y), s2 = stroke(Random(counter), id, y);
              lazy.strokes[id] = s1..z = lazy.nextZ();
              ref.strokes[id] = s2..z = ref.nextZ();
            case 2: // texto nuevo
              name = 'texto';
              if (k == null) continue;
              final id = nid('t'), y = k * kSheetStep + 100 + r.nextInt(900), x = 40.0 + r.nextInt(300), txt = 'texto ${r.nextInt(99)}';
              both((d) => d.texts[id] = TextBlock(id, x, d.snapTextY(y), 500, txt)..z = d.nextZ());
            case 3: // nota
              name = 'nota';
              if (k == null) continue;
              final id = nid('i'), y = k * kSheetStep + 100 + r.nextInt(900), txt = 'n${r.nextInt(9)}';
              both((d) => d.items[id] = Item(id, 'sticky', 100, y, 200, 150, text: txt)..z = d.nextZ());
            case 4: // goma
              name = 'goma';
              final id = pickEl(lazy.strokes);
              if (id == null) continue;
              both((d) => d.strokes.remove(id));
            case 5: // borrar texto o nota
              name = 'borrar';
              final id = pickEl(lazy.texts) ?? pickEl(lazy.items);
              if (id == null) continue;
              both((d) {
                d.texts.remove(id);
                d.items.remove(id);
              });
            case 6: // editar un texto en el lugar
              name = 'editar';
              final id = pickEl(lazy.texts);
              if (id == null) continue;
              final add = ' ${r.nextInt(99)}';
              both((d) {
                final t = d.texts[id]!;
                t.text = '${t.text}$add';
                d.markDirtyElement(t);
              });
            case 7: // mover trazos y textos a otra hoja CARGADA (como soltar una selección)
              name = 'mover';
              final to = pickLoaded();
              final id = pickEl(lazy.strokes);
              final tid = pickEl(lazy.texts);
              if (to == null) continue;
              if (id != null) {
                final dy = (to - lazy.sheetOfElement(lazy.strokes[id]!)) * kSheetStep + tenth(r, 100);
                both((d) {
                  final m = d.strokes.remove(id)!.moved(Offset(tenth(Random(counter), 50), dy));
                  d.strokes[id] = m;
                  d.stackOnTop([m]); // el z de lo movido depende del orden de carga: se lo deja arriba en los dos
                });
              }
              if (tid != null) {
                final ty = to * kSheetStep + 150 + r.nextInt(600).toDouble();
                both((d) {
                  final t = d.texts[tid]!;
                  d.markDirtyElement(t);
                  t.y = d.snapTextY(ty);
                  d.markDirtyElement(t);
                  d.stackOnTop([t]);
                });
              }
            case 8: // al frente
              name = 'orden';
              final ids = {for (final i in [...lazy.strokes.keys, ...lazy.texts.keys]) if (r.nextInt(4) == 0) i};
              both((d) => d.stackOnTop([for (final i in ids) ?(d.strokes[i] ?? d.texts[i])]));
            case 9: // hoja nueva al final o en el medio
              name = 'insertar';
              final at = r.nextInt(lazy.sheetCount + 1);
              final m = lazy.nb.newSheet();
              lazy.insertSheet(at, meta: m);
              ref.insertSheet(at, meta: m.copy());
            case 10: // borrar hoja (cargada o no)
              name = 'borrar hoja';
              if (lazy.sheetCount < 3) continue;
              final i = r.nextInt(lazy.sheetCount);
              both((d) => d.deleteSheet(i));
            case 11: // mover hoja
              name = 'mover hoja';
              final a = r.nextInt(lazy.sheetCount), b = r.nextInt(lazy.sheetCount);
              both((d) => d.moveSheet(a, b));
            case 12: // duplicar (la hoja se carga antes, como en la pantalla)
              name = 'duplicar';
              final i = r.nextInt(lazy.sheetCount);
              await store.loadSheets(lazy, [lazy.sheets[i].id]);
              dupCount++;
              final dup = lazy.duplicateSheet(i);
              final content = lazy.splitSheets({dup.id})[dup.id]!;
              ref.insertSheet(i + 1, meta: dup.copy(), content: content);
            case 13: // título / fondo
              name = 'estilo';
              final i = r.nextInt(lazy.sheetCount);
              final bg = const ['grid', 'dots', 'lined', 'blank'][r.nextInt(4)], title = 'h${r.nextInt(9)}';
              final useBg = r.nextBool();
              both((d) => useBg ? d.sheets[i].setBg(bg) : d.sheets[i].title = title);
            case 14: // otra vez el estilo
              name = 'papel';
              final i = r.nextInt(lazy.sheetCount);
              both((d) => d.sheets[i].bookmark = !d.sheets[i].bookmark);
            case 15 || 16: // cargar hojas al azar (como scrollear)
              name = 'cargar';
              final from = r.nextInt(lazy.sheetCount), n = 1 + r.nextInt(3);
              loadCount += (await store.loadSheets(lazy, [for (var i = from; i < min(lazy.sheetCount, from + n); i++) lazy.sheets[i].id])).length;
            case 17 || 18: // descargar hojas al azar (a veces "fijadas" por el editor)
              name = 'descargar';
              final pinned = {for (final m in lazy.sheets) if (r.nextInt(5) == 0) m.id};
              final ids = [for (final m in lazy.sheets) if (r.nextInt(3) == 0) m.id];
              final res = await store.unloadSheets(lazy, ids, canUnload: (id) => !pinned.contains(id));
              healedTotal += res.healed.length;
              unloadCount += res.unloaded.length;
              for (final id in res.unloaded) {
                expect(pinned.contains(id), isFalse, reason: 'se soltó una hoja fijada');
              }
            case 19: // guardar y soltar a la vez / guardar mientras se carga
              name = 'carrera';
              final from = r.nextInt(lazy.sheetCount);
              final f = store.saveNotebook(lazy);
              final u = store.unloadSheets(lazy, [for (var i = 0; i < lazy.sheetCount; i += 2) lazy.sheets[i].id]);
              final l = store.loadSheets(lazy, [lazy.sheets[from].id]);
              await Future.wait([f, u.then((x) => healedTotal += x.healed.length), l]);
          }
          checkMemory('semilla $seed, paso $step ($name)');
          if (r.nextInt(4) != 0) await saveAndCheck('semilla $seed, paso $step ($name)');
        }
        expect(healedTotal, 0, reason: 'con las operaciones bien marcadas nada se "cura" al soltar');

        // al final: se guarda, y otra Storage que abre todo ve EXACTAMENTE el modelo
        await saveAndCheck('semilla $seed, final');
        final store2 = await fresh();
        final back = await store2.loadNotebook(Notebook(lazy.id, 'T'));
        final full = ref.splitBySheet();
        expect(back.sheets.map(metaKey).toList(), ref.sheets.map(metaKey).toList());
        for (var k = 0; k < back.sheetCount; k++) {
          expect(enc(back.splitBySheet()[k]), enc(full[k]), reason: 'semilla $seed: al reabrir, la hoja $k no es igual al modelo');
        }
        // y se vuelve a abrir perezoso (otra posición), se carga todo y es lo mismo
        final store3 = await fresh();
        final again = await store3.openNotebook(Notebook(lazy.id, 'T'), around: back.sheetCount ~/ 2, radius: 1);
        await store3.loadSheets(again, again.sheets.map((m) => m.id));
        expect(again.allLoaded, isTrue);
        for (var k = 0; k < again.sheetCount; k++) {
          final id = again.sheets[k].id;
          expect(enc(again.splitSheets({id})[id]!), enc(full[k]), reason: 'semilla $seed: reapertura perezosa, hoja $k');
        }
        expect(writes, isNotEmpty);
        expect([unloadCount, loadCount, dupCount].every((n) => n > 0), isTrue, reason: 'la secuencia tiene que ejercitar todo');
      });
    }
  });

  group('carga perezosa: búsqueda, exportación y copia sin cargar el cuaderno', () {
    test('readSheetTexts lee de disco los textos y notas de una hoja sin cargarla', () async {
      final ref = build(Random(41), 5);
      ref.items['i3'] = Item('i3', 'sticky', 100, 3 * kSheetStep + 700, 200, 150, text: 'nota tres');
      final lazy = await openLazy(ref, around: 0, radius: 0);
      final texts = await store.readSheetTexts(lazy.nb, lazy.sheets[3]);
      expect(texts.map((t) => t.text), containsAll(['hoja 3', 'nota tres']));
      expect(lazy.isLoaded(lazy.sheets[3].id), isFalse);
    });

    test('copyNotebookFiles copia los archivos de las hojas sin cargar nada', () async {
      final ref = build(Random(42), 6);
      await store.saveNotebook(ref);
      final src = Notebook(ref.id, 'T');
      await store.loadSheetDoc(src..sheets.addAll(ref.sheets.map((m) => m.copy())), 0);
      final copy = Notebook('ncopia', 'T (copia)')..sheets.addAll(src.sheets.map((m) => m.copy()));
      await store.copyNotebookFiles(src, copy);
      final back = await (await fresh()).loadNotebook(Notebook('ncopia', 'x'));
      final full = ref.splitBySheet();
      expect(back.sheetCount, 6);
      for (var k = 0; k < 6; k++) {
        expect(enc(back.splitBySheet()[k]), enc(full[k]));
      }
    });
  });
}
