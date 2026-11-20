import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/updates.dart';
import 'dialogs.dart';

enum UpdateChoice { later, skip, update }

/// "Hay una versión nueva": notas (con scroll) y tres botones.
Future<UpdateChoice?> showUpdateDialog(BuildContext context, UpdateInfo info) => showDialog<UpdateChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Symbols.system_update, weight: 300),
        title: Text('Hay una versión nueva (${info.version})'),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: Scrollbar(
              child: SingleChildScrollView(
                key: const Key('updateNotes'),
                child: Text(info.notes.isEmpty ? 'Sin notas de cambios.' : info.notes),
              ),
            ),
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(key: const Key('updateLater'), onPressed: () => Navigator.pop(ctx, UpdateChoice.later), child: const Text('Más tarde')),
          TextButton(key: const Key('updateSkip'), onPressed: () => Navigator.pop(ctx, UpdateChoice.skip), child: const Text('Omitir esta versión')),
          FilledButton(key: const Key('updateNow'), onPressed: () => Navigator.pop(ctx, UpdateChoice.update), child: const Text('Actualizar')),
        ],
      ),
    );

/// Ofrece la versión nueva y, si el usuario acepta, descarga e instala.
/// [onSkip] guarda que esa versión se omite.
Future<void> offerUpdate(BuildContext context, UpdateInfo info, {required Future<void> Function() onSkip}) async {
  final choice = await showUpdateDialog(context, info);
  if (!context.mounted) return;
  switch (choice) {
    case UpdateChoice.skip:
      await onSkip();
    case UpdateChoice.update:
      await _downloadAndInstall(context, info);
    case UpdateChoice.later || null:
      break;
  }
}

Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final cancel = CancelFlag();
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Descargando actualización'),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(key: const Key('updateProgress'), value: v),
            const SizedBox(height: 8),
            Text(v == null ? 'Conectando…' : '${(v * 100).round()} %'),
          ]),
        ),
      ),
      actions: [TextButton(key: const Key('updateCancel'), onPressed: cancel.cancel, child: const Text('Cancelar'))],
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  File? apk;
  try {
    apk = await Updates.download(info, (done, total) => progress.value = total > 0 ? done / total : null, cancel);
  } finally {
    if (nav.mounted) nav.pop(); // cierra el diálogo de progreso
    progress.dispose();
  }
  if (!context.mounted || cancel.cancelled) return;
  if (apk == null) {
    snack(context, 'No se pudo descargar la actualización. Probá de nuevo más tarde.');
    return;
  }
  final r = await Updates.install(apk);
  if (!context.mounted) return;
  switch (r) {
    case InstallResult.launched:
      break;
    case InstallResult.needsPermission:
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falta un permiso'),
          content: const Text('Para instalar la actualización, Android necesita que permitas a OpenNote instalar apps. '
              'Te abrimos la pantalla: activá "Permitir de esta fuente", volvé a OpenNote y tocá Actualizar otra vez.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(key: const Key('updateOpenSettings'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir ajustes')),
          ],
        ),
      );
      if (go == true) await Updates.openInstallSettings();
    case InstallResult.failed:
      snack(context, 'No se pudo abrir el instalador.');
  }
}
