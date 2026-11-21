import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';
import '../../sync/sync_crypto.dart';

/// Frase mínima (el cifrado vale lo que vale la frase).
const kMinPassphrase = 8;

/// Sección "Cifrado" de la hoja de sincronización: estado, activar / desactivar y el pedido de frase cuando la nube
/// ya está cifrada. Solo se muestra con la sesión de Google abierta.
class CryptoSection extends StatelessWidget {
  const CryptoSection({super.key, required this.sync});
  final SyncController sync;

  Future<void> _run(BuildContext context, Future<String?> Function() op) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final problem = await op();
    if (problem != null) messenger?.showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) {
    final crypto = sync.crypto;
    if (crypto == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: crypto,
      builder: (ctx, _) {
        final busy = sync.syncing || sync.phase == SyncPhase.connecting;
        final (String status, IconData icon) = switch (crypto.state) {
          CryptoState.unknown => ('Todavía no se sabe: se ve en la próxima sincronización.', Symbols.lock_open),
          CryptoState.off => ('Desactivado: Google puede leer lo que se sube a tu Drive.', Symbols.lock_open),
          CryptoState.on => ('Activado: en Drive solo hay archivos cifrados con tu frase.', Symbols.lock),
          CryptoState.locked => ('La nube está cifrada. Ingresá la frase para poder sincronizar.', Symbols.lock),
        };
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(),
            const SizedBox(height: 8),
            Row(children: [
              Icon(icon, weight: 300, color: crypto.state == CryptoState.on ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Cifrado', style: Theme.of(ctx).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(status, key: const Key('cryptoStatus'), style: TextStyle(color: cs.onSurfaceVariant)),
            if (crypto.progress != null) ...[
              const SizedBox(height: 6),
              Text(crypto.progress!, key: const Key('cryptoProgress'), style: TextStyle(color: cs.primary)),
            ],
            const SizedBox(height: 6),
            Text(
              'Si olvidás la frase no hay forma de recuperar lo que está en la nube (lo de este dispositivo no se pierde). '
              'Los nombres de archivo en Drive son códigos al azar y siguen a la vista.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (crypto.state == CryptoState.off || crypto.state == CryptoState.unknown)
                OutlinedButton.icon(
                  key: const Key('cryptoEnable'),
                  onPressed: busy
                      ? null
                      : () async {
                          final pass = await askPassphrase(context, confirm: true);
                          if (pass != null && context.mounted) await _run(context, () => sync.enableEncryption(pass));
                        },
                  icon: const Icon(Symbols.lock, weight: 400),
                  label: const Text('Activar cifrado'),
                ),
              if (crypto.state == CryptoState.locked)
                FilledButton.icon(
                  key: const Key('cryptoUnlock'),
                  onPressed: busy
                      ? null
                      : () async {
                          final pass = await askPassphrase(context, confirm: false);
                          if (pass != null && context.mounted) await _run(context, () => sync.unlockEncryption(pass));
                        },
                  icon: const Icon(Symbols.key, weight: 400),
                  label: const Text('Ingresar frase'),
                ),
              if (crypto.state == CryptoState.on)
                OutlinedButton(
                  key: const Key('cryptoDisable'),
                  onPressed: busy
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: const Text('¿Desactivar el cifrado?'),
                              content: const Text('Se vuelve a subir todo sin cifrar y se borra lo cifrado de Drive. '
                                  'Puede tardar si hay muchos archivos.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
                                FilledButton(
                                    key: const Key('cryptoDisableOk'),
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: const Text('Desactivar')),
                              ],
                            ),
                          );
                          if (ok == true && context.mounted) await _run(context, sync.disableEncryption);
                        },
                  child: const Text('Desactivar cifrado'),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Pide la frase. Con [confirm] la pide dos veces (para activar) y avisa qué se va a hacer. Valida sin cerrarse:
/// largo mínimo y que las dos coincidan. Devuelve la frase o null si se cancela.
Future<String?> askPassphrase(BuildContext context, {required bool confirm}) {
  final c1 = TextEditingController(), c2 = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          if (c1.text.length < kMinPassphrase) {
            setState(() => error = 'La frase tiene que tener al menos $kMinPassphrase caracteres.');
          } else if (confirm && c1.text != c2.text) {
            setState(() => error = 'Las dos frases no coinciden.');
          } else {
            Navigator.pop(ctx, c1.text);
          }
        }

        return AlertDialog(
          scrollable: true,
          title: Text(confirm ? 'Activar cifrado' : 'Frase de cifrado'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (confirm)
                const Text('Elegí una frase y anotala en un lugar seguro. Si la olvidás no hay forma de recuperar lo que '
                    'está en la nube (lo de este dispositivo no se pierde). Se va a subir todo cifrado y borrar lo anterior de Drive.'),
              if (confirm) const SizedBox(height: 12),
              TextField(
                key: const Key('cryptoPass1'),
                controller: c1,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Frase'),
                onSubmitted: (_) => confirm ? null : submit(),
              ),
              if (confirm)
                TextField(
                  key: const Key('cryptoPass2'),
                  controller: c2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repetí la frase'),
                  onSubmitted: (_) => submit(),
                ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, key: const Key('cryptoDialogError'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(key: const Key('cryptoDialogOk'), onPressed: submit, child: Text(confirm ? 'Activar' : 'Desbloquear')),
          ],
        );
      },
    ),
  );
}
