// Benchmark de cuadernos grandes en la tablet (NO es parte de app_test.dart). Mide cuánto cuesta abrir, guardar,
// scrollear y tener en memoria cuadernos de 50, 100, 200 y 400 hojas, para decidir si hace falta la carga perezosa
// de hojas lejanas (PENDIENTES.md, punto 1). Todo en una carpeta temporal propia: nunca toca tus cuadernos.
//
// Se corre con tool/perf.sh (build profile + `flutter drive`; deja build/perf/perf.json y build/perf/perf.log).
// Los tamaños se eligen al compilar: --dart-define=PERF_SIZES=50,100 (por defecto 50,100,200,400).
//
// Qué mide cada número:
//   puntos / disco        puntos de tinta del cuaderno y tamaño de su carpeta (hojas + notebook.json)
//   leer+decodificar      (solo hasta 100 hojas; después SALTEADO) Storage.loadNotebook (TODO el cuaderno, como se abría antes de la carga perezosa; hoy solo lo usan
//                         duplicar y los tests, queda para comparar): leer los .sheet, descomprimir y armar el NotebookDoc.
//                         Mediana de 3 corridas con Storage nuevo (el sistema ya tiene los archivos en caché).
//   abrir perezoso        Storage.openNotebook (lo que hace la app al abrir): notebook.json y solo las hojas de la mitad
//                         del cuaderno ±2. Mediana de 3 corridas.
//   bloqueo hilo principal  mayor tiempo seguido que el hilo de la UI no atendió eventos mientras corría (timer de 2 ms)
//   abrir por la UI       desde tocar el cuaderno en la biblioteca hasta que el PageEditor está construido (incluye
//                         la lectura y la animación de entrada)
//   guardar 1 trazo       Storage.saveNotebook después de agregar UN trazo en una hoja: codifica TODAS las hojas en otro
//                         isolate, compara hashes y escribe solo la que cambió. "sin cambios" = lo mismo sin tocar nada
//   scroll                dedo (fling) en el PageEditor, en el inicio, el medio y el final del cuaderno; FrameTiming de
//                         cada frame: build y raster (promedio / p90 / p99) y frames con total > 16,7 ms
//   RSS                   memoria residente del proceso (ProcessInfo.currentRss / maxRss; maxRss no baja nunca)
//   PDF                   buildNotebookPdf del cuaderno de 100 hojas (se saltea si se estima > 2 min)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'hershey_script.dart';

const _sizesEnv = String.fromEnvironment('PERF_SIZES', defaultValue: '50,100,200,400');
const _pdfSheets = 100; // tamaño con el que se prueba la exportación
const _fullLoadMax = 100; // por encima de esto no se decodifica el cuaderno entero (la app ya no abre así; en la tablet muere)

// Modo comparación con Samsung Notes (tool/comparar.sh): --dart-define=PERF_COMPARE=34 corre SOLO ese caso (en horizontal,
// sin scrollear solo: mide FrameTiming mientras un script externo hace swipes con adb) y no los tamaños.
const _compareEnv = String.fromEnvironment('PERF_COMPARE', defaultValue: '');
const _compareWindowSeconds = 40;

// Modo traza (tool/traza.sh): --dart-define=PERF_TRACE=50 corre SOLO ese caso: genera N hojas, abre por la UI y hace
// el scroll "medio" (6 flings) dentro de binding.traceAction, que deja la línea de tiempo en reportData['timeline'].
const _traceEnv = String.fromEnvironment('PERF_TRACE', defaultValue: '');

const _phrases = [
  'La ley de Snell relaciona los angulos de incidencia',
  'Ecuacion de la recta y = 3x + 2 con pendiente 3',
  'Resumen del capitulo 4 de termodinamica y calor',
  'Ejercicio 12, calcular la velocidad media del tren',
  'El teorema de Pitagoras vale en triangulos rectos',
  'Pasos del metodo cientifico, observar y medir datos',
  'La derivada de x al cuadrado es dos veces x, siempre',
  'Importante para el parcial del jueves, repasar todo',
  'Fuerza igual a masa por aceleracion, segunda ley',
  'Integral definida entre 0 y 1, area bajo la curva',
  'Notas de la clase de hoy sobre ondas y sonido',
  'Revisar las unidades antes de reemplazar en la formula',
];

// ---------------------------------------------------------------- generación (en otro isolate)
/// Escribe en [path] un cuaderno de [n] hojas con ~25 renglones a mano y 3 resaltados por hoja.
/// Corre en un isolate aparte y hoja por hoja: cada hoja se codifica y se escribe a disco apenas se genera, así
/// nunca hay más de una en memoria (ni en este proceso ni en el isolate).
/// Devuelve (puntos, trazos).
Future<(int, int)> generateNotebookAsync(Directory root, int n, String name) {
  final path = root.path; // el Directory no se puede mandar a otro isolate: solo la ruta
  return Isolate.run(() => _generate(path, n, name));
}

