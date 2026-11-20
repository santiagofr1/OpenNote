import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'model.dart';
import 'pdf_export.dart';
import 'storage.dart';

// Diálogos y utilidades compartidas entre la biblioteca y el cuaderno.

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = '', String ok = 'Listo'}) {
  final c = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const Key('askText'),
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(key: const Key('askOk'), onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String title, String msg) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Symbols.delete, color: cs.error, weight: 300),
          title: Text(title),
          content: Text(msg, style: TextStyle(color: cs.onSurfaceVariant)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              key: const Key('confirmDelete'),
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    ) ??
    false;

/// PIN: se guarda solo su hash
String hashPin(String pin) => sha256.convert(utf8.encode('apuntes:$pin')).toString();

Future<String?> askPin(BuildContext context, String title, {String? subtitle}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Symbols.lock, weight: 300, color: cs.primary),
        title: Text(title),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (subtitle != null)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant))),
            TextField(
              key: const Key('pinField'),
              controller: c,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(hintText: 'PIN'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(key: const Key('pinOk'), onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Listo')),
        ],
      );
    },
  );
}

String fmtDate(int ms) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms), now = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'hoy $hm';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'ayer $hm';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}${d.year != now.year ? '/${d.year}' : ''}';
}

String todayTitle() {
  final d = DateTime.now();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

void snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m), width: 340));

/// Exporta con un diálogo de progreso; después el sistema pregunta carpeta y nombre.
Future<void> exportPdfFlow(BuildContext context, Storage store, Notebook nb, {List<String>? only, String? name}) async {
  final bytes = await buildPdfWithProgress(context, store, nb, only: only);
  if (bytes == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await savePdf(Uint8List.fromList(bytes), name ?? nb.name);
  if (ok) messenger.showSnackBar(SnackBar(content: Text('PDF de "${name ?? nb.name}" guardado'), width: 340));
}

Future<List<int>?> buildPdfWithProgress(BuildContext context, Storage store, Notebook nb, {List<String>? only}) async {
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

class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const MenuRow(this.icon, this.label, {super.key, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = danger ? cs.error : cs.onSurfaceVariant;
    return Row(children: [
      Icon(icon, size: 20, weight: 300, color: c),
      const SizedBox(width: 14),
      Text(label, style: TextStyle(color: danger ? cs.error : cs.onSurface)),
    ]);
  }
}
