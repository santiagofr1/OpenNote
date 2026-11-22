import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/fake_audio_source.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/voice_recorder.dart';
import 'package:apuntes/screens/notebook/notebook_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grabación de voz con el cuaderno abierto (issue #10), con un micrófono falso: la etiqueta "Grabando" en la hoja, se sigue
/// escribiendo mientras graba, solo una a la vez, parar guarda, deshacer / borrar tira lo grabado, y cerrar guarda lo grabado.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_voice_ui');
  });
  tearDown(() async {
    Storage.useIsolates = true;
    VoiceRecorder.sourceFactory = RecordAudioSource.new;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester t, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
  }

  Future<void> seed() async {
    final nb = Notebook.create('Clase');
    final d = NotebookDoc(nb);
    await Future(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveNotebook(d);
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
  }

  Future<NotebookScreenState> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // la fuente de prueba es más ancha que la real: los menús "se pasan" de ancho solo acá
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(seed);
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, find.byKey(const Key('nb-Clase')));
    await t.tap(find.byKey(const Key('nb-Clase')));
    await until(t, find.byType(PageEditor));
    return t.state<NotebookScreenState>(find.byType(NotebookScreen));
  }

  PageEditorState editor(WidgetTester t) => t.state<PageEditorState>(find.byType(PageEditor));
  List<String> media() => [for (final f in Directory('${root.path}/media').listSync()) f.path.split('/').last]..sort();
  Item? audio(WidgetTester t) => editor(t).doc.items.values.where((i) => i.type == 'audio').firstOrNull;

  Future<void> startVoice(WidgetTester t, NotebookScreenState s) async {
    await t.runAsync(() => s.runInsert('voice'));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('grabar voz no bloquea: aparece la etiqueta "Grabando", se puede dibujar, scrollear y mover, y parar guarda', (t) async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final s = await open(t);
    await startVoice(t, s);

    // la etiqueta ya está en la hoja, sin ningún diálogo
    expect(find.byType(AlertDialog), findsNothing);
    final it = audio(t)!;
    expect(it.dur, 0);
    expect(it.file, endsWith('.m4a'));
    expect(find.byKey(const ValueKey('recordingChip')), findsOneWidget);
    expect(find.textContaining('Grabando'), findsOneWidget);
    expect(find.byKey(const ValueKey('recordingDot')), findsOneWidget);
    expect(find.byKey(const ValueKey('recordingStop')), findsOneWidget);
    expect(s.recorder.recording, isTrue);
    expect(media(), ['${it.file}.tmp'], reason: 'graba a un temporal');
    expect(editor(t).selI, {it.id}, reason: 'queda elegida, como cualquier elemento insertado');

    // el cronómetro avanza
    final t0 = s.recorder.elapsedMs;
    await settle(t, 500);
    expect(s.recorder.elapsedMs, greaterThan(t0));

    // se puede escribir (dibujar con el lápiz, cambiar de herramienta) y scrollear mientras graba
    final ed = editor(t);
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await t.pump(const Duration(milliseconds: 200));
    final c = t.getCenter(find.byType(PageEditor)) + const Offset(0, 200);
    final g = await t.startGesture(c, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(c + Offset(i * 12.0, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 200));
    expect(ed.doc.strokes.length, 1, reason: 'el lápiz dibujó con la grabación en curso');
    ed.scroll.jumpTo(300);
    await t.pump(const Duration(milliseconds: 100));
    expect(s.recorder.recording, isTrue);

    // una segunda grabación no arranca
    await t.runAsync(() => s.runInsert('voice'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Ya hay una grabación en curso'), findsOneWidget);
    expect(ed.doc.items.values.where((i) => i.type == 'audio').length, 1);

    // la etiqueta se mueve como cualquier elemento (acá, directo por el modelo de selección: arrastre del dedo ya probado aparte)
    ed.sel.replace(items: [it.id]);
    final x0 = it.x;
    it.x += 50;
    ed.doc.markDirtyElement(it);
    expect(s.recorder.recording, isTrue);

    // parar con el botón: renombra, pone la duración y guarda
    await t.tap(find.byKey(const ValueKey('recordingStop')));
    await settle(t, 2500);
    expect(s.recorder.recording, isFalse);
    expect(find.byKey(const ValueKey('recordingChip')), findsNothing);
    expect(find.textContaining('Audio ·'), findsOneWidget, reason: 'vuelve a ser un audio común');
    expect(media(), [it.file], reason: 'el .tmp pasó a .m4a');
    expect(it.dur, greaterThan(400));
    expect(it.x, x0 + 50);
    final saved = await t.runAsync(() async {
      final st = Storage(root: root);
      await st.init();
      final nb = (await st.loadIndex()).notebooks.single;
      return (await st.loadNotebook(nb)).items.values.single;
    });
    expect(saved!.file, it.file);
    expect(saved.dur, it.dur, reason: 'la duración quedó guardada en la hoja');
  });

  testWidgets('deshacer la inserción mientras graba: para y descarta el archivo; es UN paso', (t) async {
    final fake = FakeAudioSource();
    VoiceRecorder.sourceFactory = () => fake;
    final s = await open(t);
    await startVoice(t, s);
    expect(s.recorder.recording, isTrue);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 1500);
    expect(audio(t), isNull, reason: 'un solo paso de deshacer saca la etiqueta');
    expect(s.recorder.recording, isFalse);
    expect(fake.stopped, isTrue);
    expect(media(), isEmpty, reason: 'sin .tmp ni .m4a');
  });

  testWidgets('borrar la etiqueta mientras graba: para y descarta', (t) async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final s = await open(t);
    await startVoice(t, s);
    await t.tap(find.text('Eliminar'));
    await settle(t, 1500);
    expect(audio(t), isNull);
    expect(s.recorder.recording, isFalse);
    expect(media(), isEmpty);
  });

  testWidgets('sin permiso del micrófono: aviso con el error y no se inserta nada', (t) async {
    VoiceRecorder.sourceFactory = () => FakeAudioSource(permission: false);
    final s = await open(t);
    await startVoice(t, s);
    expect(find.textContaining('Sin permiso para usar el micrófono'), findsOneWidget);
    expect(audio(t), isNull);
    expect(s.recorder.recording, isFalse);
    expect(media(), isEmpty);
  });

  testWidgets('cerrar el cuaderno grabando: para y guarda lo grabado hasta ahí', (t) async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final s = await open(t);
    await startVoice(t, s);
    final it = audio(t)!;
    await settle(t, 500);
    await t.runAsync(s.leave);
    await settle(t, 800);
    expect(find.byType(PageEditor), findsNothing, reason: 'volvió a la biblioteca');
    expect(media(), [it.file]);
    final saved = await t.runAsync(() async {
      final st = Storage(root: root);
      await st.init();
      final nb = (await st.loadIndex()).notebooks.single;
      return (await st.loadNotebook(nb)).items.values.single;
    });
    expect(saved!.dur, greaterThan(400));
    expect(saved.file, it.file);
  });

  testWidgets('la app pasa a segundo plano (paused): sigue grabando; detached: para y guarda', (t) async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    final s = await open(t);
    await startVoice(t, s);
    final it = audio(t)!;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(t, 300);
    expect(s.recorder.recording, isTrue, reason: 'un grabador sigue grabando en segundo plano');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await settle(t, 800);
    expect(s.recorder.recording, isFalse);
    expect(media(), [it.file]);
    expect(it.dur, greaterThan(100));
  });
}
