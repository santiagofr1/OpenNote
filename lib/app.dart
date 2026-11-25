import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'data/export.dart';
import 'editor/handwriting.dart';
import 'editor/ink_model_tag.dart';
import 'l10n/l10n.dart';
import 'l10n/language_settings.dart';
import 'screens/library/library_screen.dart';
import 'sync/sync_backend.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

class ApuntesApp extends StatefulWidget {
  /// [root]: carpeta de datos propia (los tests usan una temporal)
  const ApuntesApp({super.key, this.root, this.backend, this.syncPoll, this.syncDebounce});
  final Directory? root;

  /// Sincronización: los tests pasan una falsa (null = Google).
  final SyncBackend? backend;

  /// Tiempos de la sincronización (null = los de siempre; los tests de integración los acortan).
  final Duration? syncPoll, syncDebounce;

  @override
  State<ApuntesApp> createState() => _ApuntesAppState();
}

class _ApuntesAppState extends State<ApuntesApp> {
  /// Idioma de la app y de la escritura a mano. La biblioteca los carga de prefs.json al arrancar y la pantalla de
  /// Ajustes los cambia: al cambiar, la app se redibuja sin reiniciar.
  final LanguageSettings _lang = LanguageSettings();

  @override
  void dispose() {
    _lang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LanguageScope(
        settings: _lang,
        child: ListenableBuilder(
          listenable: _lang,
          builder: (context, _) => DynamicColorBuilder(
            // colores del sistema (Material You) y modo claro/oscuro del dispositivo
            builder: (light, dark) => MaterialApp(
              title: 'Vynote',
              debugShowCheckedModeBanner: false,
              themeMode: ThemeMode.system,
              theme: appTheme(ColorScheme.fromSeed(seedColor: light?.primary ?? kAccent)),
              darkTheme: appTheme(ColorScheme.fromSeed(
                  seedColor: dark?.primary ?? light?.primary ?? kAccent, brightness: Brightness.dark)),
              localizationsDelegates: L.localizationsDelegates,
              supportedLocales: L.supportedLocales,
              // null = el del sistema
              locale: _lang.locale,
              // el primer idioma del sistema que esté entre es / en / pt (sin mirar la región); si no, inglés
              localeListResolutionCallback: (locales, supported) => resolveAppLocale(locales),
              builder: (context, child) => _LanguageSync(settings: _lang, child: child ?? const SizedBox.shrink()),
              home: Library(root: widget.root, backend: widget.backend, syncPoll: widget.syncPoll, syncDebounce: widget.syncDebounce),
            ),
          ),
        ),
      );
}

/// Lleva al resto de la app lo que depende del idioma elegido y no se dibuja en pantalla: el modelo de la escritura a
/// mano (con `handwriting`) y los textos de los archivos que se exportan.
class _LanguageSync extends StatefulWidget {
  const _LanguageSync({required this.settings, required this.child});
  final LanguageSettings settings;
  final Widget child;

  @override
  State<_LanguageSync> createState() => _LanguageSyncState();
}

class _LanguageSyncState extends State<_LanguageSync> {
  String? _tag;
  bool _wasLoaded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    exportTexts = exportTextsOf(l);
    final hw = handwriting;
    if (hw != null) {
      final device = WidgetsBinding.instance.platformDispatcher.locale;
      final tag = inkModelTag(widget.settings.effectiveInk(l.localeName), device);
      if (tag != hw.tag) {
        // el primer valor y el que sale de leer las preferencias guardadas no son cambios: no hay nada que borrar
        final changed = _tag != null && _wasLoaded;
        hw.tag = tag;
        if (changed) unawaited(_swapModel(hw, tag));
      }
      _tag = tag;
    }
    _wasLoaded = widget.settings.loaded;
    return widget.child;
  }

  /// Baja el modelo nuevo y, si se pudo, borra los de los otros idiomas (sin conexión se queda con el que había).
  Future<void> _swapModel(HandwritingRecognizer hw, String tag) async {
    if (await hw.ensureModel()) await hw.deleteUnusedModels(tag);
  }
}
