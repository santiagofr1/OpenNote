import 'dart:io';

/// Datos del proyecto de Google Cloud. NO están en el repo: se pasan al compilar con `--dart-define` (o, más cómodo,
/// `--dart-define-from-file=google_config.json`; el archivo real está en el .gitignore, el modelo es
/// `google_config.example.json`). Pasos para conseguirlos: docs/SINCRONIZACION.md, "Configurar Google Cloud".
///
/// Si faltan, la app compila y anda igual: la pantalla de sincronización avisa que falta configurar.
class GoogleConfig {
  /// Android: ID de cliente OAuth de tipo "Aplicación web" (lo pide `google_sign_in` como `serverClientId`).
  /// El cliente "Android" (paquete + SHA-1) no se escribe en ningún lado: Google lo reconoce por la firma de la app.
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Linux / escritorio: cliente OAuth de tipo "Aplicación de escritorio". Google exige mandar el secreto en el
  /// canje del código aunque en una app instalada no sea secreto de verdad.
  static const desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  static bool get androidReady => webClientId.isNotEmpty;
  static bool get desktopReady => desktopClientId.isNotEmpty && desktopClientSecret.isNotEmpty;

  static bool get isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// ¿Está lo necesario para esta plataforma?
  static bool get ready => Platform.isAndroid ? androidReady : (isDesktop ? desktopReady : false);

  /// Qué falta, en castellano.
  static String get missing {
    if (Platform.isAndroid) return androidReady ? '' : 'GOOGLE_WEB_CLIENT_ID';
    if (isDesktop) {
      return [
        if (desktopClientId.isEmpty) 'GOOGLE_DESKTOP_CLIENT_ID',
        if (desktopClientSecret.isEmpty) 'GOOGLE_DESKTOP_CLIENT_SECRET',
      ].join(', ');
    }
    return 'esta plataforma no está soportada';
  }
}
