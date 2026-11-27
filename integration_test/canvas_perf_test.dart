// Benchmark del lienzo infinito ancho en la tablet (NO es parte de app_test.dart): paneo con un dedo, pellizco con dos
// dedos y escritura con lápiz sobre un lienzo de ~28 anchos de hoja con ~8.000 trazos. Todo con gestos reales
// (TestGesture) sobre la UI real y FrameTiming por fase. Datos en una carpeta temporal propia: nunca toca tus cuadernos.
//
// Se corre con tool/perf_lienzo.sh (build profile + `flutter drive`; deja build/perf/canvas.json y build/perf/lienzo.log).
// Tamaño al compilar: --dart-define=CANVAS_STROKES=8000 (por defecto 8000).
// Dedo (touch) = scrollea y pellizca; lápiz (stylus) = escribe (ver PageEditor._touchDown / _down).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _strokesEnv = String.fromEnvironment('CANVAS_STROKES', defaultValue: '8000');
const _screens = 28; // ancho del contenido, en anchos de hoja (kW)
const _sheetsTall = 3; // alto: 3 hojas de alto
const _name = 'Lienzo perf';

// ---------------------------------------------------------------- generación (en otro isolate)
/// Escribe en [root] un cuaderno-lienzo con [target] trazos tipo escritura a mano: bloques de palabras (3-6 trazos
/// ondulados de 20-60 puntos con presión) repartidos en una grilla de [_screens] x [_sheetsTall] celdas.
/// Devuelve (puntos, trazos, ancho del lienzo).
Future<(int, int, double)> generateCanvas(Directory root, int target) {
  final path = root.path;
  return Isolate.run(() => _generate(path, target));
}

Future<(int, int, double)> _generate(String path, int target) async {
  final s = Storage(root: Directory(path));
  await s.init();
  final canvasW = grownCanvasW(2000, _screens * kW);
  final nb = Notebook(newId('n'), _name, canvas: true, canvasW: canvasW, bg: 'blank');
  for (var k = 0; k < _sheetsTall; k++) {
    nb.sheets.add(nb.newSheet());
  }
  final contents = [for (var k = 0; k < _sheetsTall; k++) SheetContent()];
  final r = Random(7);
  final cells = _screens * _sheetsTall;
  var strokes = 0, points = 0, cell = 0;
  // palabras por celda: las justas para llegar a [target] trazos (una palabra rinde ~4,5 trazos)
  final wordsPerCell = (target / 4.5 / cells).ceil() + 1;
  outer:
  while (true) {
    final cx = cell % _screens, sh = (cell ~/ _screens) % _sheetsTall;
    final x0 = cx * kW + 60.0, y0 = 90.0; // coordenadas locales de la hoja sh
    var x = x0, y = y0;
    for (var w = 0; w < wordsPerCell; w++) {
      final ww = 55 + r.nextDouble() * 60;
      if (x + ww > x0 + kW - 120) {
        x = x0;
        y += 38.1;
        if (y > kSheetH - 80) y = y0 + (w % 3) * 2; // celda llena: se sobreescribe (no pasa con tamaños razonables)
      }
      final ns = 3 + r.nextInt(4);
      for (var i = 0; i < ns; i++) {
        final n = 20 + r.nextInt(41);
        final sx = x + ww * i / ns, len = ww / ns + 10 + r.nextDouble() * 14;
        final ph = r.nextDouble() * 6.28, amp = 4 + r.nextDouble() * 7, fr = 1.5 + r.nextDouble() * 2;
        final pts = <double>[];
        for (var j = 0; j < n; j++) {
          final u = j / (n - 1);
          final p = (.35 + .4 * sin(pi * u) + (r.nextDouble() - .5) * .08).clamp(.2, 1.0);
          pts.addAll([sx + len * u + 3 * sin(u * 9 + ph), y + amp * sin(u * fr * 6.28 + ph), p]);
        }
        contents[sh].strokes.add(Stroke(newId('s'), 'pen', '#22211e', 2.2, pts));
        strokes++;
        points += n;
        if (strokes >= target) break outer;
      }
      x += ww + 14;
    }
    cell++;
  }
  for (var k = 0; k < _sheetsTall; k++) {
    final f = s.sheetFile(nb.id, nb.sheets[k].id);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(encodeSheet(contents[k]), flush: true);
  }
  await File('${s.nbDir(nb.id).path}/notebook.json').writeAsString(jsonEncode(nb.sheetsJson()), flush: true);
  await s.saveIndex(NotesIndex(last: nb.id, notebooks: [nb]));
  return (points, strokes, canvasW);
}

