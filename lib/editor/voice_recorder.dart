import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../data/storage.dart';

/// Lo que el [VoiceRecorder] necesita de un micrófono. Es una interfaz para que los tests pongan uno falso
/// (ver [VoiceRecorder.sourceFactory]): el micrófono de verdad no se puede usar en un test.
abstract class AudioSource {
  /// Si hay permiso para grabar (lo pide si falta).
  Future<bool> hasPermission();

  /// Empieza a grabar en el archivo [path].
  Future<void> start(String path);

  /// Termina: el archivo de [start] queda completo.
  Future<void> stop();

  /// Nivel de entrada de 0 a 1.
  Stream<double> levels();
  Future<void> dispose();
}

/// El micrófono de verdad: el paquete `record`, AAC en `.m4a`.
class RecordAudioSource implements AudioSource {
  final _rec = AudioRecorder();
  @override
  Future<bool> hasPermission() => _rec.hasPermission();
  @override
  Future<void> start(String path) => _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
  @override
  Future<void> stop() => _rec.stop();
  @override
  Stream<double> levels() =>
      _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).map((a) => ((a.current + 50) / 50).clamp(0.0, 1.0));
  @override
  Future<void> dispose() => _rec.dispose();
}

enum VoiceError { busy, noPermission, failed }

/// No se pudo empezar a grabar; [message] se le puede mostrar al usuario.
class VoiceException implements Exception {
  final String message;

  /// Qué pasó (para mostrarlo en el idioma de la app) y el detalle técnico, si hay.
  final VoiceError kind;
  final String? detail;
  const VoiceException(this.message, {this.kind = VoiceError.failed, this.detail});
  @override
  String toString() => message;
}

/// Una grabación terminada: el audio ya está en media/[file].
typedef VoiceResult = ({String itemId, String file, int ms});

/// Grabación de voz en curso, fuera de cualquier diálogo: vive en el cuaderno abierto (`NotebookScreenState`), así se
/// puede seguir escribiendo mientras graba. Una sola a la vez. Envuelve el micrófono ([AudioSource]), el cronómetro y el nivel.
///
/// Graba a `media/<file>.tmp` (la sincronización ignora los `.tmp`, ver sync_paths.dart) y al parar lo renombra a
/// `media/<file>`: nunca hay un audio a medias con su nombre final. Avisa (ChangeNotifier) unas 4 veces por segundo mientras
/// graba, para el cronómetro de la etiqueta.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder(this.store);
  final Storage store;

  /// Cómo se arma el micrófono. Variable para que los tests lo reemplacen.
  static AudioSource Function() sourceFactory = RecordAudioSource.new;

  AudioSource? _src;
  String? _itemId, _file;
  bool _starting = false, _disposed = false;
  final _sw = Stopwatch();
  Timer? _tick;
  StreamSubscription<double>? _sub;

  /// Nivel de entrada actual (0 a 1).
  double level = 0;

  /// El elemento de la grabación ya está puesto en la hoja (antes de eso no se lo puede confundir con uno borrado).
  bool inserted = false;

  /// Hay una grabación en curso.
  bool get recording => _itemId != null;

  /// Ya graba o está arrancando: no se puede empezar otra.
  bool get busy => _starting || recording;
  String? get itemId => _itemId;
  bool isRecording(String itemId) => _itemId == itemId;
  int get elapsedMs => _sw.elapsedMilliseconds;

  /// Empieza a grabar el audio de [itemId] en `media/[file]` (con `.tmp` hasta parar). [VoiceException] si ya hay una grabación
  /// o no se puede (sin permiso del micrófono, etc.): en ese caso no queda nada en disco.
  Future<void> start(String itemId, String file) async {
    if (busy) throw const VoiceException('Ya hay una grabación en curso', kind: VoiceError.busy);
    _starting = true;
    final src = sourceFactory();
    try {
      if (!await src.hasPermission()) throw const VoiceException('Sin permiso para usar el micrófono', kind: VoiceError.noPermission);
      await store.media('$file.tmp').parent.create(recursive: true);
      await src.start(store.media('$file.tmp').path);
    } on VoiceException {
      await _quiet(src.dispose);
      rethrow;
    } catch (e) {
      await _quiet(src.dispose);
      throw VoiceException('No se pudo grabar: $e', kind: VoiceError.failed, detail: '$e');
    } finally {
      _starting = false;
    }
    _src = src;
    _itemId = itemId;
    _file = file;
    inserted = false;
    level = 0;
    _sw
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _notify());
    _sub = src.levels().listen((l) => level = l, onError: (_) {});
    _notify();
  }

  /// Para y deja el audio en `media/<file>`. null si no había nada grabando o no quedó archivo.
  Future<VoiceResult?> stop() async {
    final (id, file, ms) = await _halt();
    if (id == null || file == null) return null;
    final tmp = store.media('$file.tmp');
    try {
      if (!await tmp.exists() || await tmp.length() == 0) {
        await _quiet(tmp.delete);
        return null;
      }
      await tmp.rename(store.media(file).path);
    } catch (_) {
      return null;
    }
    return (itemId: id, file: file, ms: ms);
  }

  /// Para y tira lo grabado (se borró o se deshizo el elemento, o se está borrando el cuaderno).
  Future<void> discard() async {
    final (id, file, _) = await _halt();
    if (id == null || file == null) return;
    await _quiet(store.media('$file.tmp').delete);
  }

  /// Corta todo y limpia el estado ANTES de esperar al micrófono (otra llamada ya no ve una grabación en curso).
  Future<(String?, String?, int)> _halt() async {
    final id = _itemId, file = _file, src = _src;
    final ms = _sw.elapsedMilliseconds;
    _itemId = _file = null;
    _src = null;
    _sw.stop();
    _tick?.cancel();
    _tick = null;
    final sub = _sub;
    _sub = null;
    level = 0;
    _notify();
    await _quiet(() async => sub?.cancel());
    if (src != null) {
      await _quiet(src.stop);
      await _quiet(src.dispose);
    }
    return (id, file, ms);
  }

  Future<void> _quiet(FutureOr<Object?> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _sub?.cancel();
    final src = _src;
    _src = null;
    _itemId = _file = null;
    if (src != null) {
      // nadie esperó: se corta lo que se pueda (el .tmp queda; la sincronización lo ignora)
      unawaited(_quiet(src.stop).then((_) => _quiet(src.dispose)));
    }
    super.dispose();
  }
}

/// Borra [f] sin quejarse si no está.
Future<void> deleteQuietly(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
