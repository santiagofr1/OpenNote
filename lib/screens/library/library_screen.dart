import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/storage.dart';
import '../../domain/domain.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pdf_progress.dart';
import '../notebook/notebook_screen.dart';
import 'notebook_card.dart';

/// Biblioteca: todos los cuadernos con su miniatura.
class Library extends StatefulWidget {
  const Library({super.key, this.root});
  final Directory? root;
  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  late final store = Storage(root: widget.root);
  final tools = ToolState();
  NotesIndex? index;
  final thumbs = <String, NotebookDoc>{}; // primera hoja de cada cuaderno
  String? pressed; // cuaderno mantenido (resaltado)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await store.init();
    tools.load(await store.loadPrefs());
    final idx = await store.loadIndex();
    setState(() => index = idx);
    for (final nb in idx.notebooks) {
      final t = await store.loadSheetDoc(nb, 0);
      if (!mounted) return;
      if (t != null) setState(() => thumbs[nb.id] = t);
    }
  }

  /// favoritos primero; después los más recientes
  List<Notebook> get sorted => [...index!.notebooks]
    ..sort((a, b) => a.favorite != b.favorite ? (a.favorite ? -1 : 1) : b.updated.compareTo(a.updated));

  Future<void> _open(Notebook nb) async {
    if (nb.pin != null) {
      final p = await askPin(context, nb.name, subtitle: 'Este cuaderno está bloqueado');
      if (p == null || !mounted) return;
      if (hashPin(p) != nb.pin) {
        snack(context, 'PIN incorrecto');
        return;
      }
    }
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => NotebookScreen(store: store, index: index!, nb: nb, tools: tools),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutQuart);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child),
        );
      },
    ));
    // volvió: se guardó todo; refrescar miniatura y orden
    if (!mounted) return;
    if (!index!.notebooks.contains(nb)) {
      setState(() => thumbs.remove(nb.id)); // lo borraron desde adentro
      snack(context, 'Cuaderno borrado');
      return;
    }
    setState(() {});
    final t = await store.loadSheetDoc(nb, 0);
    if (mounted && t != null) setState(() => thumbs[nb.id] = t);
  }

  Future<void> _create() async {
    final name = (await askText(context, 'Nuevo cuaderno', hint: 'Ej: Análisis II', ok: 'Crear'))?.trim();
    if (name == null || name.isEmpty) return;
    final nb = Notebook.create(name)..touch();
    final doc = NotebookDoc(nb);
    await store.saveNotebook(doc);
    index!.notebooks.add(nb);
    await store.saveIndex(index!);
    setState(() => thumbs[nb.id] = doc);
    await _open(nb);
  }

  Future<void> _rename(Notebook nb) async {
    final n = (await askText(context, 'Renombrar cuaderno', initial: nb.name))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => nb.name = n);
    await store.saveIndex(index!);
  }

  Future<void> _duplicate(Notebook nb) async {
    final src = await store.loadNotebook(nb);
    final copy = Notebook(newId('n'), '${nb.name} (copia)', bg: nb.bg, paper: nb.paper)
      ..sheets.addAll(nb.sheets.map((s) => s.copy()))
      ..touch();
    final doc = NotebookDoc.fromSheets(copy, src.splitBySheet()); // copias: no comparte nada con el original
    await store.saveNotebook(doc);
    thumbs[copy.id] = doc;
    index!.notebooks.add(copy);
    await store.saveIndex(index!);
    setState(() {});
    if (mounted) snack(context, 'Cuaderno duplicado');
  }

  Future<void> _exportPdf(Notebook nb) async {
    final doc = await store.loadNotebook(nb);
    if (mounted) await exportPdfFlow(context, store, doc);
  }

  Future<void> _delete(Notebook nb) async {
    if (!await confirmDeleteNotebook(context, nb)) return;
    await store.deleteNotebook(index!, nb);
    setState(() => thumbs.remove(nb.id));
  }

  /// mantener apretado un cuaderno: opciones
  Future<void> _options(Notebook nb) async {
    HapticFeedback.mediumImpact();
    setState(() => pressed = nb.id);
    final cs = Theme.of(context).colorScheme;
    Widget tile(IconData i, String label, String v, {bool danger = false}) => ListTile(
          leading: Icon(i, weight: 300, color: danger ? cs.error : cs.onSurfaceVariant),
          title: Text(label, style: TextStyle(color: danger ? cs.error : cs.onSurface)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => Navigator.pop(context, v),
        );
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(nb.name,
                  style: Theme.of(ctx).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            tile(Symbols.open_in_new, 'Abrir', 'open'),
            tile(Symbols.edit, 'Renombrar', 'rename'),
            tile(Symbols.content_copy, 'Duplicar', 'dup'),
            tile(Symbols.picture_as_pdf, 'Exportar a PDF', 'pdf'),
            const Divider(indent: 16, endIndent: 16),
            tile(Symbols.delete, 'Borrar', 'delete', danger: true),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => pressed = null);
    switch (v) {
      case 'open':
        _open(nb);
      case 'rename':
        _rename(nb);
      case 'dup':
        _duplicate(nb);
      case 'pdf':
        _exportPdf(nb);
      case 'delete':
        _delete(nb);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = index;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      floatingActionButton: idx == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Symbols.add, weight: 400),
              label: const Text('Nuevo cuaderno'),
            ),
      body: idx == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 8),
                  sliver: SliverToBoxAdapter(child: _header(idx, cs)),
                ),
              ),
              if (idx.notebooks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Symbols.menu_book, size: 56, weight: 200, color: cs.onSurfaceVariant.withValues(alpha: .6)),
                      const SizedBox(height: 12),
                      Text('Todavía no hay cuadernos', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                    ]),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      mainAxisSpacing: 22,
                      crossAxisSpacing: 18,
                      childAspectRatio: .58,
                    ),
                    delegate: SliverChildListDelegate([
                      for (final nb in sorted)
                        NotebookCard(
                          key: Key('nb-${nb.name}'),
                          nb: nb,
                          thumb: thumbs[nb.id],
                          pressed: pressed == nb.id,
                          onTap: () => _open(nb),
                          onLongPress: () => _options(nb),
                        ),
                    ]),
                  ),
                ),
            ]),
    );
  }

  Widget _header(NotesIndex idx, ColorScheme cs) {
    final n = idx.notebooks.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Cuadernos',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
      const SizedBox(height: 4),
      Text(
        n == 0
            ? 'Creá el primero para empezar'
            : '$n ${n == 1 ? 'cuaderno' : 'cuadernos'} · mantené uno apretado para ver opciones',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
      ),
    ]);
  }
}
