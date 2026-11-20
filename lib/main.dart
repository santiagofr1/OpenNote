import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'common.dart';
import 'model.dart';
import 'notebook_screen.dart';
import 'painters.dart';
import 'pen_panel.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApuntesApp());
}

class ApuntesApp extends StatelessWidget {
  /// [root]: carpeta de datos propia (los tests usan una temporal)
  const ApuntesApp({super.key, this.root});
  final Directory? root;
  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        // colores del sistema (Material You) y modo claro/oscuro del dispositivo
        builder: (light, dark) => MaterialApp(
          title: 'Apuntes',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: appTheme(ColorScheme.fromSeed(seedColor: light?.primary ?? kAccent)),
          darkTheme: appTheme(ColorScheme.fromSeed(seedColor: dark?.primary ?? light?.primary ?? kAccent, brightness: Brightness.dark)),
          home: Library(root: root),
        ),
      );
}

/// Tema común: esquinas redondeadas parejas (10 / 14 / 18 / 26) en todo lo que flota.
ThemeData appTheme(ColorScheme cs) {
  RoundedRectangleBorder r(double v) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(v));
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    popupMenuTheme: PopupMenuThemeData(
      shape: r(18),
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black45,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: TextStyle(fontSize: 15, color: cs.onSurface),
    ),
    dialogTheme: DialogThemeData(
      shape: r(26),
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: cs.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 1.5)),
    ),
    snackBarTheme: SnackBarThemeData(shape: r(14), behavior: SnackBarBehavior.floating),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(10)),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(26))),
    ),
    chipTheme: ChipThemeData(shape: r(10)),
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

// ======================================================================
// Biblioteca: todos los cuadernos con su miniatura
// ======================================================================
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
  final thumbs = <String, PageData>{}; // primera página de cada cuaderno
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
    await _loadThumbs();
  }

  Future<void> _loadThumbs() async {
    for (final nb in index!.notebooks) {
      if (nb.pages.isEmpty) continue;
      final p = await store.loadPage(nb.pages.first.id);
      if (!mounted) return;
      setState(() => thumbs[nb.id] = p);
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
      pageBuilder: (_, __, ___) => NotebookScreen(store: store, index: index!, nb: nb, tools: tools),
      transitionsBuilder: (_, a, __, child) {
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
    if (nb.pages.isNotEmpty) {
      final p = await store.loadPage(nb.pages.first.id);
      if (mounted) setState(() => thumbs[nb.id] = p);
    }
  }

  Future<void> _create() async {
    final name = (await askText(context, 'Nuevo cuaderno', hint: 'Ej: Análisis II', ok: 'Crear'))?.trim();
    if (name == null || name.isEmpty) return;
    final page = PageData(newId('p'));
    await store.savePage(page);
    final nb = Notebook(newId('n'), name, [PageRef(page.id, todayTitle())], updated: DateTime.now().millisecondsSinceEpoch);
    index!.notebooks.add(nb);
    await store.saveIndex(index!);
    setState(() => thumbs[nb.id] = page);
    await _open(nb);
  }

  Future<void> _rename(Notebook nb) async {
    final n = (await askText(context, 'Renombrar cuaderno', initial: nb.name))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => nb.name = n);
    await store.saveIndex(index!);
  }

  Future<void> _duplicate(Notebook nb) async {
    final copy = Notebook(newId('n'), '${nb.name} (copia)', [], updated: DateTime.now().millisecondsSinceEpoch);
    for (final ref in nb.pages) {
      final p = await store.loadPage(ref.id);
      final dup = PageData.fromJson({...p.toJson(), 'id': newId('p')});
      await store.savePage(dup);
      copy.pages.add(PageRef(dup.id, ref.title));
      if (copy.pages.length == 1) thumbs[copy.id] = dup;
    }
    index!.notebooks.add(copy);
    await store.saveIndex(index!);
    setState(() {});
    _snack('Cuaderno duplicado');
  }

  Future<void> _delete(Notebook nb) async {
    if (!await confirmDelete(context, 'Borrar "${nb.name}"', 'Se borran sus ${nb.pages.length} páginas. No se puede deshacer.')) return;
    for (final p in nb.pages) {
      await store.deletePage(p.id);
    }
    setState(() {
      index!.notebooks.remove(nb);
      thumbs.remove(nb.id);
    });
    await store.saveIndex(index!);
  }

  void _snack(String m) => snack(context, m);

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
              child: Text(nb.name, style: Theme.of(ctx).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        exportPdfFlow(context, store, nb);
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
                  sliver: SliverToBoxAdapter(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Cuadernos', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text(
                        idx.notebooks.isEmpty
                            ? 'Creá el primero para empezar'
                            : '${idx.notebooks.length} ${idx.notebooks.length == 1 ? 'cuaderno' : 'cuadernos'} · mantené uno apretado para ver opciones',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                      ),
                    ]),
                  ),
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
                    delegate: SliverChildListDelegate([for (final nb in sorted) _card(nb, cs)]),
                  ),
                ),
            ]),
    );
  }

  Widget _card(Notebook nb, ColorScheme cs) {
    final thumb = thumbs[nb.id];
    final on = pressed == nb.id;
    final n = nb.pages.length;
    return GestureDetector(
      key: Key('nb-${nb.name}'),
      onTap: () => _open(nb),
      onLongPress: () => _options(nb),
      child: AnimatedScale(
        scale: on ? .95 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutQuart,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? cs.primary : cs.outlineVariant.withValues(alpha: .7), width: on ? 2 : 1),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: AspectRatio(
                  aspectRatio: kW / kSheetH,
                  child: Stack(children: [
                    Positioned.fill(
                      child: nb.pin != null
                          // bloqueado: no se muestra el contenido
                          ? Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Symbols.lock, size: 36, weight: 200, color: cs.onSurfaceVariant),
                            )
                          : thumb == null
                              ? Container(color: const Color(0xFFFFFEFB))
                              : RepaintBoundary(child: CustomPaint(painter: SheetThumbPainter(thumb))),
                    ),
                    if (nb.favorite)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: cs.surface.withValues(alpha: .9), shape: BoxShape.circle),
                          child: Icon(Symbols.star, key: Key('fav-${nb.id}'), size: 16, fill: 1, color: cs.primary),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(nb.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(
            '$n ${n == 1 ? 'página' : 'páginas'}${nb.updated > 0 ? ' · ${fmtDate(nb.updated)}' : ''}',
            maxLines: 1,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

