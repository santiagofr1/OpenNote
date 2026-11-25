import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/export_folder.dart';
import 'package:apuntes/data/import_folder.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/vynote_file.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importar el .zip de una carpeta exportada en formato Vynote: ida y vuelta, nombres repetidos, rotos y cancelar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory rootA, rootB, tmp;
  late Storage a, b;
  late NotesIndex idxA, idxB;
  late Uint8List zip;

  Future<Uint8List> zipOf() async {
    final f = await buildFolderZip(a, idxA, idxA.folders.first, FolderExportFormat.vynote, tmp: tmp);
    return await f!.readAsBytes();
  }

  Uint8List rebuild(Uint8List src, ArchiveFile? Function(ArchiveFile f) map, [List<ArchiveFile> extra = const []]) {
    final out = Archive();
    for (final f in ZipDecoder().decodeBytes(src)) {
      final r = map(f);
      if (r != null) out.addFile(r);
    }
    extra.forEach(out.addFile);
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  Future<void> setUpAll0() async {
    rootA = await Directory.systemTemp.createTemp('apuntes_imp_a');
    rootB = await Directory.systemTemp.createTemp('apuntes_imp_b');
    tmp = await Directory.systemTemp.createTemp('apuntes_imp_tmp');
    await Future(() async {
      a = Storage(root: rootA);
      b = Storage(root: rootB);
      await a.init();
      await b.init();
      final nbA = Notebook.create('A')..folder = 'f1';
      final nbB = Notebook.create('B')..folder = 'f2';
      idxA = NotesIndex(folders: [Folder('f1', 'Facultad'), Folder('f2', 'Análisis', parent: 'f1')], notebooks: [nbA, nbB]);
      await a.saveNotebook(NotebookDoc(nbA)..texts['t'] = TextBlock('t', 90, 44, 800, 'Hola A'));
      await a.saveNotebook(NotebookDoc(nbB)..texts['t'] = TextBlock('t', 90, 44, 800, 'Hola B'));
      idxB = NotesIndex(folders: [], notebooks: []);
    });
    zip = await zipOf();
    addTearDown(() async {
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
      await tmp.delete(recursive: true);
    });
  }

  Future<FolderImportResult> imp(Uint8List bytes, {bool Function()? cancelled}) async =>
      importFolderZip(b, idxB, bytes, cancelled: cancelled);

  test('ida y vuelta: carpeta, subcarpeta y contenido', () async {
    await setUpAll0();
    final r = await imp(zip);
    expect([r.imported, r.failed.length, r.skipped], [2, 0, 0]);
    final fac = idxB.folders.firstWhere((f) => f.name == 'Facultad' && f.parent == null);
    expect(r.folder, fac);
    final ana = idxB.childrenOf(fac.id).single;
    expect(ana.name, 'Análisis');
    final nbA = idxB.notebooksIn(fac.id).single, nbB = idxB.notebooksIn(ana.id).single;
    expect((nbA.name, nbB.name), ('A', 'B'));
    final doc = await b.loadSheetDoc(nbB, 0);
    expect(doc!.texts.values.single.text, 'Hola B');
  });

  test('importar dos veces no fusiona: la segunda es "Facultad (2)"', () async {
    await setUpAll0();
    await imp(zip);
    final r = await imp(zip);
    expect(r.folder!.name, 'Facultad (2)');
    expect(idxB.childrenOf(null).map((f) => f.name), ['Facultad', 'Facultad (2)']);
    expect(idxB.notebooksIn(r.folder!.id), hasLength(1));
    expect(idxB.notebooks, hasLength(4));
  });

  test('un zip sin cuadernos Vynote tira VynoteException', () async {
    await setUpAll0();
    final png = Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('X/Y/hoja.png', [1, 2, 3]))));
    await expectLater(imp(png), throwsA(isA<VynoteException>()));
    await expectLater(imp(Uint8List.fromList([1, 2, 3])), throwsA(isA<VynoteException>()));
  });

  test('una entrada .opennote también se importa', () async {
    await setUpAll0();
    final z = rebuild(zip, (f) => f.name.endsWith('A.vynote') ? ArchiveFile.bytes('Facultad/A.opennote', f.content) : f);
    final r = await imp(z);
    expect(r.imported, 2);
    expect(idxB.notebooks.map((n) => n.name), containsAll(['A', 'B']));
  });

  test('una entrada rota se informa y las demás se importan', () async {
    await setUpAll0();
    final z = rebuild(zip, (f) => f, [ArchiveFile.bytes('Facultad/Roto.vynote', [1, 2, 3]), ArchiveFile.bytes('.DS_Store', [0])]);
    final r = await imp(z);
    expect([r.imported, r.skipped], [2, 1]);
    expect(r.failed, ['Roto']);
    expect(idxB.notebooks, hasLength(2));
  });

  test('cancelar después del primer cuaderno deja todo como estaba', () async {
    await setUpAll0();
    var calls = 0;
    final r = await imp(zip, cancelled: () => calls++ >= 1);
    expect((r.folder, r.imported), (null, 0));
    expect(idxB.folders, isEmpty);
    expect(idxB.notebooks, isEmpty);
    final dir = Directory('${rootB.path}/notebooks');
    final left = await dir.exists() ? await dir.list().toList() : [];
    expect(left, isEmpty);
  });
}
