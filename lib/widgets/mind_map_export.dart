// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/export.dart';
import '../domain/domain.dart';
import '../l10n/l10n.dart';
import '../rendering/mind_map_painter.dart';

enum MindMapFormat { png, freemind }

/// Pregunta el formato del mapa conceptual del índice (imagen o `.mm` editable), lo arma y deja que el sistema lo guarde.
Future<void> exportMindMapFlow(BuildContext context, Notebook nb) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final fmt = await showDialog<MindMapFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l.mindMapTitle),
      children: [
        SimpleDialogOption(
          key: const Key('mindMapPng'),
          onPressed: () => Navigator.pop(ctx, MindMapFormat.png),
          child: Row(children: [const Icon(Symbols.image), const SizedBox(width: 12), Text(l.mindMapPng)]),
        ),
        SimpleDialogOption(
          key: const Key('mindMapFreemind'),
          onPressed: () => Navigator.pop(ctx, MindMapFormat.freemind),
          child: Row(children: [const Icon(Symbols.account_tree), const SizedBox(width: 12), Text(l.mindMapFreemind)]),
        ),
      ],
    ),
  );
  if (fmt == null || !context.mounted) return;
  try {
    final root = buildMindTree(nb, buildOutline(nb), l.mindMapUntitled);
    final safe = safeFileName(nb.name).trim();
    final base = '${safe.isEmpty ? exportTexts.notebook : safe} - mapa';
    final bool ok;
    if (fmt == MindMapFormat.png) {
      ok = await saveMindMap(await renderMindMapPng(root), '$base.png', 'image/png');
    } else {
      ok = await saveMindMap(Uint8List.fromList(utf8.encode(mindMapToFreeMind(root))), '$base.mm', 'application/x-freemind');
    }
    if (ok) messenger.showSnackBar(SnackBar(content: Text(l.mindMapSaved), width: 340));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.exportImagesFailed(errText(l, e)))));
  }
}
