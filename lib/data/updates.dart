import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/version.dart';

/// Plataformas donde la app se actualiza sola.
enum UpdatePlatform { android, linux, windows }

/// Una versión nueva publicada en GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.url,
    required this.fileName,
    required this.size,
  });
  final AppVersion version;
  final String notes;
  final String url;
  final String fileName; // nombre del asset (.apk, .deb o .exe)
  final int size; // bytes del instalador (0 = desconocido)
}

/// Resultado de buscar: [update] es la versión nueva (null si ya está al día);
/// [failed] es que no se pudo saber (sin internet, repo privado, límite de GitHub...).
class UpdateCheck {
  const UpdateCheck({this.update, this.failed = false});
  final UpdateInfo? update;
  final bool failed;
}

/// Del JSON de `releases/latest` a [UpdateInfo]. Null si es borrador o prerelease, si el tag no es
/// `v<x>.<y>.<z>` o si no trae el instalador de la plataforma: `.apk` (Android), `_amd64.deb` (Linux) o
/// `-windows-setup.exe` (Windows).
UpdateInfo? parseRelease(Map<String, dynamic> json, {UpdatePlatform platform = UpdatePlatform.android}) {
  final suffix = switch (platform) {
    UpdatePlatform.android => '.apk',
    UpdatePlatform.linux => '_amd64.deb',
    UpdatePlatform.windows => '-windows-setup.exe',
  };
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final v = AppVersion.tryParse(json['tag_name'] as String?);
  if (v == null) return null;
  final assets = json['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'], url = a['browser_download_url'];
    if (name is String && url is String && name.toLowerCase().endsWith(suffix)) {
      final size = a['size'];
      return UpdateInfo(
        version: v,
        notes: ((json['body'] as String?) ?? '').trim(),
        url: url,
        fileName: name,
        size: size is int ? size : 0,
      );
    }
  }
  return null;
}

/// Del cuerpo del Release, las novedades para el usuario: renglones "- ...", sin metadatos ni
/// merges de main, tests o docs; "Merge feat/x: Algo" queda como "Algo". Sin repetidos, en orden.
List<String> userNotes(String body) {
  const dropped = ['merge main', 'merge branch', 'test', 'pendientes', 'readme', 'docs'];
  final prefix = RegExp(r'^Merge (?:feat|fix)/[^:\s]*: ', caseSensitive: false);
  final out = <String>[];
  for (final raw in body.split('\n')) {
    var line = raw.trim();
    if (!line.startsWith('- ') || line.contains('**APK:**') || line.contains('**Código de versión:**')) continue;
    line = line.substring(2).trim();
    if (line.isEmpty) continue;
    final low = line.toLowerCase();
    if (dropped.any(low.startsWith)) continue;
    line = line.replaceFirst(prefix, '').trim();
    if (line.isEmpty) continue;
    line = line[0].toUpperCase() + line.substring(1);
    if (!out.contains(line)) out.add(line);
  }
  return out;
}

/// La release es más nueva que la instalada (si no se puede leer la instalada, no se ofrece nada).
UpdateInfo? newerThan(UpdateInfo? latest, AppVersion? installed) =>
    latest != null && installed != null && latest.version > installed ? latest : null;

/// Opciones guardadas en prefs.json (junto a las de las herramientas).
class UpdatePrefs {
  UpdatePrefs({this.auto = true, this.lastCheck = 0, this.skipped});
  bool auto;
  int lastCheck; // ms desde epoch de la última búsqueda
  String? skipped; // versión que el usuario eligió omitir

  factory UpdatePrefs.from(Map? j) => UpdatePrefs(
        auto: j?['updAuto'] != false,
        lastCheck: j?['updLastCheck'] is int ? j!['updLastCheck'] as int : 0,
        skipped: j?['updSkipped'] as String?,
      );

  Map<String, dynamic> toJson() => {'updAuto': auto, 'updLastCheck': lastCheck, 'updSkipped': skipped};

  /// Búsqueda automática: activada y pasaron 24 h (un reloj atrasado también cuenta como "ya pasó").
  bool due(DateTime now) {
    if (!auto) return false;
    final d = now.millisecondsSinceEpoch - lastCheck;
    return d >= const Duration(hours: 24).inMilliseconds || d < 0;
  }
}

/// Cancelación de la descarga.
class CancelFlag {
  bool cancelled = false;
  void Function()? _onCancel;
  void cancel() {
    cancelled = true;
    _onCancel?.call();
  }
}

enum InstallResult {
  launched,
  needsPermission,
  failed,
  installed, // ya quedó instalada (Linux)
  cancelled, // el usuario cerró el pedido de contraseña
  manual, // no hay pkexec: hay que instalar a mano
}

