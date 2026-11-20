import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'editor.dart';
import 'model.dart';
import 'painters.dart';
import 'pdf_export.dart';
import 'pen_panel.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApuntesApp());
}

class ApuntesApp extends StatelessWidget {
  const ApuntesApp({super.key});
  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        // colores del sistema (Material You) y modo claro/oscuro del dispositivo
        builder: (light, dark) => MaterialApp(
          title: 'Apuntes',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: appTheme(ColorScheme.fromSeed(seedColor: light?.primary ?? kAccent)),
          darkTheme: appTheme(ColorScheme.fromSeed(seedColor: dark?.primary ?? light?.primary ?? kAccent, brightness: Brightness.dark)),
          home: const Library(),
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
// Diálogos compartidos
// ======================================================================
Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = '', String ok = 'Listo'}) {
  final c = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
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
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    ) ??
    false;

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

/// Exporta con un diálogo de progreso; después el sistema pregunta carpeta y nombre.
Future<void> exportPdfFlow(BuildContext context, Storage store, Notebook nb) async {
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
    final bytes = await buildNotebookPdf(store, nb, onProgress: (a, b) => progress.value = (a, b));
    nav.pop();
    final ok = await savePdf(bytes, nb.name);
    if (ok) messenger.showSnackBar(SnackBar(content: Text('PDF de "${nb.name}" guardado')));
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
  }
}

// ======================================================================
// Biblioteca: todos los cuadernos con su miniatura
// ======================================================================
class Library extends StatefulWidget {
  const Library({super.key});
  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  final store = Storage();
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

  List<Notebook> get sorted => [...index!.notebooks]..sort((a, b) => b.updated.compareTo(a.updated));

  Future<void> _open(Notebook nb) async {
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

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), width: 320));

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
                  child: thumb == null
                      ? Container(color: const Color(0xFFFFFEFB))
                      : RepaintBoundary(child: CustomPaint(painter: SheetThumbPainter(thumb))),
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

// ======================================================================
// Un cuaderno abierto: editor + lista de sus páginas
// ======================================================================
class NotebookScreen extends StatefulWidget {
  final Storage store;
  final NotesIndex index;
  final Notebook nb;
  final ToolState tools;
  const NotebookScreen({super.key, required this.store, required this.index, required this.nb, required this.tools});
  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> with WidgetsBindingObserver {
  Storage get store => widget.store;
  Notebook get nb => widget.nb;
  final scaffold = GlobalKey<ScaffoldState>();
  PageData? page;
  Timer? saveTimer, prefsTimer;
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final first = nb.pages.any((p) => p.id == nb.last) ? nb.last : (nb.pages.isEmpty ? null : nb.pages.first.id);
    if (first != null) {
      _open(first);
    } else {
      _addPage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _flush(); // al salir de la app, guardar ya
  }

  // ---------- guardado ----------
  void _pageChanged() {
    dirty = true;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _prefsChanged() {
    prefsTimer?.cancel();
    prefsTimer = Timer(const Duration(milliseconds: 500), () => store.savePrefs(widget.tools.toJson()));
  }

  Future<void> _flush() async {
    saveTimer?.cancel();
    saveTimer = null;
    final p = page;
    if (p != null && dirty) {
      dirty = false;
      nb.updated = DateTime.now().millisecondsSinceEpoch;
      await store.savePage(p);
      await store.saveIndex(widget.index);
    }
  }

  /// al volver atrás: guardar todo
  Future<void> _leave() async {
    await _flush();
    prefsTimer?.cancel();
    await store.savePrefs(widget.tools.toJson());
    await store.saveIndex(widget.index);
  }

  Future<void> _open(String id) async {
    if (page?.id == id) return;
    await _flush();
    final p = await store.loadPage(id);
    nb.last = id;
    unawaited(store.saveIndex(widget.index));
    if (mounted) setState(() => page = p);
  }

  // ---------- páginas ----------
  Future<void> _addPage() async {
    final p = PageData(newId('p'));
    await store.savePage(p);
    setState(() => nb.pages.add(PageRef(p.id, todayTitle())));
    nb.updated = DateTime.now().millisecondsSinceEpoch;
    await store.saveIndex(widget.index);
    await _open(p.id);
    _closeDrawer();
  }

  Future<void> _renamePage(PageRef p) async {
    final n = (await askText(context, 'Título de la página', initial: p.title))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => p.title = n);
    await store.saveIndex(widget.index);
  }

  Future<void> _deletePage(PageRef p) async {
    if (!await confirmDelete(context, 'Borrar "${p.title}"', 'Se borra la página con todo lo que tiene.')) return;
    await store.deletePage(p.id);
    setState(() => nb.pages.remove(p));
    await store.saveIndex(widget.index);
    if (p.id == page?.id) {
      saveTimer?.cancel();
      dirty = false;
      setState(() => page = null);
      if (nb.pages.isNotEmpty) {
        await _open(nb.pages.first.id);
      } else {
        await _addPage();
      }
    }
  }

  void _closeDrawer() {
    if (scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cur = nb.pages.where((p) => p.id == page?.id).firstOrNull;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (scaffold.currentState?.isDrawerOpen ?? false) {
          _closeDrawer();
          return;
        }
        await _leave();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        key: scaffold,
        drawer: _drawer(),
        body: SafeArea(
          child: page == null
              ? const Center(child: CircularProgressIndicator())
              : PageEditor(
                  key: ValueKey(page!.id),
                  page: page!,
                  tools: widget.tools,
                  title: cur?.title ?? '',
                  subtitle: nb.name,
                  onChanged: _pageChanged,
                  onPrefsChanged: _prefsChanged,
                  onMenu: () => scaffold.currentState?.openDrawer(),
                  onBack: () => Navigator.of(context).maybePop(),
                ),
        ),
      ),
    );
  }

  Widget _drawer() {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 4),
            child: Text(nb.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: cs.onSurface)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 12, 12),
            child: Text('${nb.pages.length} ${nb.pages.length == 1 ? 'página' : 'páginas'}', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _addPage,
                  icon: const Icon(Symbols.note_add, weight: 300),
                  label: const Text('Nueva página'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Exportar a PDF',
                onPressed: () async {
                  _closeDrawer();
                  await _flush();
                  if (mounted) await exportPdfFlow(context, store, nb);
                },
                icon: const Icon(Symbols.picture_as_pdf, weight: 300),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
              children: [
                for (final p in nb.pages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: ListTile(
                      selected: p.id == page?.id,
                      selectedTileColor: cs.secondaryContainer,
                      selectedColor: cs.onSecondaryContainer,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Icon(Symbols.description, weight: 300, fill: p.id == page?.id ? 1 : 0),
                      title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () async {
                        await _open(p.id);
                        _closeDrawer();
                      },
                      trailing: PopupMenuButton<String>(
                        icon: Icon(Symbols.more_vert, weight: 300, color: cs.onSurfaceVariant),
                        onSelected: (v) => v == 'rename' ? _renamePage(p) : _deletePage(p),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: _MenuRow(Symbols.edit, 'Renombrar')),
                          PopupMenuItem(value: 'delete', child: _MenuRow(Symbols.delete, 'Borrar', danger: true)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _MenuRow(this.icon, this.label, {this.danger = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = danger ? cs.error : cs.onSurfaceVariant;
    return Row(children: [
      Icon(icon, size: 20, weight: 300, color: c),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: danger ? cs.error : cs.onSurface)),
    ]);
  }
}
