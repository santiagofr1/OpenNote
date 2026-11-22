import 'dart:convert';

import 'package:apuntes/sync/drive_remote_store.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// La lógica de DriveRemoteStore (mapa de nodos, deltas) contra un Drive de mentira hecho con un `http.Client` falso.
void main() {
  Map<String, Object?> file(String id, String name, String? parent, {bool folder = false, String? md5}) => {
        'id': id,
        'name': name,
        'mimeType': folder ? 'application/vnd.google-apps.folder' : 'application/octet-stream',
        'md5Checksum': ?md5,
        'modifiedTime': '2026-11-21T10:00:00.000Z',
        'createdTime': '2026-11-21T09:00:00.000Z',
        'parents': ?(parent == null ? null : [parent]),
      };

  final tree = [
    file('r', 'OpenNote', null, folder: true),
    file('i', 'index.json', 'r', md5: 'aa'),
    file('f1', 'notebooks', 'r', folder: true),
    file('f2', 'n1', 'f1', folder: true),
    file('nb', 'notebook.json', 'f2', md5: 'bb'),
  ];

  /// Drive falso: [listing] es lo que devuelve files.list; [delta] lo que devuelve changes.list.
  (http.Client, List<String>) fake(List<Map<String, Object?>> Function() listing, [Map<String, Object?> Function()? delta]) {
    final calls = <String>[];
    final c = MockClient((req) async {
      final p = req.url.path;
      calls.add(p);
      Object body;
      if (p.endsWith('/changes/startPageToken')) {
        body = {'startPageToken': 'T1'};
      } else if (p.endsWith('/changes')) {
        body = delta!();
      } else if (p.endsWith('/files')) {
        body = {'files': listing()};
      } else {
        return http.Response('{}', 404);
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    return (c, calls);
  }

  test('proceso nuevo con token guardado: listado COMPLETO (lo borrado antes no figura y el motor lo ve como borrado)', () async {
    // se borró notebook.json en otro dispositivo mientras esta app no corría
    final (c, calls) = fake(() => [for (final f in tree) if (f['id'] != 'nb') f]);
    final store = DriveRemoteStore(c, rootName: 'OpenNote');
    final ch = await store.changes('T0-viejo');
    expect(ch.full, isTrue);
    expect(ch.files.map((f) => f.path), ['index.json']);
    expect(ch.nextToken, 'T1');
    expect(calls.any((p) => p.endsWith('/changes') && !p.endsWith('startPageToken')), isFalse, reason: 'no se usó el delta');
  });

  test('un download previo (crypto.json) carga el mapa pero igual el primer changes es listado COMPLETO con el md5 actual', () async {
    // index.json cambió en Drive antes de que el proceso cargara el mapa
    final (c, calls) = fake(() => [for (final f in tree) f['id'] == 'i' ? {...f, 'md5Checksum': 'nuevo'} : f]);
    final store = DriveRemoteStore(c, rootName: 'OpenNote');
    await expectLater(store.download('crypto.json'), throwsA(isA<RemoteNotFoundException>()));
    calls.clear();
    final ch = await store.changes('T0-viejo');
    expect(ch.full, isTrue);
    expect(ch.files.firstWhere((f) => f.path == 'index.json').md5, 'nuevo');
    expect(calls.any((p) => p.endsWith('/changes') && !p.endsWith('startPageToken')), isFalse, reason: 'no se usó el delta');
  });

  test('con el mapa ya cargado se usa el delta (1 llamada) y un archivo a la papelera sale en removed', () async {
    final (c, calls) = fake(() => tree, () => {
          'newStartPageToken': 'T2',
          'changes': [
            {'fileId': 'nb', 'removed': false, 'file': {...file('nb', 'notebook.json', 'f2', md5: 'bb'), 'trashed': true}},
          ],
        });
    final store = DriveRemoteStore(c, rootName: 'OpenNote');
    final first = await store.changes(null);
    expect(first.full, isTrue);
    expect(first.files.map((f) => f.path).toSet(), {'index.json', 'notebooks/n1/notebook.json'});
    calls.clear();
    final d = await store.changes(first.nextToken);
    expect(d.full, isFalse);
    expect(d.removed, ['notebooks/n1/notebook.json']);
    expect(d.files, isEmpty);
    expect(d.nextToken, 'T2');
    expect(calls, hasLength(1), reason: 'una sola llamada barata');
  });
}