/// Operaciones de actualización. Son variables para que los tests las reemplacen
/// (como `Pickers`): los tests no tocan la red ni el instalador.
class Updates {
  static const repoApi = 'https://api.github.com/repos/santiagofr1/OpenNote/releases/latest';
  static const _channel = MethodChannel('opennote/updater');

  /// Plataforma donde corre la app, o null si no se actualiza sola.
  static UpdatePlatform? Function() platform = () {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isLinux) return UpdatePlatform.linux;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return null;
  };

  /// La búsqueda automática solo corre en release en una plataforma soportada (no en debug/`.test` ni en tests).
  static bool Function() autoSupported = () => kReleaseMode && platform() != null;

  static Future<AppVersion?> Function() installed = () async =>
      AppVersion.tryParse((await PackageInfo.fromPlatform()).version);

  static Future<UpdateCheck> Function() check = () async {
    try {
      final p = platform();
      if (p == null) return const UpdateCheck(failed: true);
      final json = await _getJson(repoApi);
      if (json == null) return const UpdateCheck(failed: true);
      final info = newerThan(parseRelease(json, platform: p), await installed());
      return UpdateCheck(update: info);
    } catch (_) {
      return const UpdateCheck(failed: true);
    }
  };

  /// Baja el instalador al caché y verifica el tamaño. Null si se canceló o falló.
  static Future<File?> Function(UpdateInfo, void Function(int done, int total), CancelFlag) download = _download;

  static Future<InstallResult> Function(File) install = (f) async {
    switch (platform()) {
      case UpdatePlatform.android:
        try {
          if (await _channel.invokeMethod<bool>('canInstall') != true) return InstallResult.needsPermission;
          await _channel.invokeMethod('install', f.path);
          return InstallResult.launched;
        } catch (_) {
          return InstallResult.failed;
        }
      case UpdatePlatform.linux:
        return _installLinux(f);
      case UpdatePlatform.windows:
        return _installWindows(f);
      case null:
        return InstallResult.failed;
    }
  };

  /// Reabre la app (después de actualizar en Linux).
  static Future<void> Function() restart = () async {
    await Process.start(Platform.resolvedExecutable, const [], mode: ProcessStartMode.detached);
    exit(0);
  };

  /// Abre "instalar apps desconocidas" de OpenNote.
  static Future<void> Function() openInstallSettings = () async {
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {}
  };
}

Future<InstallResult> _installLinux(File f) async {
  try {
    final r = await Process.run('pkexec', ['apt-get', 'install', '-y', f.path]);
    if (r.exitCode == 0) return InstallResult.installed;
    if (r.exitCode == 126 || r.exitCode == 127) return InstallResult.cancelled;
    return InstallResult.failed;
  } on ProcessException {
    return InstallResult.manual;
  } catch (_) {
    return InstallResult.failed;
  }
}

Future<InstallResult> _installWindows(File f) async {
  try {
    await Process.start(f.path, ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached);
    return InstallResult.launched; // el instalador cierra la app solo
  } catch (_) {
    return InstallResult.failed;
  }
}

Future<Map<String, dynamic>?> _getJson(String url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c.getUrl(Uri.parse(url));
    req.headers
      ..set(HttpHeaders.userAgentHeader, 'OpenNote-app')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>(); // 404 (repo privado), 403/429 (límite): "sin info", en silencio
      return null;
    }
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : null;
  } finally {
    c.close(force: true);
  }
}

Future<File?> _download(UpdateInfo info, void Function(int, int) progress, CancelFlag cancel) async {
  // En Android el nombre de la carpeta lo exige file_paths.xml; en Linux el tmp es /tmp, compartido.
  final sub = Updates.platform() == UpdatePlatform.android ? 'updates' : 'opennote-updates';
  final dir = Directory('${(await getTemporaryDirectory()).path}/$sub');
  if (await dir.exists()) await dir.delete(recursive: true); // instaladores viejos
  await dir.create(recursive: true);
  final file = File('${dir.path}/${info.fileName}');
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  cancel._onCancel = () => c.close(force: true);
  IOSink? sink;
  var ok = false;
  try {
    final req = await c.getUrl(Uri.parse(info.url));
    req.headers.set(HttpHeaders.userAgentHeader, 'OpenNote-app');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final total = info.size > 0 ? info.size : res.contentLength;
    sink = file.openWrite();
    var done = 0;
    await for (final chunk in res) {
      if (cancel.cancelled) break;
      sink.add(chunk);
      done += chunk.length;
      progress(done, total);
    }
    await sink.close();
    sink = null;
    if (cancel.cancelled) return null;
    if (info.size > 0 && await file.length() != info.size) return null;
    ok = true;
    return file;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
    try {
      await sink?.close();
    } catch (_) {}
    if (!ok) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
