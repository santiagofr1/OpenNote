import 'dart:io';

import 'package:apuntes/data/updates.dart';
import 'package:apuntes/domain/version.dart';
import 'package:apuntes/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final info = UpdateInfo(
    version: AppVersion.tryParse('1.0.12')!,
    notes: List.generate(40, (i) => '- Cambio $i').join('\n'),
    url: 'https://example.com/a.apk',
    fileName: 'a.apk',
    size: 10,
  );
  var skipped = 0, downloads = 0;
  var installs = <File>[];
  var openedSettings = 0;
  var restarts = 0;
  InstallResult result = InstallResult.launched;
  final oldPlatform = Updates.platform, oldRestart = Updates.restart;

  setUp(() {
    skipped = downloads = openedSettings = restarts = 0;
    Updates.platform = () => UpdatePlatform.android;
    Updates.restart = () async => restarts++;
    installs = [];
    result = InstallResult.launched;
    Updates.download = (i, progress, cancel) async {
      downloads++;
      progress(5, 10);
      progress(10, 10);
      return File('/tmp/fake.apk');
    };
    Updates.install = (f) async {
      installs.add(f);
      return result;
    };
    Updates.openInstallSettings = () async => openedSettings++;
  });

  tearDownAll(() {
    Updates.platform = oldPlatform;
    Updates.restart = oldRestart;
  });

  Future<void> open(
    WidgetTester t, {
    UpdateInfo? with_,
    AppVersion? installed,
    Size size = const Size(1200, 900),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating)),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const Key('go'),
              onPressed: () => offerUpdate(ctx, with_ ?? info, installed: installed, onSkip: () async => skipped++),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('go')));
    await t.pumpAndSettle();
  }

  testWidgets('muestra versión y notas con scroll', (t) async {
    await open(t);
    expect(find.text('Hay una versión nueva de Vynote'), findsOneWidget);
    expect(find.text('Versión nueva: 1.0.12'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    expect(find.text('Omitir esta versión'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
    final scroll = t.state<ScrollableState>(
      find.descendant(of: find.byKey(const Key('updateNotes')), matching: find.byType(Scrollable)),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('Ahora no no hace nada', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('updateLater')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(skipped + downloads, 0);
  });

  testWidgets('Omitir guarda la versión omitida', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('updateSkip')));
    await t.pumpAndSettle();
    expect(skipped, 1);
    expect(downloads, 0);
  });

  testWidgets('Actualizar descarga y abre el instalador', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('updateNow')));
    await t.pumpAndSettle();
    expect(downloads, 1);
    expect(installs.single.path, '/tmp/fake.apk');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('sin permiso de instalar explica y abre los ajustes', (t) async {
    result = InstallResult.needsPermission;
    await open(t);
    await t.tap(find.byKey(const Key('updateNow')));
    await t.pumpAndSettle();
    expect(find.text('Un paso más'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateOpenSettings')));
    await t.pumpAndSettle();
    expect(openedSettings, 1);
  });

  testWidgets('cancelar la descarga no instala', (t) async {
    Updates.download = (i, progress, cancel) async {
      progress(1, 10);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return cancel.cancelled ? null : File('/tmp/fake.apk');
    };
    await open(t);
    await t.tap(find.byKey(const Key('updateNow')));
    await t.pump(const Duration(milliseconds: 10));
    await t.tap(find.byKey(const Key('updateCancel')));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
    expect(installs, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  UpdateInfo withNotes(String n) => UpdateInfo(version: info.version, notes: n, url: info.url, fileName: info.fileName, size: 10);

  testWidgets('muestra "Tenés la X → nueva Y" con la instalada', (t) async {
    await open(t, installed: AppVersion.tryParse('1.0.4'));
    expect(find.text('Tenés la 1.0.4  →  nueva 1.0.12'), findsOneWidget);
  });

  testWidgets('muestra solo las novedades filtradas', (t) async {
    await open(
      t,
      with_: withNotes(
        '- Merge main into x\n- Merge feat/zoom: arregla el zoom\n- Tests nuevos\n\n**APK:** a.apk\n**Código de versión:** 5',
      ),
    );
    expect(find.text('Arregla el zoom'), findsOneWidget);
    expect(find.textContaining('Merge main'), findsNothing);
    expect(find.textContaining('APK'), findsNothing);
    expect(find.textContaining('Tests'), findsNothing);
  });

  testWidgets('sin novedades muestra el texto por defecto', (t) async {
    await open(t, with_: withNotes('**APK:** a.apk'));
    expect(find.text('Mejoras y arreglos varios.'), findsOneWidget);
  });

  testWidgets('sin desbordes en 360x640', (t) async {
    await open(t, installed: AppVersion.tryParse('1.0.4'), size: const Size(360, 640));
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('updateNow')), findsOneWidget);
  });

  Future<void> update(WidgetTester t) async {
    await t.tap(find.byKey(const Key('updateNow')));
    await t.pumpAndSettle();
  }

  testWidgets('Linux: instalada ofrece reiniciar y reinicia', (t) async {
    Updates.platform = () => UpdatePlatform.linux;
    result = InstallResult.installed;
    await open(t);
    await update(t);
    expect(find.text('Vynote se actualizó'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateRestart')));
    await t.pumpAndSettle();
    expect(restarts, 1);
  });

  testWidgets('instalada y Después no reinicia y cierra el diálogo', (t) async {
    result = InstallResult.installed;
    await open(t);
    await update(t);
    await t.tap(find.text('Después'));
    await t.pumpAndSettle();
    expect(restarts, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancelada muestra el aviso', (t) async {
    result = InstallResult.cancelled;
    await open(t);
    await update(t);
    expect(find.text('Actualización cancelada.'), findsOneWidget);
  });

  testWidgets('manual muestra el comando para copiar', (t) async {
    result = InstallResult.manual;
    await open(t);
    await update(t);
    expect(find.text('Instalala a mano'), findsOneWidget);
    expect(t.widget<SelectableText>(find.byKey(const Key('updateManualCmd'))).data, 'sudo apt install /tmp/fake.apk');
  });

  testWidgets('falla: el texto depende de la plataforma', (t) async {
    result = InstallResult.failed;
    Updates.platform = () => UpdatePlatform.linux;
    await open(t);
    await update(t);
    expect(find.text('No se pudo instalar la actualización. Probá de nuevo en un rato.'), findsOneWidget);
  });

  testWidgets('falla en Android mantiene el texto de siempre', (t) async {
    result = InstallResult.failed;
    await open(t);
    await update(t);
    expect(find.text('No pudimos abrir el instalador. Probá de nuevo en un rato.'), findsOneWidget);
  });
}
