import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Portapapeles del sistema (solo imágenes). Variables para que los tests las reemplacen.
class SystemClipboard {
  static Future<bool> Function() hasImage = _hasImage;
  static Future<Uint8List?> Function() readImage = _readImage; // bytes PNG/JPEG/…, null si no hay
}

const _channel = MethodChannel('vynote/clipboard');
const _cmdTimeout = Duration(seconds: 3);

/// Extensión con la que guardar [b] sin recodificar: 'png' o 'jpg'; null si es otro formato.
String? imageExt(Uint8List b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
  return null;
}

/// Tipo a leer de una lista de tipos (wl-paste / xclip): 'image/png' si está, si no el primer 'image/…'.
String? pickImageType(List<String> types) {
  final t = [for (final x in types) x.trim()].where((x) => x.startsWith('image/')).toList();
  if (t.isEmpty) return null;
  return t.contains('image/png') ? 'image/png' : t.first;
}

Future<bool> _hasImage() async {
  try {
    if (Platform.isAndroid) return await _channel.invokeMethod<bool>('hasImage') ?? false;
    if (Platform.isLinux) return pickImageType(await _linuxTypes()) != null;
    if (Platform.isWindows) return (await _powershell(_winHas)).trim() == '1';
  } catch (_) {}
  return false;
}

Future<Uint8List?> _readImage() async {
  try {
    if (Platform.isAndroid) return await _channel.invokeMethod<Uint8List>('readImage');
    if (Platform.isLinux) {
      final type = pickImageType(await _linuxTypes());
      if (type == null) return null;
      final r = await _run(_wayland ? 'wl-paste' : 'xclip',
          _wayland ? ['--no-newline', '--type', type] : ['-selection', 'clipboard', '-t', type, '-o'],
          bytes: true);
      final out = r?.stdout;
      return out is List<int> && out.isNotEmpty ? Uint8List.fromList(out) : null;
    }
    if (Platform.isWindows) {
      final f = File('${Directory.systemTemp.path}/vynote_clip_${DateTime.now().microsecondsSinceEpoch}.png');
      try {
        final path = f.path.replaceAll("'", "''");
        await _powershell("$_winAsm; \$i = [System.Windows.Forms.Clipboard]::GetImage(); "
            "if (\$i) { \$i.Save('$path', [System.Drawing.Imaging.ImageFormat]::Png) }");
        return await f.exists() ? await f.readAsBytes() : null;
      } finally {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return null;
}

bool get _wayland => (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;

Future<List<String>> _linuxTypes() async {
  final r = await _run(_wayland ? 'wl-paste' : 'xclip', _wayland ? ['--list-types'] : ['-selection', 'clipboard', '-t', 'TARGETS', '-o']);
  final out = r?.stdout;
  return out is String ? const LineSplitter().convert(out) : const [];
}

/// Corre [exe]; null si no está instalado, falla o tarda más de 3 s. Con [bytes] la salida es una lista de bytes.
Future<ProcessResult?> _run(String exe, List<String> args, {bool bytes = false}) async {
  try {
    final r = await Process.run(exe, args, stdoutEncoding: bytes ? null : utf8).timeout(_cmdTimeout);
    return r.exitCode == 0 ? r : null;
  } catch (_) {
    return null;
  }
}

const _winAsm = 'Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing';
const _winHas = "Add-Type -AssemblyName System.Windows.Forms; if ([System.Windows.Forms.Clipboard]::ContainsImage()) {'1'} else {'0'}";

Future<String> _powershell(String cmd) async {
  final r = await _run('powershell', ['-NoProfile', '-STA', '-Command', cmd]);
  final out = r?.stdout;
  return out is String ? out : '';
}
