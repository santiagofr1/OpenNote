// Simulación de la pantalla de la tablet para correr los tests de integración en la PC (Linux).
// En Android no hace falta: ya es la pantalla de verdad.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;

/// La tablet (Galaxy Tab S6 Lite, 1200 x 2000 a 240 dpi) en vertical: 1200 x 1928 px a 1,5x (800 x 1285,3 lógicos) y
/// su barra de estado de 45 px. Es la de las capturas del README.
const kTabletPhysical = Size(1200, 1928);

/// La misma tablet en horizontal (2000 x 1128 px, 1333 x 752 lógicos): así se usa y así corren los tests en ella.
const kTabletLandscape = Size(2000, 1128);

/// Tamaño de letra del sistema de la tablet (Ajustes > Pantalla > Tamaño de fuente).
const kTabletTextScale = 1.1;
const kTabletDpr = 1.5;
const kTabletTop = 45.0;

/// Registra Roboto desde las fuentes del sistema (el motor de Linux no la encuentra solo por nombre).
Future<void> loadRoboto() async {
  const dir = '/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF';
  final loader = FontLoader('Roboto');
  var n = 0;
  for (final f in ['Light', 'Regular', 'Medium', 'Bold', 'Italic', 'BoldItalic']) {
    final file = File('$dir/Roboto-$f.ttf');
    if (file.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      n++;
    }
  }
  if (n > 0) await loader.load();
}

/// Fija la pantalla, la barra de estado, el tema oscuro y los colores de la app (sin el acento del escritorio GTK,
/// que en la tablet no existe). Todo se deshace solo al terminar el test.
void simulateTablet(WidgetTester t,
    {Size physical = kTabletPhysical, double dpr = kTabletDpr, double top = kTabletTop, double textScale = 1.0}) {
  t.view.physicalSize = physical;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  t.view.devicePixelRatio = dpr;
  t.view.padding = FakeViewPadding(top: top);
  t.view.viewPadding = FakeViewPadding(top: top);
  addTearDown(t.view.reset);
  t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  const channel = MethodChannel('io.material.plugins/dynamic_color');
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
}

/// Guarda la pantalla entera como PNG en [path] dibujando la capa raíz (en la PC; en Android se usa takeScreenshot).
Future<void> saveShot(WidgetTester t, String path) async {
  await t.pump();
  final rv = t.binding.renderViews.first;
  final layer = rv.debugLayer! as OffsetLayer;
  // el layer raíz ya trae la escala del devicePixelRatio: se pide en píxeles físicos (pixelRatio 1)
  final img = await t.runAsync(() => layer.toImage(Offset.zero & t.view.physicalSize));
  final data = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  await File(path).writeAsBytes(data!.buffer.asUint8List());
}

/// `testWidgets` de los tests de integración: en la PC cada caso corre como si fuera Android
/// (`debugDefaultTargetPlatformOverride`), así los botones, los paneles y los toques tienen la densidad de la tablet y
/// no la compacta del escritorio. Se apaga ANTES de que termine el cuerpo: flutter_test verifica que quede en null.
/// En Android es el `testWidgets` de siempre.
void testWidgets(String description, WidgetTesterCallback body, {bool? skip, Timeout? timeout, Object? tags}) =>
    ft.testWidgets(description, (t) async {
      final pc = !Platform.isAndroid;
      if (pc) debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(t);
      } finally {
        if (pc) debugDefaultTargetPlatformOverride = null;
      }
    }, skip: skip, timeout: timeout, tags: tags);
