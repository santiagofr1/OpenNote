import 'dart:async';
import 'dart:io';

import 'voice_recorder.dart';

/// Micrófono falso para los tests (y para probar la pantalla sin micrófono): escribe unos bytes en el archivo que le piden,
/// como lo haría el de verdad. Se instala con `VoiceRecorder.sourceFactory = () => FakeAudioSource();`.
class FakeAudioSource implements AudioSource {
  FakeAudioSource({this.permission = true, this.failStart = false, this.bytes = 2048});
  final bool permission, failStart;
  final int bytes;
  String? path;
  bool stopped = false, disposed = false;
  final level = StreamController<double>.broadcast();
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> start(String path) async {
    if (failStart) throw StateError('micrófono ocupado');
    this.path = path;
    await File(path).writeAsBytes(List.filled(bytes, 5));
  }

  @override
  Future<void> stop() async => stopped = true;
  @override
  Stream<double> levels() => level.stream;
  @override
  Future<void> dispose() async => disposed = true;
}
