import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/library/library_screen.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

class ApuntesApp extends StatelessWidget {
  /// [root]: carpeta de datos propia (los tests usan una temporal)
  const ApuntesApp({super.key, this.root});
  final Directory? root;
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
          home: Library(root: root),
        ),
      );
}
