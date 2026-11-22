import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/editor/fake_audio_source.dart';
import 'package:apuntes/editor/voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grabación de voz sin el micrófono: nombres (`.tmp` hasta parar), una sola a la vez, permisos y descartar.
void main() {
  late Directory root;
  late Storage store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_voice');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    VoiceRecorder.sourceFactory = RecordAudioSource.new;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  List<String> media() => [for (final f in Directory('${root.path}/media').listSync()) f.path.split('/').last]..sort();

  test('graba a .m4a.tmp y al parar renombra a .m4a y da la duración', () async {
    final fake = FakeAudioSource();
    VoiceRecorder.sourceFactory = () => fake;
    final r = VoiceRecorder(store);
    expect(r.recording, isFalse);
    await r.start('i1', 'm1.m4a');
    expect(r.recording, isTrue);
    expect(r.busy, isTrue);
    expect(r.isRecording('i1'), isTrue);
    expect(r.isRecording('otro'), isFalse);
    expect(media(), ['m1.m4a.tmp'], reason: 'mientras graba, solo el temporal (la sync lo ignora)');
    fake.level.add(.7);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(r.level, closeTo(.7, 1e-9));
    final res = await r.stop();
    expect(res, isNotNull);
    expect(res!.itemId, 'i1');
    expect(res.file, 'm1.m4a');
    expect(res.ms, greaterThanOrEqualTo(50));
    expect(media(), ['m1.m4a']);
    expect(File(store.media('m1.m4a').path).lengthSync(), 2048);
    expect(r.recording, isFalse);
    expect(fake.stopped && fake.disposed, isTrue);
    expect(await r.stop(), isNull, reason: 'parar de nuevo no hace nada');
    r.dispose();
  });

  test('avisa a los oyentes mientras graba (cronómetro) y al parar', () async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final r = VoiceRecorder(store);
    var n = 0;
    r.addListener(() => n++);
    await r.start('i1', 'm1.m4a');
    final n0 = n;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(n, greaterThan(n0 + 1), reason: 'se actualiza solo, unas 4 veces por segundo');
    await r.stop();
    final n1 = n;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(n, n1, reason: 'parado, no avisa más');
    r.dispose();
  });

  test('solo una a la vez: la segunda tira "Ya hay una grabación en curso" y la primera sigue', () async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final r = VoiceRecorder(store);
    await r.start('i1', 'm1.m4a');
    await expectLater(r.start('i2', 'm2.m4a'), throwsA(isA<VoiceException>().having((e) => e.message, 'mensaje', 'Ya hay una grabación en curso')));
    expect(r.itemId, 'i1');
    expect(media(), ['m1.m4a.tmp']);
    await r.discard();
    r.dispose();
  });

  test('sin permiso del micrófono: VoiceException y no queda nada en disco ni grabando', () async {
    final fake = FakeAudioSource(permission: false);
    VoiceRecorder.sourceFactory = () => fake;
    final r = VoiceRecorder(store);
    await expectLater(r.start('i1', 'm1.m4a'), throwsA(isA<VoiceException>().having((e) => e.message, 'mensaje', contains('permiso'))));
    expect(r.recording, isFalse);
    expect(r.busy, isFalse);
    expect(media(), isEmpty);
    expect(fake.disposed, isTrue);
    r.dispose();
  });

  test('si el micrófono falla al arrancar: VoiceException con el error y se puede reintentar', () async {
    VoiceRecorder.sourceFactory = () => FakeAudioSource(failStart: true);
    final r = VoiceRecorder(store);
    await expectLater(r.start('i1', 'm1.m4a'), throwsA(isA<VoiceException>().having((e) => e.message, 'mensaje', contains('micrófono ocupado'))));
    expect(r.busy, isFalse);
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    await r.start('i2', 'm2.m4a');
    expect(r.itemId, 'i2');
    await r.discard();
    r.dispose();
  });

  test('descartar para y borra el archivo (no queda ni .tmp ni .m4a)', () async {
    final fake = FakeAudioSource();
    VoiceRecorder.sourceFactory = () => fake;
    final r = VoiceRecorder(store);
    await r.start('i1', 'm1.m4a');
    await r.discard();
    expect(r.recording, isFalse);
    expect(media(), isEmpty);
    expect(fake.stopped, isTrue);
    r.dispose();
  });

  test('si no quedó archivo (o está vacío), parar da null y no deja nada', () async {
    VoiceRecorder.sourceFactory = () => FakeAudioSource(bytes: 0);
    final r = VoiceRecorder(store);
    await r.start('i1', 'm1.m4a');
    expect(await r.stop(), isNull);
    expect(media(), isEmpty);
    r.dispose();
  });
}
