import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as ml;

import '../domain/domain.dart';

/// Lee a mano alzada (trazos -> texto). Solo hay en Android; en el resto, quien llama pide escribir el nombre.
abstract class HandwritingRecognizer {
  /// Si el modelo del idioma ya está bajado (la primera vez hay que bajarlo).
  Future<bool> isModelReady();

  /// Se asegura de tener el modelo (lo baja si falta). De vuelo único: si ya hay una bajada en curso, espera esa misma.
  /// Devuelve false si no se pudo.
  Future<bool> ensureModel();

  /// El texto que se leyó de [strokes], o null si no se pudo (baja el modelo si falta).
  Future<String?> recognize(List<Stroke> strokes);
}

/// Ejecuta [run] de a una: mientras haya una corriendo, quien llame de nuevo recibe la misma. Al terminar (bien o mal)
/// se libera y la próxima llamada arranca de cero (así un fallo se puede reintentar).
class SingleFlight<T> {
  Future<T>? _current;

  /// Hay una en curso.
  bool get running => _current != null;

  Future<T> run(Future<T> Function() task) {
    final cur = _current;
    if (cur != null) return cur;
    late final Future<T> f;
    f = task().whenComplete(() {
      if (identical(_current, f)) _current = null;
    });
    _current = f;
    return f;
  }
}

/// Reconocimiento de letra de ML Kit (en el dispositivo, español).
class MlKitHandwriting implements HandwritingRecognizer {
  static const _lang = 'es-AR'; // ver los modelos en developers.google.com/ml-kit/vision/digital-ink-recognition/base-models
  static const _timeout = Duration(seconds: 25);
  final _models = ml.DigitalInkRecognizerModelManager();
  final _download = SingleFlight<bool>();

  @override
  Future<bool> isModelReady() async {
    try {
      return await _models.isModelDownloaded(_lang);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ensureModel() => _download.run(() async {
        try {
          if (await _models.isModelDownloaded(_lang)) return true;
          final ok = await _models.downloadModel(_lang, isWifiRequired: false);
          if (!ok) debugPrint('OpenNote letra: no se pudo bajar el modelo $_lang');
          return ok;
        } catch (e) {
          debugPrint('OpenNote letra: error al bajar el modelo $e');
          return false;
        }
      });

  /// Tope para leer (con la bajada del modelo incluida); si vence, devuelve null y la bajada sigue en segundo plano.
  @override
  Future<String?> recognize(List<Stroke> strokes) => _read(strokes).timeout(_timeout, onTimeout: () {
        debugPrint('OpenNote letra: venció el tiempo (${_timeout.inSeconds} s) leyendo; la bajada sigue en segundo plano');
        return null;
      });

  Future<String?> _read(List<Stroke> strokes) async {
    ml.DigitalInkRecognizer? rec;
    try {
      if (!await ensureModel()) return null;
      // en el orden en que se escribieron, con tiempos inventados: 10 ms entre puntos y 300 ms entre trazos
      final ordered = List.of(strokes)..sort((a, b) => a.z.compareTo(b.z));
      final ink = ml.Ink();
      var t = 0;
      for (final s in ordered) {
        final st = ml.Stroke();
        for (var i = 0; i + 1 < s.pts.length; i += 3) {
          st.points.add(ml.StrokePoint(x: s.pts[i], y: s.pts[i + 1], t: t));
          t += 10;
        }
        t += 300;
        ink.strokes.add(st);
      }
      rec = ml.DigitalInkRecognizer(languageCode: _lang);
      final out = await rec.recognize(ink);
      final text = out.isEmpty ? '' : out.first.text.trim();
      if (text.isEmpty) debugPrint('OpenNote letra: sin candidatos (${ink.strokes.length} trazos)');
      return text.isEmpty ? null : text;
    } catch (e, st) {
      debugPrint('OpenNote letra: error $e\n$st');
      return null;
    } finally {
      try {
        await rec?.close();
      } catch (_) {}
    }
  }
}

/// El reconocedor que se usa (null donde no hay). Los tests lo reemplazan.
HandwritingRecognizer? handwriting = Platform.isAndroid ? MlKitHandwriting() : null;
