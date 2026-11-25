import 'package:flutter/widgets.dart';

/// Los idiomas de la app (los de los .arb).
const kAppLanguages = ['es', 'en', 'pt'];

/// El idioma de la app para los idiomas del sistema [system]: el primero que sea es, en o pt (sin mirar la región);
/// si ninguno lo es, inglés.
Locale resolveAppLocale(List<Locale>? system, [Iterable<String> supported = kAppLanguages]) {
  for (final l in system ?? const <Locale>[]) {
    if (supported.contains(l.languageCode)) return Locale(l.languageCode);
  }
  return const Locale('en');
}

/// Las preferencias de idioma (se guardan en prefs.json):
/// - [appLanguage]: `system` (el del sistema) o `es` / `en` / `pt`.
/// - [inkLanguage]: `app` (el mismo que la app) o `es` / `en` / `pt`, para leer la letra a mano.
/// Avisa a quien escuche cuando cambian: la app se redibuja en el idioma nuevo sin reiniciar.
class LanguageSettings extends ChangeNotifier {
  LanguageSettings({String appLanguage = 'system', String inkLanguage = 'app'})
      : _app = _valid(appLanguage, 'system'),
        _ink = _valid(inkLanguage, 'app');

  String _app, _ink;

  /// Ya se leyeron las preferencias guardadas (antes valen las de fábrica).
  bool get loaded => _loaded;
  bool _loaded = false;

  static String _valid(String v, String auto) => v == auto || kAppLanguages.contains(v) ? v : auto;

  String get appLanguage => _app;
  String get inkLanguage => _ink;

  /// El idioma elegido a mano, o null para seguir al sistema (lo que va en `MaterialApp.locale`).
  Locale? get locale => _app == 'system' ? null : Locale(_app);

  /// El idioma con el que se lee la letra: el elegido o, con `app`, el que [appLanguage] resolvió ([appLanguageCode]).
  String effectiveInk(String appLanguageCode) => _ink == 'app' ? appLanguageCode : _ink;

  set appLanguage(String v) {
    final n = _valid(v, 'system');
    if (n == _app) return;
    _app = n;
    notifyListeners();
  }

  set inkLanguage(String v) {
    final n = _valid(v, 'app');
    if (n == _ink) return;
    _ink = n;
    notifyListeners();
  }

  /// Lee las claves `appLanguage` e `inkLanguage` de las preferencias (null o inválidas: las de siempre).
  void load(Map? prefs) {
    final a = _valid('${prefs?['appLanguage'] ?? 'system'}', 'system');
    final i = _valid('${prefs?['inkLanguage'] ?? 'app'}', 'app');
    _app = a;
    _ink = i;
    _loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {'appLanguage': _app, 'inkLanguage': _ink};
}

/// Pone las preferencias de idioma al alcance de las pantallas (ver [LanguageScope.of]).
class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({super.key, required LanguageSettings settings, required super.child}) : super(notifier: settings);

  /// Las preferencias si hay un [LanguageScope] arriba (null si no: los tests de pantallas sueltas).
  static LanguageSettings? maybeOf(BuildContext context, {bool listen = false}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<LanguageScope>()
        : context.getInheritedWidgetOfExactType<LanguageScope>();
    return scope?.notifier;
  }

  /// Las preferencias; con [listen] la pantalla se redibuja cuando cambian.
  static LanguageSettings of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<LanguageScope>()
        : context.getInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'No hay LanguageScope sobre este contexto');
    return scope!.notifier!;
  }
}
