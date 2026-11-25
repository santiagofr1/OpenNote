// Capturas de la app para el README, con datos de ejemplo en una carpeta temporal (nunca tus cuadernos).
// En la tablet se corre con tool/screenshots.sh (usa `flutter drive`; los PNG quedan en docs/img/).
// En la PC (Linux) se corre con tool/screenshots_pc.sh: simula la pantalla de la tablet (1200 x 1928 px, 1,5x) y
// guarda los PNG en SHOT_OUT (por defecto docs/img). El idioma del contenido de ejemplo sale de SHOT_LANG (es|en).

import 'dart:io';
import 'dart:math';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/pdf_page_image.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:integration_test/integration_test.dart';

import 'screenshots_data.dart';
import 'tablet_sim.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  const outDir = String.fromEnvironment('SHOT_OUT', defaultValue: 'docs/img');

  testWidgets('capturas del README', (t) async {
    final android = Platform.isAndroid;
    if (!android) {
      // PC: se simula la pantalla de la tablet (1200 x 1928 px a 1,5x = 800 x 1285,3 lógicos) y su barra de estado
      simulateTablet(t);
      // Roboto (la fuente de Android) desde el sistema; si no está, queda la fuente por defecto de Linux
      await loadRoboto();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Directory(outDir).createSync(recursive: true);
    }
    final root = await Directory.systemTemp.createTemp('apuntes_capturas');
    try {
      final s = Storage(root: root);
      await s.init();
      await seedLibrary(s);

      await t.pumpWidget(ApuntesApp(root: root));
      await settle(t, 3000); // que carguen las miniaturas

      // en Android hay que pasar la superficie a imagen una sola vez, antes de la primera captura
      if (android) {
        await binding.convertFlutterSurfaceToImage();
        await t.pump();
        await settle(t, 600);
      }

      Future<void> shot(String name) async {
        await t.pump();
        if (android) {
          await binding.takeScreenshot(name);
          return;
        }
        // PC: se dibuja la capa raíz entera a PNG
        await saveShot(t, '$outDir/$name.png');
      }

      await shot('03_biblioteca');

      await t.tap(find.byKey(Key('nb-$nbPhysics')));
      await settle(t, 3500);
      await shot('01_cuaderno');

      await t.tap(find.byKey(const Key('pagesBtn')));
      await settle(t, 1500);
      expect(find.byKey(const Key('pagesPanel')), findsOneWidget);
      await shot('02_panel_hojas');

      await t.tap(find.byKey(const Key('back')));
      await settle(t, 1200);

      // ---- cuadernos extra: se suman DESPUÉS de las capturas de arriba para que no cambien la biblioteca ----
      await seedExtras(s);
      await t.pumpWidget(ApuntesApp(key: UniqueKey(), root: root));
      await settle(t, 2500);

      Future<void> open(String name) async {
        final f = find.byKey(Key('nb-$name'));
        await t.ensureVisible(f);
        await settle(t, 300);
        await t.tap(f);
        await settle(t, 3500);
      }

      Future<void> back() async {
        await t.tap(find.byKey(const Key('back')));
        await settle(t, 1500);
      }

      PageEditorState editor() => t.state<PageEditorState>(find.byType(PageEditor));
      Offset docToScreen(Offset p) {
        final ed = editor();
        final layers = find
            .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
            .evaluate()
            .map((e) => e.renderObject as RenderBox)
            .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
        return layers.localToGlobal(p * ed.scale);
      }

      // 04: índice con títulos de varios niveles y sus marcas en la hoja
      await open(nbAnalysis);
      await t.tap(find.byKey(const Key('indexBtn')));
      await settle(t, 1500);
      await shot('04_indice');
      await t.tap(find.byKey(const Key('indexBtn')));
      await settle(t, 400);
      await back();

      // 05: esquema con figuras limpias y una seleccionada (8 manijas + rotar)
      await open(nbControl);
      await t.tap(find.byTooltip('Seleccionar'));
      await settle(t);
      final g = await t.startGesture(docToScreen(const Offset(550, 450)), kind: PointerDeviceKind.stylus);
      await g.up();
      await settle(t, 800);
      expect(editor().sel.strokes.length, 1);
      await shot('05_figuras');
      await back();

      // 06: PDF importado por el flujo real, con anotaciones a mano encima
      final pdfBytes = (await t.runAsync(buildPracticePdf))!;
      final savedPick = Pickers.pdf;
      Pickers.pdf = () async => (pdfBytes, nbWorksheet);
      try {
        await open(nbWorksheet);
        await t.tap(find.byKey(const Key('insert')));
        await settle(t);
        await t.tap(find.text('PDF'));
        final sw = Stopwatch()..start();
        while (editor().doc.sheetCount < 3 && sw.elapsedMilliseconds < 10000) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await t.pump();
        }
        await settle(t, 800);
        final ed = editor();
        final r = Random(5);
        const k = 1000 / 595; // puntos del PDF -> unidades de la hoja (el PDF ocupa el ancho)
        final top = practiceTop[2]! * k;
        for (final st in [
          highlighter(84, 545, top + 7 * k),
          ...write(r, practiceTop[1]! * k + 62, 'lim (3x + 1) = 3.2 + 1 = 7', x0: 110, color: '#1d4ed8'),
          ...write(r, top + 62, tr('lim sen(x)/x = 1   (límite notable)', 'lim sin(x)/x = 1   (standard limit)'), x0: 110, color: '#1d4ed8'),
          ...write(r, practiceTop[3]! * k + 62, 'a = 2  =>  f(1) = 3', x0: 110, color: '#1d4ed8'),
        ]) {
          st.z = ed.doc.nextZ();
          ed.doc.strokes[st.id] = st;
          ed.doc.markDirtyElement(st);
        }
        // ignore: invalid_use_of_protected_member
        ed.setState(() {});
        final shown = find.descendant(of: find.byType(PdfPageImage), matching: find.byType(RawImage));
        final sw2 = Stopwatch()..start();
        while (shown.evaluate().isEmpty && sw2.elapsedMilliseconds < 3000) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
        }
        await settle(t, 5000); // que se vaya el aviso "2 hojas importadas"
        await shot('06_pdf');
        await back();
      } finally {
        Pickers.pdf = savedPick;
      }

      // 07a: la hoja de sincronización con Google Drive (remoto y cuenta de mentira; nunca el Google real)
      await t.pumpWidget(ApuntesApp(key: UniqueKey(), root: root, backend: FakeBackend(FakeRemoteStore(), account: 'ana@example.com')));
      await settle(t, 2500);
      await t.tap(find.byKey(const Key('libraryMenu')));
      await settle(t);
      await t.tap(find.byKey(const Key('syncMenu')));
      await settle(t, 600);
      await t.tap(find.byKey(const Key('syncConnect')));
      for (var i = 0; i < 60 && find.byKey(const Key('syncNow')).evaluate().isEmpty; i++) {
        await settle(t, 100);
      }
      await t.tap(find.byKey(const Key('syncNow')));
      await settle(t, 6000);
      await shot('07a_sync_tablet');
      await t.pumpWidget(const SizedBox());
      await settle(t, 800);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
