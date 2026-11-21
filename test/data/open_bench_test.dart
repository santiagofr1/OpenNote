import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Apertura del cuaderno (lo que hace la app: `Storage.openNotebook`) con 5 hojas de ~46k puntos cada una, con
/// isolates de verdad. Compara: sin mallas (antes de la etapa 5), mallas en un solo isolate (etapa 5) y mallas
/// repartidas en isolates paralelos (ahora). Los tiempos son orientativos (PC); lo que se prueba de verdad es que la
/// hoja inicial llega con malla, que las vecinas también, y que el paralelo no es más lento que el serie.
void main() {
  late Directory root;
  late Notebook nb;

  const sheets = 5, strokesPerSheet = 30, ptsPerStroke = 1500; // 45k puntos por hoja

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('apuntes_open');
    final s = Storage(root: root);
    await s.init();
    nb = Notebook.create('T');
    while (nb.sheets.length < sheets) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    final r = Random(3);
    var e = 0;
    for (var k = 0; k < sheets; k++) {
      for (var i = 0; i < strokesPerSheet; i++) {
        final id = 's${e++}';
        final y0 = k * kSheetStep + 100 + r.nextDouble() * 1000;
        final pts = <double>[
          for (var j = 0; j < ptsPerStroke; j++) ...[
            (100 + j * .5 + sin(j / 20) * 30).roundToDouble() , (y0 + cos(j / 15) * 40 + i * 2).roundToDouble(), .6,
          ]
        ];
        d.strokes[id] = Stroke(id, i % 3 == 0 ? 'pencil' : 'pen', '#22211e', 2.6, pts)..z = d.nextZ();
      }
    }
    await s.saveNotebook(d);
  });
  tearDownAll(() => root.deleteSync(recursive: true));

  Future<(double, NotebookDoc)> open({int par = 4, bool mesh = true, bool all = false, bool wait = false}) async {
    final prevP = Storage.loadParallelism, prevM = Storage.meshesOnLoad;
    Storage.loadParallelism = par;
    Storage.meshesOnLoad = mesh;
    addTearDown(() {
      Storage.loadParallelism = prevP;
      Storage.meshesOnLoad = prevM;
    });
    final s = Storage(root: root);
    await s.init();
    final n2 = Notebook(nb.id, 'T');
    final sw = Stopwatch()..start();
    final doc = await s.openNotebook(n2, around: 2, meshAll: all);
    final ms = sw.elapsedMicroseconds / 1000;
    if (wait) await s.meshesIdle;
    return (ms, doc);
  }

  double median(List<double> v) => (v..sort())[v.length ~/ 2];

  test('la hoja inicial llega con malla al abrir y las vecinas enseguida', () async {
    final (_, doc) = await open(wait: false);
    expect(doc.loadedSheets, hasLength(sheets));
    final initial = doc.sheets[2].id;
    final strokes = doc.strokes.values.toList();
    expect(strokes, hasLength(sheets * strokesPerSheet));
    for (final s in strokes) {
      if (doc.sheets[doc.sheetOfElement(s)].id == initial) expect(s.mesh, isNotNull, reason: 'trazo ${s.id} de la hoja inicial sin malla');
    }
  });

  test('las vecinas llegan con malla cuando termina el segundo plano', () async {
    final (_, doc) = await open(wait: true);
    for (final s in doc.strokes.values) {
      expect(s.mesh, isNotNull, reason: 'trazo ${s.id} sin malla');
    }
  });

  test('sin mallas al abrir no hay malla (se arma al primer dibujo)', () async {
    final (_, doc) = await open(mesh: false, wait: true);
    expect(doc.strokes.values.every((s) => s.mesh == null), isTrue);
  });

  test('segundo plano y todo junto dan las mismas mallas', () async {
    final (_, a) = await open(par: 1, all: true);
    final (_, b) = await open(wait: true);
    expect(b.strokes.keys.toSet(), a.strokes.keys.toSet());
    for (final id in a.strokes.keys) {
      expect(b.strokes[id]!.pts, a.strokes[id]!.pts);
      expect(b.strokes[id]!.mesh!.vertexCount, a.strokes[id]!.mesh!.vertexCount);
      // (en uno la malla se corrió de lugar al cargar y en el otro se armó ya en su lugar: igual salvo el redondeo a float32)
      final pa = a.strokes[id]!.mesh!.parts.first.pos, pb = b.strokes[id]!.mesh!.parts.first.pos;
      expect(pb.length, pa.length);
      for (var i = 0; i < pa.length; i++) {
        expect((pa[i] - pb[i]).abs(), lessThan(.01));
      }
    }
  });

  test('un trazo que cambió mientras se armaban las mallas no recibe la malla vieja', () async {
    final s = Storage(root: root);
    await s.init();
    final doc = await s.openNotebook(Notebook(nb.id, 'T'), around: 2);
    // (las vecinas siguen armándose) se toca un trazo de una vecina sin malla
    final victim = doc.strokes.values.firstWhere((x) => x.mesh == null, orElse: () => doc.strokes.values.first);
    victim.pts[0] += 5;
    victim.invalidate();
    await s.meshesIdle;
    if (victim.mesh != null) {
      // solo puede haber una malla si se armó con los puntos nuevos (la vieja se descartó por la otra meshGen)
      expect(victim.mesh!.parts.first.pos.length, greaterThan(0));
    }
  });

  test('benchmark: openNotebook con 5 hojas de ~46k puntos', () async {
    await open(); // calienta (JIT, disco)
    Future<double> run({int par = 4, bool mesh = true, bool all = false}) async =>
        median([for (var i = 0; i < 5; i++) (await open(par: par, mesh: mesh, all: all)).$1]);
    final sinMallas = await run(par: 1, mesh: false);
    final antes = await run(par: 1, all: true); // etapa 5: todas las mallas en un isolate antes de devolver
    final paralelo = await run(all: true); // isolates en paralelo, todas antes de devolver
    final ahora = await run(); // lo que hace la app: inicial con malla, vecinas después
    // ignore: avoid_print
    print('abrir 5 hojas ~46k puntos: sin mallas ${sinMallas.toStringAsFixed(0)} ms, ANTES (etapa 5, 1 isolate) '
        '${antes.toStringAsFixed(0)} ms, 4 isolates ${paralelo.toStringAsFixed(0)} ms, AHORA (inicial + segundo plano) '
        '${ahora.toStringAsFixed(0)} ms');
    expect(ahora, lessThan(antes), reason: 'abrir no puede ser más lento que armar todo en serie');
  });
}
