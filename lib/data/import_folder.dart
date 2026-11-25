import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/domain.dart';
import 'storage.dart';
import 'vynote_file.dart';

/// Resultado de importar un .zip de carpeta: la carpeta de primer nivel creada (si es una sola), cuántos cuadernos
/// entraron, los nombres de los que no se pudieron leer y cuántos archivos del zip no eran cuadernos.
typedef FolderImportResult = ({Folder? folder, int imported, List<String> failed, int skipped});

/// Importa el .zip que genera "Exportar carpeta" en formato Vynote: recrea las carpetas (bajo [parent]) y mete cada
/// cuaderno en su lugar. Las carpetas de primer nivel que chocan de nombre con las que ya hay no se fusionan: se crean
/// como "nombre (2)". NO guarda el índice (lo hace quien llama). Si [cancelled] da true entre cuadernos, deshace todo.
Future<FolderImportResult> importFolderZip(Storage store, NotesIndex idx, Uint8List zipBytes,
    {String? parent, void Function(int done, int total, String name)? onProgress, bool Function()? cancelled}) async {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw VynoteException('El archivo no es un .zip.', kind: VynoteError.notZip);
  }
  final valid = <ArchiveFile>[];
  var skipped = 0;
  for (final f in zip) {
    if (!f.isFile) continue;
    final lower = f.name.toLowerCase();
    final last = f.name.split('/').last;
    if (lower.startsWith('__macosx/') || last.startsWith('.') || !(lower.endsWith('.vynote') || lower.endsWith('.opennote'))) {
      skipped++;
    } else {
      valid.add(f);
    }
  }
  if (valid.isEmpty) {
    throw VynoteException('El .zip no tiene cuadernos de Vynote. ¿Lo exportaste en PDF o PNG?', kind: VynoteError.noNotebooks);
  }

  final folders = <String, Folder>{}; // por ruta acumulada
  final newFolders = <Folder>[];
  final newNotebooks = <Notebook>[];
  final topLevel = <Folder>{};
  var looseNotebooks = false;
  final failed = <String>[];

  Folder folderFor(List<String> segs) {
    Folder? cur;
    var path = '';
    for (final s in segs) {
      path = path.isEmpty ? s : '$path/$s';
      var f = folders[path];
      if (f == null) {
        var name = s;
        if (cur == null) {
          final used = {for (final c in idx.childrenOf(parent)) c.name.toLowerCase()};
          for (var c = 2; used.contains(name.toLowerCase()); c++) {
            name = '$s ($c)';
          }
        }
        f = Folder.create(name, parent: cur?.id ?? parent);
        idx.folders.add(f);
        newFolders.add(f);
        if (cur == null) topLevel.add(f);
        folders[path] = f;
      }
      cur = f;
    }
    return cur!;
  }

  Future<FolderImportResult> undo() async {
    for (final nb in newNotebooks) {
      idx.notebooks.remove(nb);
      await store.removeNotebookFiles(nb.id);
    }
    idx.folders.removeWhere(newFolders.contains);
    return (folder: null, imported: 0, failed: <String>[], skipped: 0);
  }

  for (var i = 0; i < valid.length; i++) {
    if (cancelled?.call() ?? false) return undo();
    final f = valid[i];
    final segs = f.name.split('/').where((s) => s.isNotEmpty).toList();
    final nbName = segs.removeLast().replaceFirst(RegExp(r'\.(vynote|opennote)$', caseSensitive: false), '');
    onProgress?.call(i, valid.length, nbName);
    try {
      final bytes = f.readBytes();
      if (bytes == null) throw VynoteException('vacío');
      final folder = segs.isEmpty ? null : folderFor(segs);
      final dest = folder?.id ?? parent;
      // los nombres solo chocan dentro de la carpeta de destino (en una carpeta recién creada no hay con qué chocar)
      final taken = {for (final n in idx.notebooksIn(dest)) n.name};
      final nb = await importNotebookBytes(store, Uint8List.fromList(bytes), taken: taken, folder: dest);
      idx.notebooks.add(nb);
      newNotebooks.add(nb);
      if (folder == null) looseNotebooks = true;
    } catch (_) {
      failed.add(nbName);
    }
  }
  if (cancelled?.call() ?? false) return undo();
  onProgress?.call(valid.length, valid.length, '');
  return (
    folder: topLevel.length == 1 && !looseNotebooks ? topLevel.single : null,
    imported: newNotebooks.length,
    failed: failed,
    skipped: skipped,
  );
}
