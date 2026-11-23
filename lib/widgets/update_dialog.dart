import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/updates.dart';
import '../domain/version.dart';
import 'dialogs.dart';

enum UpdateChoice { later, skip, update }

/// "Hay una versión nueva de OpenNote": versiones, novedades (con scroll) y tres botones.
Future<UpdateChoice?> showUpdateDialog(BuildContext context, UpdateInfo info, {AppVersion? installed}) {
  final notes = userNotes(info.notes);
  final theme = Theme.of(context);
  final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
  return showDialog<UpdateChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      icon: const Icon(Symbols.new_releases, weight: 300),
      title: const Text('Hay una versión nueva de OpenNote', textAlign: TextAlign.center),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              installed == null ? 'Versión nueva: ${info.version}' : 'Tenés la $installed  →  nueva ${info.version}',
              key: const Key('updateVersions'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text('Novedades', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(ctx).height * 0.25).clamp(80.0, 240.0)),
              child: Scrollbar(
                child: SingleChildScrollView(
                  key: const Key('updateNotes'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final n in notes.isEmpty ? const ['Mejoras y arreglos varios.'] : notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: Text(n)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Se baja de la página oficial del proyecto en GitHub. Tus cuadernos no se tocan: solo se actualiza la app.',
              style: small,
            ),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('updateLater'),
          onPressed: () => Navigator.pop(ctx, UpdateChoice.later),
          child: const Text('Ahora no'),
        ),
        TextButton(
          key: const Key('updateSkip'),
          onPressed: () => Navigator.pop(ctx, UpdateChoice.skip),
          child: const Text('Omitir esta versión'),
        ),
        FilledButton(
          key: const Key('updateNow'),
          onPressed: () => Navigator.pop(ctx, UpdateChoice.update),
          child: const Text('Actualizar'),
        ),
      ],
    ),
  );
}

/// Ofrece la versión nueva y, si el usuario acepta, descarga e instala.
/// [onSkip] guarda que esa versión se omite.
Future<void> offerUpdate(
  BuildContext context,
  UpdateInfo info, {
  AppVersion? installed,
  required Future<void> Function() onSkip,
}) async {
  final choice = await showUpdateDialog(context, info, installed: installed);
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
      title: const Text('Bajando la versión nueva'),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(key: const Key('updateProgress'), value: v),
              const SizedBox(height: 8),
              Text(v == null ? 'Conectando…' : '${(v * 100).round()} %'),
            ],
          ),
        ),
      ),
      actions: [TextButton(key: const Key('updateCancel'), onPressed: cancel.cancel, child: const Text('Cancelar'))],
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  File? file;
  try {
    file = await Updates.download(info, (done, total) => progress.value = total > 0 ? done / total : null, cancel);
  } finally {
    if (nav.mounted) nav.pop(); // cierra el diálogo de progreso
    progress.dispose();
  }
  if (!context.mounted || cancel.cancelled) return;
  if (file == null) {
    snack(context, 'No pudimos bajar la actualización. Probá de nuevo en un rato.');
    return;
  }
  final r = await Updates.install(file);
  if (!context.mounted) return;
  switch (r) {
    case InstallResult.launched:
      break;
    case InstallResult.needsPermission:
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Un paso más'),
          content: const Text(
            'Android pide que le des permiso a OpenNote para instalar su propia actualización. '
            'Es una sola vez. Te llevamos a los ajustes: activá "Permitir de esta fuente", volvé y tocá Actualizar de nuevo.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
            FilledButton(
              key: const Key('updateOpenSettings'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ir a ajustes'),
            ),
          ],
        ),
      );
      if (go == true) await Updates.openInstallSettings();
    case InstallResult.installed:
      final restart = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OpenNote se actualizó'),
          content: Text('Ya quedó instalada la ${info.version}. Reiniciá la app para usarla.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Después')),
            FilledButton(
              key: const Key('updateRestart'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reiniciar ahora'),
            ),
          ],
        ),
      );
      if (restart == true) await Updates.restart();
    case InstallResult.cancelled:
      snack(context, 'Actualización cancelada.');
    case InstallResult.manual:
      final cmd = 'sudo apt install ${file.path}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Instalala a mano'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No encontramos cómo pedir permisos de administrador. Abrí una terminal y corré:'),
              const SizedBox(height: 12),
              SelectableText(cmd, key: const Key('updateManualCmd'), style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: cmd));
                if (ctx.mounted) snack(ctx, 'Comando copiado');
              },
              child: const Text('Copiar'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
          ],
        ),
      );
    case InstallResult.failed:
      snack(
        context,
        Updates.platform() == UpdatePlatform.android
            ? 'No pudimos abrir el instalador. Probá de nuevo en un rato.'
            : 'No se pudo instalar la actualización. Probá de nuevo en un rato.',
      );
  }
}
