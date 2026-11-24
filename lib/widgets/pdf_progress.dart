import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/export.dart';
import '../data/export_folder.dart';
import '../data/storage.dart';
import '../domain/domain.dart';

/// Exporta con un diálogo de progreso; después el sistema pregunta carpeta y nombre.
/// [sections]: ids de las secciones a incluir (todas si es null).
Future<void> exportPdfFlow(BuildContext context, Storage store, NotebookDoc doc,
    {List<int>? only, String? name, Set<String>? sections}) async {
  final nb = doc.nb;
  final bytes = await buildPdfWithProgress(context, store, doc, only: only, sections: sections);
  if (bytes == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await savePdf(bytes, name ?? nb.name);
  if (ok) messenger.showSnackBar(SnackBar(content: Text('PDF de "${name ?? nb.name}" guardado'), width: 340));
}

/// Genera el PDF mostrando "Hoja n de total". Null si falló (ya se avisó).
Future<Uint8List?> buildPdfWithProgress(BuildContext context, Storage store, NotebookDoc doc,
    {List<int>? only, Set<String>? sections}) async {
  final progress = ValueNotifier<(int, int)>((0, 1));
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Generando PDF'),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (ctx, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 12),
          Text('Hoja ${v.$1} de ${v.$2}', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
      ),
    ),
  ));
  try {
    final bg = await exportBackgroundPref(store);
    final bytes = await buildNotebookPdf(store, doc,
        only: only, sections: sections, background: bg, onProgress: (a, b) => progress.value = (a, b));
    nav.pop();
    return bytes;
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    return null;
  }
}

/// Exporta las hojas como PNG (un .zip, o un .png si hay una sola) con progreso cancelable; después el sistema
/// pregunta dónde guardar. [sections]: ids de las secciones a incluir (todas si es null).
Future<void> exportPngFlow(BuildContext context, Storage store, NotebookDoc doc, {Set<String>? sections}) async {
  final progress = ValueNotifier<(int, int)>((0, 1));
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var cancel = false;
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Generando imágenes'),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (ctx, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 12),
          Text('Hoja ${v.$1} de ${v.$2}', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [TextButton(key: const Key('cancelPng'), onPressed: () => cancel = true, child: const Text('Cancelar'))],
    ),
  ));
  ({Uint8List bytes, bool zip})? r;
  try {
    final bg = await exportBackgroundPref(store);
    r = await buildNotebookPngs(store, doc,
        sections: sections, background: bg, onProgress: (a, b) => progress.value = (a, b), cancelled: () => cancel);
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('No se pudieron generar las imágenes: $e')));
    return;
  }
  nav.pop();
  if (r == null || !context.mounted) return;
  final ok = await saveImages(r.bytes, doc.nb.name, r.zip);
  if (ok) messenger.showSnackBar(SnackBar(content: Text(r.zip ? 'Imágenes guardadas' : 'Imagen guardada'), width: 340));
}

/// Exporta una carpeta entera en un .zip con progreso cancelable ("Cuaderno n de total"); después el sistema
/// pregunta dónde guardar.
Future<void> exportFolderFlow(BuildContext context, Storage store, NotesIndex idx, Folder f, FolderExportFormat fmt) async {
  final progress = ValueNotifier<(int, int, String)>((0, 1, ''));
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var cancel = false;
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Exportando carpeta'),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (ctx, v, _) {
          final style = TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 12),
            Text('Cuaderno ${v.$1 < v.$2 ? v.$1 + 1 : v.$2} de ${v.$2}', style: style),
            if (v.$3.isNotEmpty) Text(v.$3, style: style.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]);
        },
      ),
      actions: [TextButton(key: const Key('cancelFolderExport'), onPressed: () => cancel = true, child: const Text('Cancelar'))],
    ),
  ));
  File? file;
  try {
    file = await buildFolderZip(store, idx, f, fmt, onProgress: (a, b, n) => progress.value = (a, b, n), cancelled: () => cancel);
    nav.pop();
    if (file == null || !context.mounted) return;
    if (await saveFolderZip(file, f.name)) messenger.showSnackBar(const SnackBar(content: Text('Carpeta exportada'), width: 340));
  } catch (e) {
    if (nav.canPop()) nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar la carpeta: $e')));
  } finally {
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}
