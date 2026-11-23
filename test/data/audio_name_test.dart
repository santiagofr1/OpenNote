import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Item audio(String text) => makeAudioItem('a.m4a', 0, name: text);

  test('nombre por defecto: el mayor "Audio N" + 1, ignora otros nombres y otros tipos', () {
    expect(nextAudioName([]), 'Audio 1');
    expect(nextAudioName([audio('Audio 1'), audio('Audio 3'), audio('Clase 9'), audio('')]), 'Audio 4');
    expect(nextAudioName([makeSticky()..text = 'Audio 7']), 'Audio 1');
  });

  test('makeAudioItem guarda el nombre en text y copy lo conserva', () {
    final a = audio('Audio 2');
    expect(a.text, 'Audio 2');
    expect(a.copy().text, 'Audio 2');
    expect(a.toJson()['text'], 'Audio 2');
    expect(makeAudioItem('b.m4a', 0).toJson().containsKey('text'), isFalse, reason: 'sin nombre no cambia el formato');
  });

  test('History.forgetItem saca el elemento de todo el historial y descarta lo que queda vacío', () {
    final a = audio('Audio 1'), b = audio('Audio 2');
    final h = History()
      ..push(EditAction(itemBefore: {a.id: null}, itemAfter: {a.id: a.copy()}))
      ..push(EditAction(itemBefore: {a.id: a.copy(), b.id: b.copy()}, itemAfter: {a.id: a.copy(), b.id: b.copy()}));
    h.forgetItem(a.id);
    final last = h.undo()!;
    expect(last.itemBefore.keys, [b.id]);
    expect(h.canUndo, isFalse, reason: 'la inserción de a quedó vacía y se descartó');
  });
}
