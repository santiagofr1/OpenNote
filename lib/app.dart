import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/library/library_screen.dart';
import 'sync/sync_backend.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

class ApuntesApp extends StatelessWidget {
  /// [root]: carpeta de datos propia (los tests usan una temporal)
  const ApuntesApp({super.key, this.root, this.backend, this.syncPoll, this.syncDebounce});
  final Directory? root;

  /// Sincronización: los tests pasan una falsa (null = Google).
  final SyncBackend? backend;

  /// Tiempos de la sincronización (null = los de siempre; los tests de integración los acortan).
  final Duration? syncPoll, syncDebounce;
  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        // colores del sistema (Material You) y modo claro/oscuro del dispositivo
        builder: (light, dark) => MaterialApp(
          title: 'OpenNote',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: appTheme(ColorScheme.fromSeed(seedColor: light?.primary ?? kAccent)),
          darkTheme: appTheme(ColorScheme.fromSeed(
              seedColor: dark?.primary ?? light?.primary ?? kAccent, brightness: Brightness.dark)),
          home: Library(root: root, backend: backend, syncPoll: syncPoll, syncDebounce: syncDebounce),
        ),
      );
}
