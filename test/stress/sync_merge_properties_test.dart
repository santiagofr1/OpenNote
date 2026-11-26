import 'dart:convert';
import 'dart:math';

import 'package:apuntes/sync/sync_merge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Propiedades de la fusión de tres vías (funciones puras): identidad, idempotencia, simetría de lo que sobrevive,
/// "editar le gana a borrar", sin ids repetidos, y convergencia de dos dispositivos que fusionan uno después del otro.
void main() {
  const ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

  /// Lista de entradas {id, v, updated} con un subconjunto al azar de [ids], en orden al azar.
  List<Map> gen(Random r) {
    final pick = [for (final id in ids) if (r.nextInt(3) != 0) id]..shuffle(r);
    return [for (final id in pick) {'id': id, 'v': r.nextInt(3), 'updated': 1 + r.nextInt(4)}];
  }

  /// Variación de [base] como la haría un dispositivo: borra, cambia, agrega, a veces reordena.
  List<Map> mutate(Random r, List<Map> base) {
    final out = [
      for (final e in base)
        if (r.nextInt(5) != 0) r.nextInt(3) == 0 ? {...e, 'v': 10 + r.nextInt(5), 'updated': 1 + r.nextInt(6)} : {...e}
    ];
    for (final id in ids) {
      if (!out.any((e) => e['id'] == id) && !base.any((e) => e['id'] == id) && r.nextInt(3) == 0) {
        out.add({'id': id, 'v': 20 + r.nextInt(3), 'updated': 1 + r.nextInt(6)});
      }
    }
    if (r.nextInt(4) == 0) out.shuffle(r);
    return out;
  }

  String enc(List<Map> l) => jsonEncode(l);
  Set<String> idSet(List<Map> l) => {for (final e in l) e['id'] as String};
  Map<String, Map> byId(List<Map> l) => {for (final e in l) e['id'] as String: e};

  for (final seed in kSeeds) {
    group('mergeById (semilla $seed)', () {
      test('identidad: si la nube no cambió, queda exactamente lo local; fusionar algo consigo mismo no cambia nada', () {
        final r = Random(seed);
        for (var i = 0; i < 300; i++) {
          final b = gen(r), l = mutate(r, b);
          expect(enc(mergeById(b, l, b)), enc(l), reason: 'semilla $seed it $i: merge(b, l, b) != l');
          expect(enc(mergeById(b, l, l)), enc(l), reason: 'semilla $seed it $i: merge(b, l, l) != l');
          expect(enc(mergeById(l, l, l)), enc(l), reason: 'semilla $seed it $i: merge(l, l, l) != l');
        }
      });

      test('sin ids repetidos, sin ids de la nada, editar le gana a borrar y lo borrado sin cambios del otro lado se va', () {
        final r = Random(seed + 100);
        for (var i = 0; i < 400; i++) {
          final b = gen(r), l = mutate(r, b), rm = mutate(r, b);
          final m = mergeById(b, l, rm);
          final tag = 'semilla $seed it $i';
          expect(idSet(m).length, m.length, reason: '$tag: ids repetidos');
          expect(idSet(l).union(idSet(rm)).containsAll(idSet(m)), isTrue, reason: '$tag: apareció un id que nadie tenía');
          final bm = byId(b), lm = byId(l), rmm = byId(rm), mm = byId(m);
          for (final id in ids) {
            final inB = bm.containsKey(id), inL = lm.containsKey(id), inR = rmm.containsKey(id);
            final changedL = inL && (!inB || jsonEncode(lm[id]) != jsonEncode(bm[id]));
            final changedR = inR && (!inB || jsonEncode(rmm[id]) != jsonEncode(bm[id]));
            // lo cambiado o agregado en un lado NUNCA se pierde
            if (changedL || changedR) expect(mm.containsKey(id), isTrue, reason: '$tag: se perdió "$id" que cambió en un lado');
            // borrado de un lado y sin cambios en el otro: se borra
            if (inB && !inL && inR && !changedR) expect(mm.containsKey(id), isFalse, reason: '$tag: "$id" borrado en L y sin cambios en R sigue');
            if (inB && !inR && inL && !changedL) expect(mm.containsKey(id), isFalse, reason: '$tag: "$id" borrado en R y sin cambios en L sigue');
            // si no cambió en ningún lado y está en los dos, queda igual
            if (inB && inL && inR && !changedL && !changedR) expect(jsonEncode(mm[id]), jsonEncode(bm[id]), reason: '$tag: "$id"');
          }
        }
      });

      test('simetría: qué ids sobreviven no depende de quién fusiona (A con B o B con A)', () {
        final r = Random(seed + 200);
        for (var i = 0; i < 400; i++) {
          final b = gen(r), l = mutate(r, b), rm = mutate(r, b);
          expect(idSet(mergeById(b, l, rm)), idSet(mergeById(b, rm, l)), reason: 'semilla $seed it $i');
        }
      });

      test('dos dispositivos que fusionan uno tras otro terminan con la MISMA lista (no hay ping-pong)', () {
        // A sube lo suyo, B fusiona con lo de A y sube, A baja eso (lo suyo no cambió desde que subió): ¿terminan iguales?
        final r = Random(seed + 300);
        for (var i = 0; i < 400; i++) {
          final b = gen(r), a = mutate(r, b), bb = mutate(r, b);
          final mA = mergeById(b, a, bb); // A fusiona con lo que subió B (empatan en la nube)
          final mB = mergeById(b, bb, mA); // B fusiona su local con lo que subió A (la base de B sigue siendo b)
          // A ve que la nube cambió y A no (local == mA == su base): baja mB tal cual. Los dos quedan en mB.
          // Lo que importa: no se perdió nada que haya tocado alguien.
          final bm = byId(b);
          for (final e in [...a, ...bb]) {
            final id = e['id'] as String;
            final cambiado = !bm.containsKey(id) || jsonEncode(e) != jsonEncode(bm[id]);
            if (cambiado) expect(idSet(mB), contains(id), reason: 'semilla $seed it $i: se perdió "$id" en la segunda fusión');
          }
          expect(idSet(mergeById(mB, mB, mB)), idSet(mB));
        }
      });
    });
  }

  group('mergeNotebookJson / mergeIndexJson con JSON de la nube que no es de fiar', () {
    // La sync acepta de la nube cualquier JSON con `format: 3` y una lista; la fusión hace `e['id'] as String`: una sola
    // entrada sin id (o con id numérico) tira TypeError EN CADA PASADA y ese archivo no vuelve a sincronizar jamás.
    final feos = <String, String>{
      'hoja sin id': '{"format":3,"sheets":[{"bg":"lined"}]}',
      'hoja con id numérico': '{"format":3,"sheets":[{"id":5}]}',
      'hoja nula y texto': '{"format":3,"sheets":[null,"x",{"id":"ok"}]}',
      'sections sin id': '{"format":3,"sheets":[],"sections":[{"name":"x"}]}',
      'cuaderno sin id': '{"format":3,"notebooks":[{"name":"x"}]}',
      'folders sin id': '{"format":3,"notebooks":[],"folders":[{}]}',
    };
    const limpio = '{"format":3,"sheets":[{"id":"a"}],"notebooks":[{"id":"a","name":"n"}]}';
    feos.forEach((nombre, feo) {
      test('notebook.json: $nombre (en la nube y en el lado local)', () {
        expect(() => mergeNotebookJson(limpio, limpio, feo), returnsNormally, reason: 'remoto feo');
        expect(() => mergeNotebookJson(limpio, feo, limpio), returnsNormally, reason: 'local feo');
        expect(() => mergeNotebookJson(feo, limpio, limpio), returnsNormally, reason: 'base fea');
      });
      test('index.json: $nombre', () {
        expect(() => mergeIndexJson(limpio, limpio, feo), returnsNormally, reason: 'remoto feo');
        expect(() => mergeIndexJson(limpio, feo, limpio), returnsNormally, reason: 'local feo');
      });
    });

    test('índices: `rev` no numérico o `updated` de cualquier tipo no tira', () {
      expect(() => mergeIndexJson('{}', '{"rev":"x","notebooks":[]}', '{"rev":2,"notebooks":[]}'), returnsNormally);
      expect(
          () => mergeIndexJson('{}', '{"notebooks":[{"id":"a","updated":"ayer"}]}', '{"notebooks":[{"id":"a","updated":2.5}]}'), returnsNormally);
    });

    test('mergeNotebookJson: juntar dos hojas nuevas conserva las dos y el orden local', () {
      final l = jsonEncode({'format': 3, 'sheets': [{'id': 'a'}, {'id': 'x'}]});
      final r = jsonEncode({'format': 3, 'sheets': [{'id': 'a'}, {'id': 'y'}]});
      final b = jsonEncode({'format': 3, 'sheets': [{'id': 'a'}]});
      final m = (jsonDecode(mergeNotebookJson(b, l, r)) as Map)['sheets'] as List;
      final got = [for (final s in m) (s as Map)['id']];
      expect(got.toSet(), {'a', 'x', 'y'}, reason: 'se perdió una hoja nueva: $got');
      expect(got.length, 3);
      expect(got.first, 'a');
    });
  });

  group('normalizeIndex / restoreIndexLocal', () {
    test('restaurar lo local sobre la forma de nube devuelve el índice original (ida y vuelta)', () {
      final r = Random(4);
      for (var i = 0; i < 100; i++) {
        final idx = {
          'format': 3,
          'rev': r.nextInt(50),
          if (r.nextBool()) 'last': 'a',
          'notebooks': [
            for (final id in ids.take(1 + r.nextInt(5))) {'id': id, 'name': 'n$id', 'last': r.nextInt(9), 'updated': r.nextInt(100)}
          ],
        };
        final text = jsonEncode(idx);
        final cloud = normalizeIndex(text);
        expect(normalizeIndex(cloud), cloud, reason: 'normalizar no es idempotente');
        expect(jsonDecode(restoreIndexLocal(cloud, text)), jsonDecode(text), reason: 'iteración $i');
      }
    });
  });
}