Future<(int, int)> _generate(String path, int n, String name) async {
  final s = Storage(root: Directory(path));
  await s.init();
  final nb = Notebook(newId('n'), name);
  var points = 0, strokes = 0;
  for (var k = 0; k < n; k++) {
    final r = Random(1000 + k);
    final meta = nb.newSheet();
    nb.sheets.add(meta);
    final c = SheetContent();
    for (var i = 0; i < 25; i++) {
      final base = 90.0 + i * 38.1;
      final text = _phrases[r.nextInt(_phrases.length)];
      c.strokes.addAll(handwrite(text, Offset(120, base - 3), rnd: r, size: 1.12, maxWidth: 800));
    }
    for (var h = 0; h < 3; h++) {
      final y = 90.0 + r.nextInt(24) * 38.1 - 12, x0 = 120.0 + r.nextInt(200), x1 = x0 + 200 + r.nextInt(400);
      final pts = <double>[];
      for (var x = x0; x <= x1; x += 3) {
        pts.addAll([x, y + (r.nextDouble() - .5) * .6, .5]);
      }
      c.strokes.add(Stroke(newId('s'), 'hl', '#fde047', 16, pts, .4));
    }
    for (final st in c.strokes) {
      points += st.n;
    }
    strokes += c.strokes.length;
    // el contenido de cada hoja es local (como lo guarda Storage): se escribe directo, sin armar el NotebookDoc global
    final f = s.sheetFile(nb.id, meta.id);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(encodeSheet(c), flush: true);
  }
  await File('${s.nbDir(nb.id).path}/notebook.json').writeAsString(jsonEncode(nb.sheetsJson()), flush: true);
  await s.saveIndex(NotesIndex(last: nb.id, notebooks: [nb]));
  return (points, strokes);
}

// ---------------------------------------------------------------- medición
final _sw = Stopwatch()..start();

/// Ejecuta [f] y mide el mayor tiempo seguido que el hilo principal no atendió eventos (ms, menos el período del timer).
Future<(T, double)> withStall<T>(Future<T> Function() f) async {
  var last = _sw.elapsedMicroseconds, worst = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
    final now = _sw.elapsedMicroseconds;
    worst = max(worst, now - last);
    last = now;
  });
  try {
    final v = await f();
    return (v, max(0.0, (worst - 2000) / 1000));
  } finally {
    timer.cancel();
  }
}

double ms(Duration d) => d.inMicroseconds / 1000;
double r1(num v) => (v * 10).round() / 10;
double median(List<double> v) => (List.of(v)..sort())[v.length ~/ 2];
double pct(List<double> sorted, double p) => sorted.isEmpty ? 0 : sorted[(p * (sorted.length - 1)).round()];
double mb(int bytes) => r1(bytes / 1048576);

/// Qué pasaba en un cuadro (se anota al terminar de armarlo, no cuando llega su FrameTiming).
class _Sample {
  final int ts; // vsyncStart del cuadro (µs), el mismo reloj que FrameTiming
  final bool vector, gen;
  final double off, delta; // posición del scroll y cuánto se movió desde el cuadro anterior (|delta|)
  _Sample(this.ts, this.vector, this.gen, this.off, this.delta);
}

/// Junta los FrameTiming que reporta el motor (llegan en tandas, hasta ~1 s después de cada frame) y, por cada cuadro,
/// una muestra barata de cómo se estaba dibujando la tinta ([probe]: hojas visibles en vectorial y contador
/// de generación de imágenes). Los dos se juntan por el instante de inicio del cuadro.
class FrameRecorder {
  final _all = <FrameTiming>[];
  final _samples = <_Sample>[];
  ({bool vector, int activity, double offset})? Function()? probe;
  bool _sampling = false;
  int _lastActivity = 0;
  double _lastOff = 0;
  void _cb(List<FrameTiming> l) => _all.addAll(l);

  void attach() {
    SchedulerBinding.instance.addTimingsCallback(_cb);
    _sampling = true;
    _chain();
  }

  void detach() {
    _sampling = false;
    SchedulerBinding.instance.removeTimingsCallback(_cb);
  }

