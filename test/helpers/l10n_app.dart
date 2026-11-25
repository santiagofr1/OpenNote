import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Un `MaterialApp` en español con las localizaciones de la app, para los tests de widgets sueltos.
Widget l10nApp(Widget child, {Locale locale = const Locale('es')}) => MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: locale,
      home: child,
    );
