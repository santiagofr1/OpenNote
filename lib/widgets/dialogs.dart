import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';

// Diálogos compartidos entre la biblioteca y el cuaderno.

/// Hoja inferior que nunca desborda: ocupa lo que necesita, scrollea si no entra (pantalla baja,
/// horizontal) y sube con el teclado.
Future<T?> showSafeSheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(top: false, child: builder(ctx)),
      ),
    );

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = '', String ok = 'Listo'}) {
  final c = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
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

/// Nombre y tipo de un cuaderno nuevo: hojas (por defecto) o lienzo infinito. null si se cancela.
Future<({String name, bool canvas})?> askNewNotebook(BuildContext context, {String hint = 'Ej: Análisis II'}) {
  final c = TextEditingController();
  var canvas = false;
  return showDialog<({String name, bool canvas})>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final cs = Theme.of(ctx).colorScheme;
      Widget kind(Key key, IconData icon, String title, String sub, bool value) => Expanded(
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(14),
              onTap: () => set(() => canvas = value),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: canvas == value ? cs.primary : cs.outlineVariant, width: canvas == value ? 2.5 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, weight: 300, color: canvas == value ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          );
      return AlertDialog(
        scrollable: true,
        title: const Text('Nuevo cuaderno'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              key: const Key('askText'),
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.pop(ctx, (name: v, canvas: canvas)),
            ),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              kind(const Key('nbKindSheets'), Symbols.description, 'Hojas', '', false),
              const SizedBox(width: 10),
              kind(const Key('nbKindCanvas'), Symbols.gesture, 'Lienzo infinito',
                  'Sin cortes, crece mientras escribís. Para mapas conceptuales y diagramas', true),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(key: const Key('askOk'), onPressed: () => Navigator.pop(ctx, (name: c.text, canvas: canvas)), child: const Text('Crear')),
        ],
      );
    }),
  );
}

Future<bool> confirmDelete(BuildContext context, String title, String msg) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          scrollable: true,
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

Future<bool> confirmDeleteNotebook(BuildContext context, Notebook nb) =>
    confirmDelete(context, 'Borrar "${nb.name}"', 'Se borran sus ${nb.totalSheets} ${nb.totalSheets == 1 ? 'hoja' : 'hojas'}. No se puede deshacer.');

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

/// Aviso abajo; reemplaza al anterior para que no se encolen.
void snack(BuildContext context, String m,
        {Duration duration = const Duration(seconds: 4), double width = 340, SnackBarAction? action}) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: duration, width: width, action: action));