  void _chain() {
    if (!_sampling) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final p = probe?.call();
      if (p != null) {
        final gen = p.activity != _lastActivity;
        _lastActivity = p.activity;
        final delta = (p.offset - _lastOff).abs();
        _lastOff = p.offset;
        _samples.add(_Sample(
            SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds, p.vector, gen, p.offset, delta));
      }
      _chain();
    });
  }

  /// Descarta lo anterior (después de dejar que lleguen las tandas pendientes).
  Future<void> mark() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    _all.clear();
    _samples.clear();
  }

  /// Resumen de los frames desde el último [mark]. Con [onlyMoving] cuenta solo los de la ventana en que el scroll se
  /// movió: desde el primer cuadro con cambio de offset hasta 500 ms después del último (la ventana de medición de
  /// la comparación incluye pausas entre swipes y el principio y el final sin tocar nada).
  Future<Map<String, Object>> take({bool onlyMoving = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    var fr = List.of(_all);
    final samples = List.of(_samples)..sort((a, b) => a.ts.compareTo(b.ts));
    _all.clear();
    _samples.clear();
    int vs(FrameTiming f) => f.timestampInMicroseconds(FramePhase.vsyncStart);
    // la muestra del cuadro: la más cercana a su vsyncStart (tolerancia 3 ms)
    _Sample? sampleOf(FrameTiming f) {
      final t = vs(f);
      var lo = 0, hi = samples.length;
      while (lo < hi) {
        final m = (lo + hi) ~/ 2;
        if (samples[m].ts < t) {
          lo = m + 1;
        } else {
          hi = m;
        }
      }
      _Sample? best;
      for (final i in [lo - 1, lo]) {
        if (i < 0 || i >= samples.length) continue;
        if ((samples[i].ts - t).abs() <= 3000 && (best == null || (samples[i].ts - t).abs() < (best.ts - t).abs())) {
          best = samples[i];
        }
      }
      return best;
    }

    var t0 = 0, t1 = 1 << 62, activeMs = 0.0;
    var walked = 0.0;
    var win = samples;
    if (onlyMoving) {
      final moving = [for (final s in samples) if (s.delta > .5) s];
      if (moving.isEmpty) {
        t0 = 1 << 62;
        t1 = 0;
        win = const [];
      } else {
        t0 = moving.first.ts;
        t1 = moving.last.ts + 500000;
        win = [for (final s in samples) if (s.ts >= t0 && s.ts <= t1) s];
      }
      activeMs = t1 > t0 ? (t1 - t0) / 1000 : 0;
      fr = [for (final f in fr) if (vs(f) >= t0 && vs(f) <= t1) f];
    }
    for (final s in win) {
      walked += s.delta;
    }
    final build = [for (final f in fr) ms(f.buildDuration)]..sort();
    final raster = [for (final f in fr) ms(f.rasterDuration)]..sort();
    final total = [for (final f in fr) ms(f.totalSpan)]..sort();
    double avg(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    // por grupo: cuadros con hoja vectorial / con generación de imagen, y cuántos de ellos pasan de 16 ms
    var vec = 0, vecSlow = 0, gen = 0, genSlow = 0, noSample = 0;
    for (final f in fr) {
      final s = sampleOf(f);
      if (s == null) {
        noSample++;
        continue;
      }
      final slow = ms(f.totalSpan) > 16.7;
      if (s.vector) {
        vec++;
        if (slow) vecSlow++;
      }
      if (s.gen) {
        gen++;
        if (slow) genSlow++;
      }
    }
    return {
      'frames': fr.length,
      if (onlyMoving) 'ventana_activa_ms': r1(activeMs),
      'recorrido_total_px': r1(walked),
      'build_prom_ms': r1(avg(build)),
      'build_p50_ms': r1(pct(build, .5)),
      'build_p90_ms': r1(pct(build, .9)),
      'build_p99_ms': r1(pct(build, .99)),
      'raster_prom_ms': r1(avg(raster)),
      'raster_p50_ms': r1(pct(raster, .5)),
      'raster_p90_ms': r1(pct(raster, .9)),
      'raster_p99_ms': r1(pct(raster, .99)),
      'total_peor_ms': r1(total.isEmpty ? 0 : total.last),
      'frames_mas_16ms': total.where((t) => t > 16.7).length,
      'frames_mas_16ms_pct': total.isEmpty ? 0.0 : r1(100 * total.where((t) => t > 16.7).length / total.length),
      'frames_mas_33ms': total.where((t) => t > 33.4).length,
      'frames_vectorial': vec,
      'frames_vectorial_mas_16ms': vecSlow,
      'frames_generacion': gen,
      'frames_generacion_mas_16ms': genSlow,
      'frames_sin_muestra': noSample,
    };
  }
}

int dirBytes(Directory d) {
  var t = 0;
  if (!d.existsSync()) return 0;
  for (final e in d.listSync(recursive: true)) {
    if (e is File) t += e.lengthSync();
  }
  return t;
}

String modo() => kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final compare = _compareEnv.isEmpty ? null : int.parse(_compareEnv.trim());
  final trace = _traceEnv.isEmpty ? null : int.parse(_traceEnv.trim());
  final sizes = compare != null || trace != null ? <int>[] : [for (final s in _sizesEnv.split(',')) int.parse(s.trim())];
  final results = <String, Object>{'modo': modo(), 'tamanios': sizes};
  if (compare != null) results['comparar_hojas'] = compare;
  if (trace != null) results['traza_hojas'] = trace;
  final frames = FrameRecorder();
  final lines = <String>[];

  void say(String s) {
    lines.add(s);
    // ignore: avoid_print
    print('PERF $s');
  }

  void publish() {
    results['tabla'] = List.of(lines);
    binding.reportData = Map<String, dynamic>.of(results);
  }

  /// "con hoja vectorial A (>16 ms: B), con generación C (D)" de un resumen de [FrameRecorder.take].
  String groups(Map<String, Object> f) => 'frames con hoja vectorial ${f['frames_vectorial']} (>16 ms: ${f['frames_vectorial_mas_16ms']}), '
      'con generación ${f['frames_generacion']} (${f['frames_generacion_mas_16ms']}), sin muestra ${f['frames_sin_muestra']}';

  /// Qué dibuja el editor abierto (si hay uno): la muestra por cuadro de [FrameRecorder].
  frames.probe = () {
    final els = find.byType(PageEditor).evaluate();
    if (els.isEmpty) return null;
    final ed = (els.first as StatefulElement).state as PageEditorState;
    if (!ed.scroll.hasClients || !ed.scroll.position.hasPixels) return null;
    final s = ed.imageFrameState;
    return (vector: s.vector, activity: s.activity, offset: ed.scroll.offset);
  };

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  setUpAll(frames.attach);
  tearDownAll(() {
    frames.detach();
    if (compare == null) {
      // tabla resumen entre tamaños
      say('');
      say('===== RESUMEN (modo ${modo()}) =====');
      say('hojas | puntos | disco MB | leer+decod ms | abrir perezoso ms | abrir UI ms | guardar 1 trazo ms | scroll build p90 | '
          'scroll raster p90 | >16ms % | RSS abierto MB | maxRSS MB');
      for (final n in sizes) {
        final m = results['$n'];
        if (m is! Map) continue;
        final sc = [for (final z in ['inicio', 'medio', 'final']) m['scroll_$z']].whereType<Map>().toList();
        double worst(String k) => sc.isEmpty ? 0 : sc.map((e) => (e[k] as num).toDouble()).reduce(max);
        final fr = sc.fold<int>(0, (a, e) => a + (e['frames'] as int));
        final slow = sc.fold<int>(0, (a, e) => a + (e['frames_mas_16ms'] as int));
        say('$n | ${m['puntos']} | ${m['disco_mb']} | ${m['leer_decodificar_ms'] ?? '-'} | ${m['abrir_perezoso_ms']} | '
            '${m['abrir_ui_ms']} | ${m['guardar_1_trazo_ms']} | ${worst('build_p90_ms')} | ${worst('raster_p90_ms')} | '
            '${fr == 0 ? '-' : r1(100 * slow / fr)} | ${m['rss_abierto_mb']} | ${m['rss_max_mb']}');
      }
    }
    publish();
  });

  /// Genera el cuaderno de [n] hojas en [root] (hoja por hoja, en otro isolate) y deja sus números en [out].
  Future<void> generate(int n, Directory root, Map<String, Object?> out) async {
    final sw = Stopwatch()..start();
    final (points, strokes) = await generateNotebookAsync(root, n, 'Perf $n');
    final bytes = dirBytes(root);
    out['puntos'] = points;
    out['trazos'] = strokes;
    out['disco_mb'] = mb(bytes);
    say('--- $n hojas: $points puntos en $strokes trazos (${r1(points / n)} puntos/hoja), '
        'disco ${mb(bytes)} MB (generar: ${r1(ms(sw.elapsed) / 1000)} s) ---');
    await Future<void>.delayed(const Duration(seconds: 1));
    out['rss_inicio_mb'] = mb(ProcessInfo.currentRss);
  }

  /// Los pasos de Storage (leer, abrir perezoso, guardar, PDF). Es una función aparte para que, al volver, no quede
  /// ninguna referencia viva a los documentos (el RSS que se mide después es el de la UI, no el de estos pasos).
  Future<void> storageSteps(int n, Directory root, Map<String, Object?> out) async {
    final skipFull = n > _fullLoadMax;
    var sw = Stopwatch();
    NotebookDoc? doc;
    late Storage s;

    // ---------- (a) leer + decodificar con Storage (solo hasta _fullLoadMax hojas) ----------
    if (skipFull) {
      out['leer_decodificar_ms'] = null;
      out['leer_decodificar_corridas_ms'] = null;
      out['leer_decodificar_bloqueo_ms'] = null;
      say('leer+decodificar: SALTEADO (n > $_fullLoadMax, la app ya no abre así)');
    } else {
      final reads = <double>[];
      var stall = 0.0;
      for (var i = 0; i < 3; i++) {
        s = Storage(root: root);
        await s.init();
        final idx = await s.loadIndex();
        sw = Stopwatch()..start();
        final (dd, st) = await withStall(() => s.loadNotebook(idx.notebooks.first));
        reads.add(ms(sw.elapsed));
        stall = max(stall, st);
        doc = dd;
      }
      out['leer_decodificar_ms'] = r1(median(reads));
      out['leer_decodificar_corridas_ms'] = [for (final v in reads) r1(v)];
      out['leer_decodificar_bloqueo_ms'] = r1(stall);
      say('leer+decodificar (Storage): mediana ${out['leer_decodificar_ms']} ms (corridas ${out['leer_decodificar_corridas_ms']}), '
          'bloqueo máx del hilo principal ${r1(stall)} ms');
    }

    // ---------- (a ter) abrir perezoso con Storage.openNotebook (como la app) ----------
    final lazyReads = <double>[];
    var lazyStall = 0.0;
    var lazyLoaded = 0;
    for (var i = 0; i < 3; i++) {
      final s2 = Storage(root: root);
      await s2.init();
      final idx = await s2.loadIndex();
      sw = Stopwatch()..start();
      final (dd, st) = await withStall(() => s2.openNotebook(idx.notebooks.first, around: n ~/ 2));
      lazyReads.add(ms(sw.elapsed));
      lazyStall = max(lazyStall, st);
      lazyLoaded = dd.loadedSheets.length;
    }
    out['abrir_perezoso_ms'] = r1(median(lazyReads));
    out['abrir_perezoso_corridas_ms'] = [for (final v in lazyReads) r1(v)];
    out['abrir_perezoso_hojas_cargadas'] = lazyLoaded;
    out['abrir_perezoso_bloqueo_ms'] = r1(lazyStall);
    say('abrir perezoso (Storage.openNotebook, $lazyLoaded hojas): mediana ${out['abrir_perezoso_ms']} ms '
        '(corridas ${out['abrir_perezoso_corridas_ms']}), bloqueo máx ${r1(lazyStall)} ms');

    // ---------- (b) guardar después de agregar UN trazo ----------
    // hasta _fullLoadMax: con el documento entero (codifica todas las hojas); después: con el perezoso, que es lo que
    // hace la app (solo se codifican las hojas cargadas y sucias)
    if (skipFull) {
      s = Storage(root: root);
      await s.init();
      final idx = await s.loadIndex();
      doc = await s.openNotebook(idx.notebooks.first, around: n ~/ 2);
      say('guardar y PDF: con el documento perezoso (hojas cargadas: ${doc.loadedSheets.length}), no con el cuaderno entero');
    }
    final d = doc!;
    final k = n ~/ 2;
    Stroke newStroke(int i) {
      final y = k * kSheetStep + 300 + i * 40;
      final pts = <double>[for (var j = 0; j < 40; j++) ...[200 + j * 8.0, y + sin(j / 4) * 6, .6]];
      return Stroke(newId('s'), 'pen', '#22211e', 2.2, pts)..z = d.nextZ();
    }

    final saves = <double>[], splits = <double>[];
    var saveStall = 0.0;
    for (var i = 0; i < 3; i++) {
      final st = newStroke(i);
      d.strokes[st.id] = st;
      final revs = [for (final m in d.sheets) m.rev];
      if (!skipFull) {
        sw = Stopwatch()..start();
        d.splitBySheet(); // necesita todas las hojas cargadas
        splits.add(ms(sw.elapsed));
      }
      sw = Stopwatch()..start();
      final (_, stl) = await withStall(() => s.saveNotebook(d));
      saves.add(ms(sw.elapsed));
      saveStall = max(saveStall, stl);
      final tocadas = [for (var j = 0; j < d.sheets.length; j++) d.sheets[j].rev != revs[j]].where((x) => x).length;
      out['guardar_hojas_escritas'] = tocadas;
    }
    sw = Stopwatch()..start();
    await s.saveNotebook(d);
    final noChange = ms(sw.elapsed);
    out['guardar_1_trazo_ms'] = r1(median(saves));
    out['guardar_corridas_ms'] = [for (final v in saves) r1(v)];
    out['guardar_split_ms'] = splits.isEmpty ? null : r1(median(splits));
    out['guardar_sin_cambios_ms'] = r1(noChange);
    out['guardar_bloqueo_ms'] = r1(saveStall);
    say('guardar tras 1 trazo${skipFull ? ' (documento perezoso)' : ''}: mediana ${out['guardar_1_trazo_ms']} ms '
        '(corridas ${out['guardar_corridas_ms']}; splitBySheet ${out['guardar_split_ms'] ?? '-'} ms; '
        'hojas escritas ${out['guardar_hojas_escritas']}), sin cambios ${r1(noChange)} ms, bloqueo máx ${r1(saveStall)} ms');

    // ---------- (e) exportar a PDF ----------
    if (n == _pdfSheets) {
      final store = s;
      sw = Stopwatch()..start();
      await buildNotebookPdf(store, d, only: [0, 1, 2]);
      final per = ms(sw.elapsed) / 3;
      final est = per * n / 1000;
      out['pdf_ms_por_hoja_estimado'] = r1(per);
      if (est > 120) {
        out['pdf'] = 'salteado: estimado ${r1(est)} s (> 2 min)';
        say('PDF de $n hojas: SALTEADO, estimado ${r1(est)} s (> 2 min)');
      } else {
        sw = Stopwatch()..start();
        try {
          final pdf = await buildNotebookPdf(store, d).timeout(const Duration(seconds: 150));
          out['pdf_ms'] = r1(ms(sw.elapsed));
          out['pdf_mb'] = mb(pdf.length);
          out['rss_tras_pdf_mb'] = mb(ProcessInfo.currentRss);
          say('PDF de $n hojas: ${r1(ms(sw.elapsed) / 1000)} s (estimado ${r1(est)} s), ${mb(pdf.length)} MB, '
              'RSS después ${out['rss_tras_pdf_mb']} MB');
        } on TimeoutException {
          out['pdf'] = 'cortado a los 150 s';
          say('PDF de $n hojas: pasó de 150 s, abandonado');
        }
      }
    } else if (n > _pdfSheets) {
      say('PDF: solo se prueba con $_pdfSheets hojas');
    }
  }

  /// Abre el cuaderno "Perf [n]" por la UI (biblioteca, toque, PageEditor) y mide. Devuelve con el editor abierto.
  Future<void> openByUi(WidgetTester t, int n, Directory root, Map<String, Object?> out) async {
    await t.pumpWidget(ApuntesApp(root: root));
    await settle(t, 2000); // biblioteca y miniaturas
    out['rss_antes_abrir_mb'] = mb(ProcessInfo.currentRss); // justo antes de abrir: ya sin documentos de los pasos
    await frames.mark();
    final sw = Stopwatch()..start();
    await t.tap(find.byKey(Key('nb-Perf $n')));
    while (find.byType(PageEditor).evaluate().isEmpty) {
      await t.pump(const Duration(milliseconds: 16));
      if (sw.elapsed > const Duration(minutes: 3)) fail('el cuaderno no abrió en 3 min');
    }
    await t.pump();
    out['abrir_ui_ms'] = r1(ms(sw.elapsed));
    await settle(t, 1500);
    out['abrir_ui_frames'] = await frames.take();
    final open = out['abrir_ui_frames']! as Map;
    out['rss_abierto_mb'] = mb(ProcessInfo.currentRss);
    out['rss_max_mb'] = mb(ProcessInfo.maxRss);
    say('abrir por la UI: ${out['abrir_ui_ms']} ms hasta el PageEditor; en esa ventana ${open['frames']} frames, '
        'peor ${open['total_peor_ms']} ms, ${open['frames_mas_16ms']} > 16 ms');
    say('RSS: antes de abrir ${out['rss_antes_abrir_mb']} MB, abierto ${out['rss_abierto_mb']} MB, '
        'maxRSS ${out['rss_max_mb']} MB');
  }

  for (final n in sizes) {
    testWidgets('perf: cuaderno de $n hojas', timeout: const Timeout(Duration(minutes: 40)), (t) async {
      final out = <String, Object?>{};
      results['$n'] = out;
      final root = await Directory.systemTemp.createTemp('apuntes_perf$n');
      try {
        await generate(n, root, out);
        await storageSteps(n, root, out);
        out['rss_tras_pasos_mb'] = mb(ProcessInfo.currentRss);
        await Future<void>.delayed(const Duration(seconds: 1)); // sin referencias vivas: que el GC pueda soltar lo suyo

        // ---------- (a bis) abrir por la UI ----------
        await openByUi(t, n, root, out);

        // ---------- (c) scroll con el dedo ----------
        final ed = t.state<PageEditorState>(find.byType(PageEditor));
        final scroll = ed.scroll;
        say('alto del cuaderno: ${r1(scroll.position.maxScrollExtent)} px, escala ${r1(ed.scale)} px/unidad');
        var sw = Stopwatch();

        Future<void> flings(String zone, Offset dir, int count) async {
          await frames.mark();
          final p0 = scroll.offset;
          sw = Stopwatch()..start();
          for (var i = 0; i < count; i++) {
            await t.fling(find.byType(PageEditor), dir, 6000);
            var last = -1.0, still = 0;
            final until = sw.elapsed + const Duration(seconds: 5);
            while (still < 3 && sw.elapsed < until) {
              await t.pump(const Duration(milliseconds: 16));
              still = (scroll.offset - last).abs() < .5 ? still + 1 : 0;
              last = scroll.offset;
            }
          }
          final took = ms(sw.elapsed);
          final f = await frames.take();
          f['recorrido_px'] = r1((scroll.offset - p0).abs()); // neto; el total (sumando |delta| por cuadro) va en recorrido_total_px
          f['duracion_ms'] = r1(took);
          out['scroll_$zone'] = f;
          say('scroll $zone: ${f['frames']} frames, ${f['recorrido_px']} px en ${r1(took / 1000)} s | '
              'build prom/p90/p99 ${f['build_prom_ms']}/${f['build_p90_ms']}/${f['build_p99_ms']} ms | '
              'raster prom/p90/p99 ${f['raster_prom_ms']}/${f['raster_p90_ms']}/${f['raster_p99_ms']} ms | '
              '>16 ms: ${f['frames_mas_16ms']} (>33 ms: ${f['frames_mas_33ms']}), peor ${f['total_peor_ms']} ms | '
              'recorrido total ${f['recorrido_total_px']} px | ${groups(f)}');
        }

        final max0 = scroll.position.maxScrollExtent;
        await flings('inicio', const Offset(0, -500), 6); // dedo hacia arriba: el contenido avanza
        scroll.jumpTo(max0 / 2);
        await settle(t, 600);
        await flings('medio', const Offset(0, -500), 6);
        scroll.jumpTo(max0 - 9000);
        await settle(t, 600);
        await flings('final', const Offset(0, 500), 6); // hacia atrás: no choca con "tirar para agregar hoja"
        out['rss_tras_scroll_mb'] = mb(ProcessInfo.currentRss);
        out['rss_max_mb'] = mb(ProcessInfo.maxRss);
        say('RSS tras scrollear ${out['rss_tras_scroll_mb']} MB, maxRSS ${out['rss_max_mb']} MB');
        final ic = ed.imageCache;
        out['cache_imagenes'] = {'tandas': ic.imageCount, 'franjas': ic.stripsReady, 'mb': mb(ic.bytes)};
        say('caché de imágenes: ${ic.imageCount} tandas / ${ic.stripsReady} franjas (${mb(ic.bytes)} MB)');

        // salir: que no quede nada guardándose antes de borrar la carpeta
        await t.tap(find.byKey(const Key('back')));
        await settle(t, 1500);
      } catch (e) {
        out['error'] = '$e';
        say('ERROR en $n hojas: $e');
        rethrow;
      } finally {
        publish();
        await t.pumpWidget(const SizedBox());
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  }

  // ---------- caso aparte: traza de la línea de tiempo (tool/traza.sh) ----------
  if (trace != null) {
    testWidgets('perf: traza de scroll medio ($trace hojas)', timeout: const Timeout(Duration(minutes: 20)), (t) async {
      final out = <String, Object?>{};
      results['traza'] = out;
      final root = await Directory.systemTemp.createTemp('apuntes_perf_trace');
      try {
        await generate(trace, root, out);
        await openByUi(t, trace, root, out);
        final ed = t.state<PageEditorState>(find.byType(PageEditor));
        final scroll = ed.scroll;
        scroll.jumpTo(scroll.position.maxScrollExtent / 2);
        await settle(t, 600);
        await frames.mark();
        final sw = Stopwatch()..start();
        // mismo scroll que 'medio' del caso normal; la traza lleva los eventos 'ON ...' de la app
        await binding.traceAction(() async {
          for (var i = 0; i < 6; i++) {
            await t.fling(find.byType(PageEditor), const Offset(0, -500), 6000);
            var last = -1.0, still = 0;
            final until = sw.elapsed + const Duration(seconds: 5);
            while (still < 3 && sw.elapsed < until) {
              await t.pump(const Duration(milliseconds: 16));
              still = (scroll.offset - last).abs() < .5 ? still + 1 : 0;
              last = scroll.offset;
            }
          }
        }, reportKey: 'timeline', streams: const ['Dart', 'Embedder', 'GC']);
        results['timeline'] = binding.reportData?['timeline']; // publish() reemplaza reportData: se guarda acá
        final f = await frames.take();
        out['scroll_medio_traza'] = f;
        say('traza scroll medio ($trace hojas): ${f['frames']} frames, build p90/p99 ${f['build_p90_ms']}/${f['build_p99_ms']} ms, '
            'raster p90/p99 ${f['raster_p90_ms']}/${f['raster_p99_ms']} ms, >16 ms: ${f['frames_mas_16ms']}, peor ${f['total_peor_ms']} ms');
        await t.tap(find.byKey(const Key('back')));
        await settle(t, 1500);
      } catch (e) {
        out['error'] = '$e';
        say('ERROR en traza: $e');
        rethrow;
      } finally {
        publish();
        await t.pumpWidget(const SizedBox());
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  }

  // ---------- caso aparte: comparación con Samsung Notes (tool/comparar.sh) ----------
  if (compare != null) {
    testWidgets('perf: comparación con Samsung Notes ($compare hojas, horizontal)',
        timeout: const Timeout(Duration(minutes: 20)), (t) async {
      final out = <String, Object?>{};
      results['comparar'] = out;
      final root = await Directory.systemTemp.createTemp('apuntes_perf_cmp');
      try {
        await generate(compare, root, out);
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        await Future<void>.delayed(const Duration(seconds: 2)); // que el sistema termine de girar
        await openByUi(t, compare, root, out);

        // ventana de medición: el test NO scrollea; solo mira los frames mientras tool/comparar.sh hace swipes con adb
        final ed = t.state<PageEditorState>(find.byType(PageEditor));
        final p0 = ed.scroll.offset;
        await frames.mark();
        final sw = Stopwatch()..start();
        // el binding de test descarta los toques reales y no dibuja frames por su cuenta: durante la ventana
        // se dejan pasar los toques de adb y los frames los pide la app como en uso normal
        final lb = t.binding as LiveTestWidgetsFlutterBinding;
        final policy = lb.framePolicy;
        lb.shouldPropagateDevicePointerEvents = true;
        lb.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
        say('LISTO_PARA_SWIPES');
        try {
          while (sw.elapsed < const Duration(seconds: _compareWindowSeconds)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        } finally {
          lb.shouldPropagateDevicePointerEvents = false;
          lb.framePolicy = policy;
        }
        // solo los cuadros mientras el scroll se movía (ver FrameRecorder.take); los de afuera de esa ventana no cuentan
        final f = await frames.take(onlyMoving: true);
        f['recorrido_px'] = r1((ed.scroll.offset - p0).abs()); // neto
        f['ventana_s'] = _compareWindowSeconds;
        out['swipes'] = f;
        out['rss_tras_swipes_mb'] = mb(ProcessInfo.currentRss);
        out['rss_max_mb'] = mb(ProcessInfo.maxRss);
        say('swipes ($compare hojas, horizontal, ventana de $_compareWindowSeconds s, activa ${f['ventana_activa_ms']} ms): '
            '${f['frames']} frames en movimiento, ${f['recorrido_total_px']} px recorridos (neto ${f['recorrido_px']}) | '
            'build prom/p50/p90/p99 ${f['build_prom_ms']}/${f['build_p50_ms']}/${f['build_p90_ms']}/${f['build_p99_ms']} ms | '
            'raster prom/p50/p90/p99 ${f['raster_prom_ms']}/${f['raster_p50_ms']}/${f['raster_p90_ms']}/${f['raster_p99_ms']} ms | '
            '>16 ms: ${f['frames_mas_16ms']} (${f['frames_mas_16ms_pct']} %), peor ${f['total_peor_ms']} ms');
        say('swipes, por grupo: ${groups(f)}');
        say('RSS tras swipes ${out['rss_tras_swipes_mb']} MB, maxRSS ${out['rss_max_mb']} MB');

        await t.tap(find.byKey(const Key('back')));
        await settle(t, 1500);
      } catch (e) {
        out['error'] = '$e';
        say('ERROR en comparación: $e');
        rethrow;
      } finally {
        await SystemChrome.setPreferredOrientations([]);
        publish();
        await t.pumpWidget(const SizedBox());
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  }
}
