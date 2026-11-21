// Driver del benchmark (tool/perf.sh): guarda en build/perf/perf.json lo que el test deja en binding.reportData
// y repite la tabla en la consola (líneas "PERF ..."). Aparte de integration_test.dart, que es el de las capturas.
// Modo traza (tool/traza.sh): si viene 'timeline', además de perf.json (sin la traza) deja en build/perf/
// traza.timeline.json (traza cruda, formato Chrome trace) y traza.timeline_summary.json (TimelineSummary).
import 'package:flutter_driver/flutter_driver.dart' show TimelineSummary;
import 'package:flutter_driver/flutter_driver.dart' as driver show Timeline;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(hours: 2),
      writeResponseOnFailure: true, // si un tamaño falla, igual quedan los resultados de los otros
      responseDataCallback: (data) async {
        final timeline = data?['timeline'];
        if (data != null && timeline is Map<String, dynamic>) {
          final rest = Map<String, dynamic>.of(data)..remove('timeline'); // la traza es enorme: va en su propio archivo
          await writeResponseData(rest, testOutputFilename: 'perf', destinationDirectory: 'build/perf');
          final summary = TimelineSummary.summarize(driver.Timeline.fromJson(timeline));
          await summary.writeTimelineToFile('traza', destinationDirectory: 'build/perf', pretty: false, includeSummary: true);
        } else {
          await writeResponseData(data, testOutputFilename: 'perf', destinationDirectory: 'build/perf');
        }
        for (final l in (data?['tabla'] as List? ?? const [])) {
          // ignore: avoid_print
          print('PERF $l');
        }
      },
    );