// ---------------------------------------------------------------- medición
double ms(Duration d) => d.inMicroseconds / 1000;
double r1(num v) => (v * 10).round() / 10;
double pct(List<double> sorted, double p) => sorted.isEmpty ? 0 : sorted[(p * (sorted.length - 1)).round()];
double avg(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
String modo() => kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

class FrameRecorder {
  final _all = <FrameTiming>[];
  void _cb(List<FrameTiming> l) => _all.addAll(l);
  void attach() => SchedulerBinding.instance.addTimingsCallback(_cb);
  void detach() => SchedulerBinding.instance.removeTimingsCallback(_cb);

  /// Descarta lo anterior (después de dejar que lleguen las tandas pendientes, que llegan hasta ~1 s tarde).
  Future<void> mark() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    _all.clear();
  }

  Future<Map<String, Object>> take() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final fr = List.of(_all);
    _all.clear();
    final build = [for (final f in fr) ms(f.buildDuration)]..sort();
    final raster = [for (final f in fr) ms(f.rasterDuration)]..sort();
    final total = [for (final f in fr) ms(f.totalSpan)]..sort();
    final slowBR = fr.where((f) => ms(f.buildDuration) > 16.7 || ms(f.rasterDuration) > 16.7).length;
    double p(int n) => fr.isEmpty ? 0.0 : r1(100 * n / fr.length);
    return {
      'frames': fr.length,
      'build_avg_ms': r1(avg(build)),
      'build_p50_ms': r1(pct(build, .5)),
      'build_p90_ms': r1(pct(build, .9)),
      'build_p99_ms': r1(pct(build, .99)),
      'build_max_ms': r1(build.isEmpty ? 0 : build.last),
      'raster_avg_ms': r1(avg(raster)),
      'raster_p50_ms': r1(pct(raster, .5)),
      'raster_p90_ms': r1(pct(raster, .9)),
      'raster_p99_ms': r1(pct(raster, .99)),
      'raster_max_ms': r1(raster.isEmpty ? 0 : raster.last),
      'total_p90_ms': r1(pct(total, .9)),
      'total_max_ms': r1(total.isEmpty ? 0 : total.last),
      'lentos_build_o_raster_pct': p(slowBR),
      'lentos_total_pct': p(total.where((t) => t > 16.7).length),
      'lentos_total_33ms': total.where((t) => t > 33.4).length,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final target = int.parse(_strokesEnv.trim());
  final results = <String, Object>{'modo': modo(), 'trazos_pedidos': target};
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

  Future<void> settle(WidgetTester t, [int msec = 400]) async {
    for (var i = 0; i < msec ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  setUpAll(frames.attach);
  tearDownAll(() {
    frames.detach();
    publish();
  });

  testWidgets('perf: lienzo infinito ancho', timeout: const Timeout(Duration(minutes: 30)), (t) async {
    final root = await Directory.systemTemp.createTemp('apuntes_perf_lienzo');
    try {
      final sw0 = Stopwatch()..start();
      final (points, strokes, canvasW) = await generateCanvas(root, target);
      results['puntos'] = points;
      results['trazos'] = strokes;
      results['canvasW'] = canvasW;
      results['anchos_de_hoja'] = r1(canvasW / kW);
      say(jsonEncode({
        'phase': 'datos',
        'trazos': strokes,
        'puntos': points,
        'canvasW': canvasW,
        'anchos_de_hoja': r1(canvasW / kW),
        'hojas_de_alto': _sheetsTall,
        'generar_s': r1(ms(sw0.elapsed) / 1000),
        'modo': modo(),
      }));
      await Future<void>.delayed(const Duration(seconds: 1));

      // ---------- abrir por la UI ----------
      await t.pumpWidget(ApuntesApp(root: root));
      await settle(t, 2000);
      await frames.mark();
      final sw = Stopwatch()..start();
      await t.tap(find.byKey(const Key('nb-Lienzo perf')));
      while (find.byType(PageEditor).evaluate().isEmpty) {
        await t.pump(const Duration(milliseconds: 16));
        if (sw.elapsed > const Duration(minutes: 3)) fail('el lienzo no abrió en 3 min');
      }
      final openMs = ms(sw.elapsed);
      await t.pump();
      final ed = t.state<PageEditorState>(find.byType(PageEditor));
      // inactivo: sin tareas de imágenes pendientes durante 10 cuadros seguidos
      var quiet = 0;
      while (quiet < 10) {
        await t.pump(const Duration(milliseconds: 50));
        quiet = ed.imageFrameState.jobs == 0 ? quiet + 1 : 0;
        if (sw.elapsed > const Duration(minutes: 3)) break;
      }
      final idleMs = ms(sw.elapsed);
      expect(ed.doc.nb.canvas, isTrue);
      expect(ed.hscroll.position.maxScrollExtent, greaterThan(0));
      Future<void> phase(String name, Map<String, Object> f, [Map<String, Object?> extra = const {}]) async {
        final m = {
          'phase': name,
          ...f,
          ...extra,
          'zoom': r1(ed.ts.zoom * 100) / 100,
          'rss_mb': r1(ProcessInfo.currentRss / 1048576),
        };
        results[name] = m;
        say(jsonEncode(m));
        publish();
      }

      await phase('open', await frames.take(), {'abrir_hasta_editor_ms': r1(openMs), 'abrir_hasta_inactivo_ms': r1(idleMs)});
      say(jsonEncode({
        'phase': 'editor',
        'escala_px_por_unidad': r1(ed.scale * 100) / 100,
        'scroll_x_max': r1(ed.hscroll.position.maxScrollExtent),
        'scroll_y_max': r1(ed.scroll.position.maxScrollExtent),
        'trazos_cargados': ed.doc.strokes.length,
      }));

      final box = t.getRect(find.byType(PageEditor));
      final hs = ed.hscroll, vs = ed.scroll;
      ed.ts.zoomLocked = false;

      // ---------- gestos ----------
      /// Un dedo de [a] a [b] en [steps] cuadros de 16 ms (touch: scrollea), más un rato de inercia.
      Future<void> drag(Offset a, Offset b, {int steps = 24}) async {
        final g = await t.startGesture(a, kind: PointerDeviceKind.touch);
        for (var i = 1; i <= steps; i++) {
          await g.moveTo(Offset.lerp(a, b, i / steps)!);
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 16));
        }
      }

      /// Barre todo el ancho (o alto) del lienzo con arrastres de ~[dist] px hacia el final y vuelve. Devuelve los arrastres.
      Future<int> sweep(ScrollController c, bool horizontal, {int rounds = 1}) async {
        final dist = horizontal ? min(800.0, box.width - 120) : min(800.0, box.height - 260);
        final cx = box.center.dx, cy = box.center.dy;
        var n = 0;
        for (var rd = 0; rd < rounds; rd++) {
          for (final fwd in [true, false]) {
            var last = -1.0, still = 0;
            for (var i = 0; i < 150 && still < 2; i++) {
              final end = fwd ? c.position.maxScrollExtent : 0.0;
              if ((c.offset - end).abs() < 1) break;
              final s = fwd ? 1.0 : -1.0; // avanzar el contenido = el dedo va hacia atrás
              final a = horizontal ? Offset(cx + s * dist / 2, cy) : Offset(cx, cy + s * dist / 2);
              final b = horizontal ? Offset(cx - s * dist / 2, cy) : Offset(cx, cy - s * dist / 2);
              await drag(a, b);
              n++;
              still = (c.offset - last).abs() < .5 ? still + 1 : 0;
              last = c.offset;
            }
          }
        }
        return n;
      }

      /// Pellizco de dos dedos separados [from] -> [to] px alrededor de [c], en [steps] cuadros.
      Future<void> pinch(Offset c, double from, double to, {int steps = 40}) async {
        final a = await t.createGesture(kind: PointerDeviceKind.touch);
        final b = await t.createGesture(kind: PointerDeviceKind.touch);
        await a.down(c - Offset(from / 2, 0));
        await t.pump(const Duration(milliseconds: 30));
        await b.down(c + Offset(from / 2, 0));
        for (var i = 1; i <= steps; i++) {
          final d = from + (to - from) * i / steps;
          await a.moveTo(c - Offset(d / 2, 0));
          await b.moveTo(c + Offset(d / 2, 0));
          await t.pump(const Duration(milliseconds: 16));
        }
        await a.up();
        await b.up();
        await settle(t, 300);
      }

      final wide = min(700.0, box.width * .85);
      final center = Offset(box.center.dx, box.center.dy);

      // 1) paneo horizontal: de punta a punta y vuelta
      hs.jumpTo(0);
      vs.jumpTo(0);
      await settle(t, 600);
      await frames.mark();
      var sw1 = Stopwatch()..start();
      var n = await sweep(hs, true);
      await phase('pan_x', await frames.take(), {'arrastres': n, 'duracion_s': r1(sw1.elapsed.inMilliseconds / 1000)});

      // 2) paneo vertical (2 vueltas)
      vs.jumpTo(0);
      await settle(t, 600);
      await frames.mark();
      sw1 = Stopwatch()..start();
      n = await sweep(vs, false, rounds: 2);
      await phase('pan_y', await frames.take(), {'arrastres': n, 'duracion_s': r1(sw1.elapsed.inMilliseconds / 1000)});

      // 3) pellizco: 5 ciclos (acercar y alejar) en 3 posiciones horizontales
      vs.jumpTo(0);
      final zooms = <double>[];
      await frames.mark();
      sw1 = Stopwatch()..start();
      for (final pos in [0.0, .5, 1.0]) {
        hs.jumpTo(hs.position.maxScrollExtent * pos);
        await settle(t, 600);
        for (var i = 0; i < 5; i++) {
          await pinch(center, 150, wide);
          zooms.add(ed.ts.zoom);
          await pinch(center, wide, 150);
        }
      }
      await phase('pinch_in_out', await frames.take(), {
        'ciclos': 15,
        'zoom_max_alcanzado': r1(zooms.reduce(max) * 100) / 100,
        'duracion_s': r1(sw1.elapsed.inMilliseconds / 1000),
      });

      // 4) alejar al mínimo y panear todo el ancho
      var prev = -1.0, pinches = 0;
      while ((ed.ts.zoom - prev).abs() > .001 && pinches < 8) {
        prev = ed.ts.zoom;
        await pinch(center, wide, 150);
        pinches++;
      }
      say(jsonEncode({'phase': 'zoom_minimo', 'zoom': r1(ed.ts.zoom * 100) / 100, 'pellizcos': pinches}));
      hs.jumpTo(0);
      vs.jumpTo(0);
      await settle(t, 800);
      await frames.mark();
      sw1 = Stopwatch()..start();
      n = await sweep(hs, true);
      await phase('zoomed_out_pan', await frames.take(), {'arrastres': n, 'duracion_s': r1(sw1.elapsed.inMilliseconds / 1000)});

      // 5) escribir con lápiz en el extremo derecho (zoom 1 otra vez)
      await pinch(center, 150, 150 * (1 / ed.ts.zoom)); // de vuelta a zoom ~1
      await settle(t, 400);
      hs.jumpTo(hs.position.maxScrollExtent);
      vs.jumpTo(0);
      await settle(t, 800);
      final before = ed.doc.strokes.length;
      await frames.mark();
      sw1 = Stopwatch()..start();
      for (var i = 0; i < 30; i++) {
        final y = box.top + 160 + (i % 15) * 55.0;
        final x0 = box.right - 330 + (i ~/ 15) * 20.0;
        final g = await t.startGesture(Offset(x0, y), kind: PointerDeviceKind.stylus);
        for (var j = 1; j <= 25; j++) {
          await g.moveTo(Offset(x0 + j * 6, y + sin(j / 3) * 10));
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await t.pump(const Duration(milliseconds: 100));
      }
      await phase('write_far_right', await frames.take(), {
        'trazos_nuevos': ed.doc.strokes.length - before,
        'canvasW_final': ed.doc.nb.canvasW,
        'duracion_s': r1(sw1.elapsed.inMilliseconds / 1000),
      });
      results['rss_max_mb'] = r1(ProcessInfo.maxRss / 1048576);
      say(jsonEncode({'phase': 'rss', 'rss_mb': r1(ProcessInfo.currentRss / 1048576), 'rss_max_mb': results['rss_max_mb']}));

      await t.tap(find.byKey(const Key('back')));
      await settle(t, 2000);
    } catch (e) {
      results['error'] = '$e';
      say(jsonEncode({'phase': 'error', 'error': '$e'}));
      rethrow;
    } finally {
      publish();
      await t.pumpWidget(const SizedBox());
      await Storage.settleWrites();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
