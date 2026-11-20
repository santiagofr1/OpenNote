import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/export.dart';
import '../data/storage.dart';
import '../domain/domain.dart';

/// Exporta con un diálogo de progreso; después el sistema pregunta carpeta y nombre.
Future<void> exportPdfFlow(BuildContext context, Storage store, Notebook nb, {List<String>? only, String? name}) async {
  final bytes = await buildPdfWithProgress(context, store, nb, only: only);
  if (bytes == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await savePdf(bytes, name ?? nb.name);
  if (ok) messenger.showSnackBar(SnackBar(content: Text('PDF de "${name ?? nb.name}" guardado'), width: 340));
}

/// Genera el PDF mostrando "Hoja n de total". Null si falló (ya se avisó).
Future<Uint8List?> buildPdfWithProgress(BuildContext context, Storage store, Notebook nb, {List<String>? only}) async {
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
    final bytes = await buildNotebookPdf(store, nb, only: only, onProgress: (a, b) => progress.value = (a, b));
    nav.pop();
    return bytes;
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    return null;
  }
}
