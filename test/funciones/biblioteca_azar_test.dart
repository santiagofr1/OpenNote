import 'dart:convert';
import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Biblioteca (carpetas, mover, borrar, buscar): acciones al azar sobre el índice contra un modelo de mapas simples.
/// Invariantes después de cada paso: sin ciclos, ningún cuaderno ni carpeta apunta a algo que no existe, los cuadernos
/// no se pierden (salvo los de una carpeta borrada con su contenido), los contadores y las migas de pan coinciden con
/// un cálculo independiente.
void main() {
  /// Cálculo independiente: ¿[ancestro] está arriba de [id] (o es él)?
  bool cuelga(Map<String, String?> padre, String id, String ancestro) {
    String? c = id;
    var n = 0;
    while (c != null && n++ <= padre.length + 1) {
      if (c == ancestro) return true;
      c = padre[c];
    }
    return false;
  }

  void chequear(NotesIndex idx, Map<String, String?> padre, Map<String, String?> carpetaDe, String donde) {
    expect({for (final f in idx.folders) f.id: f.parent}, padre, reason: '$donde: carpetas');
    expect({for (final n in idx.notebooks) n.id: n.folder}, carpetaDe, reason: '$donde: cuadernos');
    for (final f in idx.folders) {
      expect(f.parent == null || padre.containsKey(f.parent), isTrue, reason: '$donde: padre inexistente');
      final path = idx.pathOf(f.id);
      expect(path.last.id, f.id, reason: '$donde: la miga de pan termina en la carpeta');
      expect(path.map((x) => x.id).toSet().length, path.length, reason: '$donde: ciclo');
      // independiente: la profundidad es la cantidad de ancestros
      var prof = 0;
      for (String? c = f.id; c != null; c = padre[c]) {
        prof++;
      }
      expect(path.length, prof, reason: '$donde: profundidad de ${f.id}');
      // descendantIds = todas las carpetas que cuelgan de f (menos f)
      expect(idx.descendantIds(f.id), {for (final g in idx.folders) if (g.id != f.id && cuelga(padre, g.id, f.id)) g.id},
          reason: '$donde: descendientes de ${f.id}');
      final cuenta = idx.notebooks.where((n) => n.folder != null && cuelga(padre, n.folder!, f.id)).length;
      expect(idx.notebookCount(f.id), cuenta, reason: '$donde: cuadernos dentro de ${f.id}');
    }
    for (final n in idx.notebooks) {
      expect(n.folder == null || padre.containsKey(n.folder), isTrue, reason: '$donde: cuaderno en carpeta inexistente');
    }
    // lo directo: cada cuaderno aparece exactamente en una lista
    final vistos = <String>[];
    for (final f in <String?>[null, ...idx.folders.map((f) => f.id)]) {
      vistos.addAll(idx.notebooksIn(f).map((n) => n.id));
    }
    expect(vistos.toSet().length, vistos.length, reason: '$donde: un cuaderno en dos carpetas');
    expect(vistos.toSet(), carpetaDe.keys.toSet(), reason: '$donde: algún cuaderno no aparece en ninguna carpeta');
  }

  for (final seed in kSeeds) {
    test('300 acciones de biblioteca al azar (semilla $seed): nada cuelga de la nada, no hay ciclos, nada se pierde', () {
      final r = Random(seed);
      final idx = NotesIndex();
      final padre = <String, String?>{};
      final carpetaDe = <String, String?>{};
      var k = 0;
      String? unaCarpeta() => padre.isEmpty || r.nextInt(5) == 0 ? null : padre.keys.elementAt(r.nextInt(padre.length));

      for (var paso = 0; paso < 300; paso++) {
        final donde = 'semilla $seed paso $paso';
        switch (r.nextInt(8)) {
          case 0 || 1: // carpeta nueva
            final p = unaCarpeta();
            final f = Folder('f${k++}', kNombresRaros[r.nextInt(kNombresRaros.length)], parent: p);
            idx.folders.add(f);
            padre[f.id] = p;
          case 2 || 3: // cuaderno nuevo
            final p = unaCarpeta();
            final n = Notebook('n${k++}', 'cuaderno $k', folder: p);
            idx.notebooks.add(n);
            carpetaDe[n.id] = p;
          case 4: // mover carpeta
            if (padre.isEmpty) break;
            final f = idx.folders[r.nextInt(idx.folders.length)];
            final dest = unaCarpeta();
            final ciclo = dest != null && cuelga(padre, dest, f.id);
            final ok = idx.moveFolder(f, dest);
            expect(ok, !ciclo, reason: '$donde: moveFolder acepta mover si y solo si no hace un ciclo');
            if (ok) padre[f.id] = dest;
          case 5: // mover cuaderno
            if (carpetaDe.isEmpty) break;
            final n = idx.notebooks[r.nextInt(idx.notebooks.length)];
            final dest = unaCarpeta();
            idx.moveNotebook(n, dest);
            carpetaDe[n.id] = dest;
          case 6: // borrar carpeta
            if (padre.isEmpty) break;
            final f = idx.folders[r.nextInt(idx.folders.length)];
            final modo = r.nextBool() ? FolderDelete.moveContentsToParent : FolderDelete.deleteContents;
            final id = f.id, arriba = f.parent;
            final desc = idx.descendantIds(id);
            final enBorrada = {for (final e in carpetaDe.entries) if (e.value == id || desc.contains(e.value)) e.key};
            final sacados = idx.deleteFolder(f, modo);
            padre.remove(id);
            if (modo == FolderDelete.moveContentsToParent) {
              expect(sacados, isEmpty, reason: '$donde: sacar el contenido no borra cuadernos');
              for (final e in padre.entries.toList()) {
                if (e.value == id) padre[e.key] = arriba;
              }
              for (final e in carpetaDe.entries.toList()) {
                if (e.value == id) carpetaDe[e.key] = arriba;
              }
            } else {
              expect(sacados.map((n) => n.id).toSet(), enBorrada, reason: '$donde: devuelve exactamente los cuadernos de adentro');
              for (final d in desc) {
                padre.remove(d);
              }
              for (final n in enBorrada) {
                carpetaDe.remove(n);
              }
            }
          default: // reparar es idempotente y no toca un índice sano
            final antes = jsonEncode(idx.toJson());
            idx.repairFolders();
            expect(jsonEncode(idx.toJson()), antes, reason: '$donde: repairFolders cambió un índice sano');
        }
        chequear(idx, padre, carpetaDe, donde);
      }
    });

    test('repairFolders con referencias rotas y ciclos al azar (semilla $seed): queda un índice válido y no se pierde nada', () {
      final r = Random(seed);
      for (var it = 0; it < 100; it++) {
        final n = 1 + r.nextInt(8);
        final idx = NotesIndex(folders: [
          for (var i = 0; i < n; i++) Folder('f$i', 'c$i', parent: r.nextInt(4) == 0 ? null : (r.nextInt(5) == 0 ? 'fantasma' : 'f${r.nextInt(n)}'))
        ], notebooks: [
          for (var i = 0; i < 5; i++) Notebook('n$i', 'x', folder: r.nextInt(3) == 0 ? null : (r.nextInt(4) == 0 ? 'fantasma' : 'f${r.nextInt(n)}'))
        ]);
        idx.repairFolders();
        final padre = {for (final f in idx.folders) f.id: f.parent};
        expect(idx.folders.length, n, reason: 'it $it: reparar no borra carpetas');
        expect(idx.notebooks.length, 5, reason: 'it $it: ni cuadernos');
        for (final f in idx.folders) {
          expect(f.parent == null || padre.containsKey(f.parent), isTrue);
          final p = idx.pathOf(f.id);
          expect(p.map((x) => x.id).toSet().length, p.length, reason: 'it $it: ciclo sin arreglar');
        }
        for (final nb in idx.notebooks) {
          expect(nb.folder == null || padre.containsKey(nb.folder), isTrue);
        }
        final j = jsonEncode(idx.toJson());
        idx.repairFolders();
        expect(jsonEncode(idx.toJson()), j, reason: 'it $it: reparar dos veces = reparar una');
        // lo que se guarda y se vuelve a leer es lo mismo
        expect(jsonEncode(NotesIndex.fromJson(jsonDecode(j) as Map).toJson()), j, reason: 'it $it: ida y vuelta');
      }
    });
  }

  group('buscar', () {
    final idx = NotesIndex(
      folders: [Folder('f1', 'Análisis Matemático'), Folder('f2', 'FÍSICA'), Folder('f3', 'niño'), Folder('f4', 'a/b')],
      notebooks: [Notebook('n1', 'Parcial de ANALISIS'), Notebook('n2', 'Apuntes ñandú'), Notebook('n3', 'Física 2')],
    );

    test('sin tildes ni mayúsculas, en las dos direcciones', () {
      expect(idx.search('analisis').folders.map((f) => f.id), ['f1']);
      expect(idx.search('ANÁLISIS').notebooks.map((n) => n.id), ['n1']);
      expect(idx.search('fisica').folders.map((f) => f.id), ['f2']);
      expect(idx.search('fisica').notebooks.map((n) => n.id), ['n3']);
      expect(idx.search('NINO').folders.map((f) => f.id), ['f3']);
      expect(idx.search('ñandu').notebooks.map((n) => n.id), ['n2']);
    });

    test('vacío o solo espacios: no devuelve nada (no "todo")', () {
      expect(idx.search('').isEmpty, isTrue);
      expect(idx.search('   ').isEmpty, isTrue);
    });

    test('caracteres raros en la consulta no tiran ni se interpretan como patrón', () {
      for (final q in ['.*', '(', '[a-', r'\', '%', '_', '\u0000', '😀', 'a/b', 'x' * 5000]) {
        expect(() => idx.search(q), returnsNormally, reason: q);
      }
      expect(idx.search('a/b').folders.map((f) => f.id), ['f4']);
      expect(idx.search('.*').isEmpty, isTrue, reason: 'no es una expresión regular');
    });

    test('propiedad: toda carpeta o cuaderno cuyo nombre CONTIENE la consulta (ASCII, sin mayúsculas) aparece', () {
      final r = Random(7);
      const abc = 'abcdeABCDE ';
      for (var i = 0; i < 300; i++) {
        final nombres = [for (var j = 0; j < 6; j++) List.generate(1 + r.nextInt(10), (_) => abc[r.nextInt(abc.length)]).join()];
        final ix = NotesIndex(folders: [for (var j = 0; j < 3; j++) Folder('f$j', nombres[j])], notebooks: [for (var j = 3; j < 6; j++) Notebook('n$j', nombres[j])]);
        final q = List.generate(1 + r.nextInt(3), (_) => abc[r.nextInt(abc.length)]).join();
        final hits = ix.search(q);
        final qq = q.trim().toLowerCase();
        final esperadasF = {for (var j = 0; j < 3; j++) if (qq.isNotEmpty && nombres[j].toLowerCase().contains(qq)) 'f$j'};
        final esperadasN = {for (var j = 3; j < 6; j++) if (qq.isNotEmpty && nombres[j].toLowerCase().contains(qq)) 'n$j'};
        expect(hits.folders.map((f) => f.id).toSet(), esperadasF, reason: 'consulta "$q" en $nombres');
        expect(hits.notebooks.map((n) => n.id).toSet(), esperadasN, reason: 'consulta "$q" en $nombres');
      }
    });

    test('BUG sospechado: un nombre con la tilde "descompuesta" (a + U+0301, como lo escriben macOS y algunos teclados) también se encuentra buscando sin tilde', () {
      final ix = NotesIndex(notebooks: [Notebook('n1', 'Análisis')]);
      expect(ix.search('analisis').notebooks, isNotEmpty);
      expect(normalizeSearch('Análisis'), 'analisis');
    });

    test('BUG sospechado: letras acentuadas que la tabla no tiene (ő, ž, ø, ł) se comparan sin acento', () {
      expect(normalizeSearch('Žižek'), normalizeSearch('zizek'));
    });
  });

  group('ordenar y migas', () {
    test('childrenOf ordena sin tildes ni mayúsculas, estable con nombres iguales', () {
      final idx = NotesIndex(folders: [Folder('1', 'zeta'), Folder('2', 'Árbol'), Folder('3', 'arbol'), Folder('4', 'Beta')]);
      final nombres = idx.childrenOf(null).map((f) => f.id).toList();
      expect(nombres.indexOf('4'), lessThan(nombres.indexOf('1')));
      expect(nombres.indexOf('2'), lessThan(nombres.indexOf('4')));
      expect(nombres.indexOf('3'), lessThan(nombres.indexOf('4')));
    });

    test('pathLabel con nombres hostiles no tira y empieza con el inicio', () {
      final idx = NotesIndex(folders: [Folder('a', kNombresRaros[7]), Folder('b', '😀', parent: 'a')]);
      expect(idx.pathLabel('b', home: 'Inicio'), startsWith('Inicio / '));
      expect(idx.pathLabel(null), 'Inicio');
      expect(idx.pathLabel('no-existe'), 'Inicio');
    });
  });
}
