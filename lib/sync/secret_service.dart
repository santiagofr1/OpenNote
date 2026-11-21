import 'dart:io';

/// En Linux, `flutter_secure_storage` usa libsecret, que habla con un "Secret Service" por D-Bus (gnome-keyring,
/// KWallet, KeePassXC...). Si no hay ninguno, el plugin tira una excepción de C++ que Dart no puede atajar y la app
/// se cierra al arrancar. Por eso, antes de tocarlo, se pregunta a D-Bus si `org.freedesktop.secrets` está corriendo
/// o se puede activar. En el resto de las plataformas siempre hay almacén seguro.
class SecretService {
  static const _name = 'org.freedesktop.secrets';
  static Future<bool>? _cached;

  static Future<bool> available() => _cached ??= Platform.isLinux ? _probeLinux() : Future.value(true);

  static Future<bool> _probeLinux() async {
    for (final method in ['ListNames', 'ListActivatableNames']) {
      try {
        final r = await Process.run('dbus-send', [
          '--session',
          '--print-reply',
          '--dest=org.freedesktop.DBus',
          '/org/freedesktop/DBus',
          'org.freedesktop.DBus.$method',
        ]).timeout(const Duration(seconds: 3));
        if (r.exitCode == 0 && (r.stdout as String).contains('"$_name"')) return true;
      } catch (_) {
        // Sin dbus-send o sin bus de sesión: se toma como que no hay llavero.
      }
    }
    return false;
  }
}

/// Lo que se muestra cuando no se puede guardar la sesión en Linux.
const kNoSecretServiceMessage =
    'No hay un llavero de contraseñas (Secret Service) en este sistema, así que no se puede guardar la sesión de '
    'Google. Instalá gnome-keyring o KWallet (o activá el Secret Service de KeePassXC) y volvé a intentar.';
