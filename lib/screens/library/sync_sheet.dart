import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';

/// Hoja "Sincronización con Google Drive": estado y botones Conectar / Sincronizar ahora / Desconectar.
/// Sin configuración de Google avisa qué falta; nunca lanza.
class SyncSheet extends StatelessWidget {
  const SyncSheet({super.key, required this.sync, this.missing = ''});
  final SyncController sync;
  final String missing;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
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
            status = 'Esta versión no tiene configurado el acceso a Google (falta: $missing). '
                'Las notas siguen guardándose en este dispositivo.';
          case SyncPhase.disconnected:
            status = 'Sin conectar. Los cuadernos se guardan solo en este dispositivo.';
          case SyncPhase.connecting:
            status = 'Conectando con Google…';
          case SyncPhase.syncing:
            status = 'Sincronizando…';
          case SyncPhase.idle:
            status = 'Conectado como ${sync.account}\n'
                '${sync.lastSync == null ? 'Todavía no se sincronizó' : 'Última sincronización: ${SyncSheet._ago(sync.lastSync!)}'}';
        }
        if (sync.error != null) color = cs.error;
        final busy = p == SyncPhase.connecting || p == SyncPhase.syncing;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.cloud_sync, weight: 300, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('Sincronización con Google Drive', style: Theme.of(ctx).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            if (busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator()),
            Text(status, key: const Key('syncStatus'), style: TextStyle(color: cs.onSurfaceVariant)),
            if (sync.error != null) ...[
              const SizedBox(height: 8),
              Text(sync.error!, key: const Key('syncError'), style: TextStyle(color: color)),
            ],
            if (sync.conflictCount > 0) ...[
              const SizedBox(height: 8),
              Text('Hubo ${sync.conflictCount} conflicto(s): buscá las hojas "(conflicto)" y quedate con la que sirva.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (sync.backgroundSupported && p != SyncPhase.notConfigured) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('syncBackground'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Sincronizar en segundo plano'),
                subtitle: const Text('Cada 15 minutos con red, aunque la app esté cerrada.'),
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
                  label: const Text('Conectar con Google'),
                ),
              if (p == SyncPhase.idle || p == SyncPhase.syncing) ...[
                FilledButton.icon(
                  key: const Key('syncNow'),
                  onPressed: busy ? null : () => sync.syncNow(manual: true),
                  icon: const Icon(Symbols.sync, weight: 400),
                  label: const Text('Sincronizar ahora'),
                ),
                OutlinedButton(
                  key: const Key('syncDisconnect'),
                  onPressed: busy ? null : sync.disconnect,
                  child: const Text('Desconectar'),
                ),
              ],
            ]),
          ]),
        );
      },
    );
  }
}
