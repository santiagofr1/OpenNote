import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/updates.dart';
import '../domain/version.dart';
import '../l10n/l10n.dart';
import 'dialogs.dart';

enum UpdateChoice { later, skip, update }

/// "Hay una versión nueva de Vynote": versiones, novedades (con scroll) y tres botones.
Future<UpdateChoice?> showUpdateDialog(BuildContext context, UpdateInfo info, {AppVersion? installed}) {
  final notes = userNotes(info.notes);
  final theme = Theme.of(context);
  final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
  return showDialog<UpdateChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      icon: const Icon(Symbols.new_releases, weight: 300),
      title: Text(ctx.l10n.updateAvailableTitle, textAlign: TextAlign.center),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              installed == null
                  ? ctx.l10n.updateNewVersion('${info.version}')
                  : ctx.l10n.updateVersions('$installed', '${info.version}'),
              key: const Key('updateVersions'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(ctx.l10n.updateNotesTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(ctx).height * 0.25).clamp(80.0, 240.0)),
              child: Scrollbar(
                child: SingleChildScrollView(
                  key: const Key('updateNotes'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final n in notes.isEmpty ? [ctx.l10n.updateNotesDefault] : notes)
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
              ctx.l10n.updateSourceInfo,
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
          child: Text(ctx.l10n.commonNotNow),
        ),
        TextButton(
          key: const Key('updateSkip'),
          onPressed: () => Navigator.pop(ctx, UpdateChoice.skip),
          child: Text(ctx.l10n.updateSkip),
        ),
        FilledButton(
          key: const Key('updateNow'),
          onPressed: () => Navigator.pop(ctx, UpdateChoice.update),
          child: Text(ctx.l10n.updateInstall),
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
      title: Text(ctx.l10n.updateDownloading),
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
              Text(v == null ? ctx.l10n.updateConnecting : '${(v * 100).round()} %'),
            ],
          ),
        ),
      ),
      actions: [TextButton(key: const Key('updateCancel'), onPressed: cancel.cancel, child: Text(ctx.l10n.commonCancel))],
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
    snack(context, context.l10n.updateDownloadFailed);
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
          title: Text(ctx.l10n.updateStepTitle),
          content: Text(ctx.l10n.updatePermissionBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonNotNow)),
            FilledButton(
              key: const Key('updateOpenSettings'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.updateGoToSettings),
            ),
          ],
        ),
      );
      if (go == true) await Updates.openInstallSettings();
    case InstallResult.installed:
      final restart = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.updateDoneTitle),
          content: Text(ctx.l10n.updateDoneBody('${info.version}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonLater)),
            FilledButton(
              key: const Key('updateRestart'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.updateRestartNow),
            ),
          ],
        ),
      );
      if (restart == true) await Updates.restart();
    case InstallResult.cancelled:
      snack(context, context.l10n.updateCancelled);
    case InstallResult.manual:
      final cmd = 'sudo apt install ${file.path}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.updateManualTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ctx.l10n.updateManualBody),
              const SizedBox(height: 12),
              SelectableText(cmd, key: const Key('updateManualCmd'), style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: cmd));
                if (ctx.mounted) snack(ctx, ctx.l10n.updateCommandCopied);
              },
              child: Text(ctx.l10n.commonCopy),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonDone)),
          ],
        ),
      );
    case InstallResult.failed:
      snack(
        context,
        Updates.platform() == UpdatePlatform.android
            ? context.l10n.updateInstallerFailed
            : context.l10n.updateInstallFailed,
      );
  }
}
