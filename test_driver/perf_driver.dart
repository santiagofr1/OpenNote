// Driver del benchmark (tool/perf.sh): guarda en build/perf/perf.json lo que el test deja en binding.reportData
// y repite la tabla en la consola (líneas "PERF ..."). Aparte de integration_test.dart, que es el de las capturas.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(hours: 2),
      writeResponseOnFailure: true, // si un tamaño falla, igual quedan los resultados de los otros
      responseDataCallback: (data) async {
        await writeResponseData(data, testOutputFilename: 'perf', destinationDirectory: 'build/perf');
        for (final l in (data?['tabla'] as List? ?? const [])) {
          // ignore: avoid_print
          print('PERF $l');
        }
      },
    );
