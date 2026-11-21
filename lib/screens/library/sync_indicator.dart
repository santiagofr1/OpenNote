import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';

/// Indicador chico del estado de la sincronización para las barras de arriba: al día, sincronizando, pendiente, sin
/// conexión o con error. Sin texto (solo el tooltip). Tocarlo abre la hoja de Sincronización ([onTap]). No se ve si no
/// hay sesión con Google (el estado "sin conectar" está en el menú ⋮ de la biblioteca).
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.sync, required this.onTap});
  final SyncController sync;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final st = sync.status;
        if (st == SyncStatus.off) return const SizedBox.shrink();
        final (IconData icon, Color color, String tip) = switch (st) {
          SyncStatus.synced => (Symbols.cloud_done, cs.onSurfaceVariant, 'Sincronizado'),
          SyncStatus.syncing => (Symbols.cloud_sync, cs.primary, 'Sincronizando'),
          SyncStatus.pending => (Symbols.cloud_upload, cs.primary, 'Cambios por subir'),
          SyncStatus.offline => (Symbols.cloud_off, cs.outline, 'Sin conexión'),
          _ => (Symbols.sync_problem, cs.error, 'Error de sincronización'),
        };
        return IconButton(
          key: const Key('syncIndicator'),
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 22, weight: 300, color: color, semanticLabel: tip),
        );
      },
    );
  }
}
