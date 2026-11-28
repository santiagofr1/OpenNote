// Driver de tool/perf_lienzo.sh: guarda en build/perf/canvas.json lo que el test deja en binding.reportData y repite
// las líneas "PERF ..." en la consola (mismo mecanismo que perf_driver.dart).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(hours: 1),
      writeResponseOnFailure: true, // si una fase falla, igual quedan los resultados de las otras
      responseDataCallback: (data) async {
        final tl = data?['pinch_timeline']; // timeline del pellizco (Chrome trace): aparte, es enorme
        if (tl != null) {
          await writeResponseData({'pinch_timeline': tl}, testOutputFilename: 'pinch_timeline', destinationDirectory: 'build/perf');
          data = Map<String, dynamic>.of(data!)..remove('pinch_timeline');
        }
        await writeResponseData(data, testOutputFilename: 'canvas', destinationDirectory: 'build/perf');
        for (final l in (data?['tabla'] as List? ?? const [])) {
          // ignore: avoid_print
          print('PERF $l');
        }
      },
    );
