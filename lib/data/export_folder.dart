import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/domain.dart';
import 'export.dart';
import 'opennote_file.dart';
import 'storage.dart';

/// Cómo se exporta cada cuaderno de una carpeta.
enum FolderExportFormat { pdf, png, opennote }

/// Cuadernos de [root] y sus subcarpetas, con su ruta dentro del zip (sin extensión): "Facultad/Análisis/Parcial 1".
/// Primero los cuadernos de la carpeta, después cada subcarpeta (por nombre), a fondo. Los nombres repetidos en una
/// misma carpeta (sin importar mayúsculas) llevan " (2)", " (3)"…; cuadernos y subcarpetas comparten nombres.
List<({Notebook nb, String path})> folderExportEntries(NotesIndex idx, Folder root) {
  final out = <({Notebook nb, String path})>[];
  String clean(String name, String fallback) {
    final s = safeFileName(name).trim();
    return s.isEmpty ? fallback : s;
  }

  String unique(Set<String> used, String base) {
    var name = base;
    for (var c = 2; !used.add(name.toLowerCase()); c++) {
      name = '$base ($c)';
    }
    return name;
  }

  void walk(Folder f, String path) {
    final used = <String>{};
    for (final nb in idx.notebooksIn(f.id)) {
      out.add((nb: nb, path: '$path/${unique(used, clean(nb.name, 'Cuaderno'))}'));
    }
    for (final c in idx.childrenOf(f.id)) {
      walk(c, '$path/${unique(used, clean(c.name, 'Carpeta'))}');
    }
  }

  walk(root, clean(root.name, 'Carpeta'));
  return out;
}

/// Arma el zip de [root] en un archivo temporal, cuaderno por cuaderno (no junta todo en memoria).
/// [onProgress] recibe (hechos, total, nombre del cuaderno que empieza). Si [cancelled] da true devuelve null y no
/// deja nada. [tmp]: carpeta temporal a usar (por defecto la del sistema).
Future<File?> buildFolderZip(Storage store, NotesIndex idx, Folder root, FolderExportFormat fmt,
    {void Function(int done, int total, String name)? onProgress, bool Function()? cancelled, Directory? tmp}) async {
  final entries = folderExportEntries(idx, root);
  final base = tmp ?? await getTemporaryDirectory();
  final dir = Directory('${base.path}/opennote-export');
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final safe = safeFileName(root.name).trim();
  final file = File('${dir.path}/${safe.isEmpty ? 'Carpeta' : safe}.zip');
  final enc = ZipFileEncoder()..create(file.path);
  var closed = false;
  Future<File?> abort() async {
    closed = true;
    await enc.close();
    if (await file.exists()) await file.delete();
    return null;
  }

  try {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (cancelled?.call() ?? false) return await abort();
      onProgress?.call(i, entries.length, e.nb.name);
      switch (fmt) {
        case FolderExportFormat.pdf:
          final doc = await store.openNotebook(e.nb, radius: 0);
          enc.addArchiveFile(ArchiveFile.bytes('${e.path}.pdf', await buildNotebookPdf(store, doc)));
        case FolderExportFormat.png:
          final doc = await store.openNotebook(e.nb, radius: 0);
          await for (final p in notebookPngs(store, doc, cancelled: cancelled)) {
            enc.addArchiveFile(ArchiveFile.bytes('${e.path}/${p.name}', p.png));
          }
          if (cancelled?.call() ?? false) return await abort();
        case FolderExportFormat.opennote:
          enc.addArchiveFile(ArchiveFile.bytes('${e.path}.opennote', await exportNotebookBytes(store, e.nb)));
      }
    }
    closed = true;
    await enc.close();
  } catch (_) {
    if (!closed) {
      closed = true;
      try {
        await enc.close();
      } catch (_) {}
    }
    if (await file.exists()) await file.delete();
    rethrow;
  }
  onProgress?.call(entries.length, entries.length, '');
  return file;
}

/// Guarda el zip preguntando dónde. Es una variable para que los tests la reemplacen. Falso si el usuario canceló.
Future<bool> Function(File zip, String name) saveFolderZip = (zip, name) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar carpeta',
    fileName: '${safe.isEmpty ? 'Carpeta' : safe}.zip',
    bytes: await zip.readAsBytes(),
    mimeType: 'application/zip',
  );
  return uri != null;
};
