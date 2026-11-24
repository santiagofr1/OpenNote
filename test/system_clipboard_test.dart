import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/system_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imageExt reconoce PNG y JPEG por los bytes mágicos', () {
    expect(imageExt(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2])), 'png');
    expect(imageExt(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'jpg');
    expect(imageExt(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), isNull, reason: 'GIF: se recodifica');
    expect(imageExt(Uint8List(0)), isNull);
  });

  test('pickImageType prefiere image/png y si no el primer image/…', () {
    expect(pickImageType(['text/plain', 'image/jpeg', 'image/png']), 'image/png');
    expect(pickImageType(['text/plain', 'image/bmp', 'image/jpeg']), 'image/bmp');
    expect(pickImageType(['text/plain', 'text/html']), isNull);
    expect(pickImageType([]), isNull);
  });

  test('la implementación real no tira aunque falte wl-paste/xclip', () async {
    expect(await SystemClipboard.hasImage(), isA<bool>());
    await SystemClipboard.readImage();
  }, skip: !Platform.isLinux);
}
