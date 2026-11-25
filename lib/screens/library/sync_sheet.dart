import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';
import '../../l10n/l10n.dart';
import 'crypto_section.dart';

/// Hoja "Sincronización con Google Drive": estado y botones Conectar / Sincronizar ahora / Desconectar.
/// Sin configuración de Google avisa qué falta; nunca lanza.
class SyncSheet extends StatelessWidget {
  const SyncSheet({super.key, required this.sync, this.missing = ''});
  final SyncController sync;
  final String missing;

  static String _ago(L l, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return l.syncAgoNow;
    if (d.inHours < 1) return l.syncAgoMinutes(d.inMinutes);
    if (d.inDays < 1) return l.syncAgoHours(d.inHours);
    return l.syncAgoDays(d.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: sync,
      builder: (ctx, _) {
        final p = sync.phase;
        final String status;
        Color color = cs.onSurfaceVariant;
        switch (p) {
          case SyncPhase.notConfigured:
            status = ctx.l10n.syncNotConfigured(missing);
          case SyncPhase.disconnected:
            status = ctx.l10n.syncDisconnectedStatus;
          case SyncPhase.connecting:
            status = ctx.l10n.syncConnecting;
          case SyncPhase.syncing:
            status = ctx.l10n.syncSyncing;
          case SyncPhase.idle:
            status = ctx.l10n.syncConnectedAs(
                '${sync.account}',
                sync.lastSync == null
                    ? ctx.l10n.syncNever
                    : ctx.l10n.syncLast(SyncSheet._ago(ctx.l10n, sync.lastSync!)));
        }
        if (sync.error != null) color = cs.error;
        final busy = p == SyncPhase.connecting || p == SyncPhase.syncing;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.cloud_sync, weight: 300, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(ctx.l10n.syncTitle, style: Theme.of(ctx).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            if (busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator()),
            Text(status, key: const Key('syncStatus'), style: TextStyle(color: cs.onSurfaceVariant)),
            if (sync.error != null) ...[
              const SizedBox(height: 8),
              Text(syncErrorText(ctx.l10n, sync.errorKind, sync.errorArg, sync.error!), key: const Key('syncError'), style: TextStyle(color: color)),
            ],
            if (sync.conflictCount > 0) ...[
              const SizedBox(height: 8),
              Text(ctx.l10n.syncConflicts(sync.conflictCount),
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (sync.backgroundSupported && p != SyncPhase.notConfigured) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('syncBackground'),
                contentPadding: EdgeInsets.zero,
                title: Text(ctx.l10n.syncBackgroundTitle),
                subtitle: Text(ctx.l10n.syncBackgroundSubtitle),
                value: sync.backgroundEnabled,
                onChanged: sync.setBackgroundEnabled,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (p == SyncPhase.disconnected || p == SyncPhase.connecting)
                FilledButton.icon(
                  key: const Key('syncConnect'),
                  onPressed: busy ? null : sync.connect,
                  icon: const Icon(Symbols.login, weight: 400),
                  label: Text(ctx.l10n.syncConnect),
                ),
              if (p == SyncPhase.idle || p == SyncPhase.syncing) ...[
                FilledButton.icon(
                  key: const Key('syncNow'),
                  onPressed: busy ? null : () => sync.syncNow(manual: true),
                  icon: const Icon(Symbols.sync, weight: 400),
                  label: Text(ctx.l10n.syncNow),
                ),
                OutlinedButton(
                  key: const Key('syncDisconnect'),
                  onPressed: busy ? null : sync.disconnect,
                  child: Text(ctx.l10n.syncDisconnect),
                ),
              ],
            ]),
            if (p == SyncPhase.idle || p == SyncPhase.syncing) CryptoSection(sync: sync),
          ]),
        );
      },
    );
  }
}
