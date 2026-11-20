import 'dart:async';

import 'package:flutter/material.dart';

import 'editor.dart';
import 'pen_panel.dart';
import 'model.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApuntesApp());
}

class ApuntesApp extends StatelessWidget {
  const ApuntesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Apuntes',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kAccent, surface: kPanel),
          scaffoldBackgroundColor: kDesk,
          useMaterial3: true,
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  final store = Storage();
  final tools = ToolState();
  final scaffold = GlobalKey<ScaffoldState>();
  NotesIndex? index;
  PageData? page;
  Timer? saveTimer;
  final collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _flush(); // al salir de la app, guardar ya
  }

  Future<void> _load() async {
    await store.init();
    tools.load(await store.loadPrefs());
    final idx = await store.loadIndex();
    setState(() => index = idx);
    final last = idx.find(idx.last) != null ? idx.last : _firstPageId();
    if (last != null) await _open(last);
  }

  String? _firstPageId() {
    for (final nb in index!.notebooks) {
      if (nb.pages.isNotEmpty) return nb.pages.first.id;
    }
    return null;
  }

  // ---------- guardado ----------
  Timer? prefsTimer;
  void _prefsChanged() {
    prefsTimer?.cancel();
    prefsTimer = Timer(const Duration(milliseconds: 500), () => store.savePrefs(tools.toJson()));
  }

  void _pageChanged() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  Future<void> _flush() async {
    saveTimer?.cancel();
    saveTimer = null;
    final p = page;
    if (p != null) await store.savePage(p);
  }

  Future<void> _saveIndex() => store.saveIndex(index!);

  Future<void> _open(String id) async {
    if (page?.id == id) return;
    if (saveTimer != null) await _flush();
    final p = await store.loadPage(id);
    index!.last = id;
    unawaited(_saveIndex());
    setState(() => page = p);
  }

  // ---------- cuadernos y páginas ----------
  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Future<String?> _ask(String title, {String initial = '', String hint = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Listo')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addNotebook() async {
    final name = (await _ask('Nuevo cuaderno', hint: 'Ej: Análisis II'))?.trim();
    if (name == null || name.isEmpty) return;
    final nb = Notebook(newId('n'), name, []);
    index!.notebooks.add(nb);
    await _addPage(nb);
  }

  Future<void> _addPage(Notebook nb) async {
    final p = PageData(newId('p'));
    await store.savePage(p);
    setState(() {
      nb.pages.add(PageRef(p.id, _today()));
      collapsed.remove(nb.id);
    });
    await _saveIndex();
    await _open(p.id);
    _closeDrawerIfNarrow();
  }

  Future<void> _renameNotebook(Notebook nb) async {
    final n = (await _ask('Nombre del cuaderno', initial: nb.name))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => nb.name = n);
    await _saveIndex();
  }

  Future<void> _deleteNotebook(Notebook nb) async {
    if (!await _confirm('¿Borrar "${nb.name}" y todas sus páginas?')) return;
    final hadCurrent = nb.pages.any((p) => p.id == page?.id);
    for (final p in nb.pages) {
      await store.deletePage(p.id);
    }
    setState(() => index!.notebooks.remove(nb));
    if (hadCurrent) await _afterDeleteCurrent();
    await _saveIndex();
  }

  Future<void> _renamePage(PageRef p) async {
    final n = (await _ask('Título de la página', initial: p.title))?.trim();
    if (n == null || n.isEmpty) return;
    setState(() => p.title = n);
    await _saveIndex();
  }

  Future<void> _deletePage(Notebook nb, PageRef p) async {
    if (!await _confirm('¿Borrar la página "${p.title}"?')) return;
    await store.deletePage(p.id);
    setState(() => nb.pages.remove(p));
    if (p.id == page?.id) await _afterDeleteCurrent();
    await _saveIndex();
  }

  Future<void> _afterDeleteCurrent() async {
    saveTimer?.cancel();
    saveTimer = null;
    setState(() => page = null);
    final first = _firstPageId();
    if (first != null) await _open(first);
  }

  void _closeDrawerIfNarrow() {
    if (scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final idx = index;
    final cur = idx?.find(page?.id);
    return Scaffold(
      key: scaffold,
      backgroundColor: kDesk,
      drawer: idx == null ? null : _drawer(idx),
      body: SafeArea(
        child: idx == null
            ? const Center(child: CircularProgressIndicator())
            : page == null
                ? _empty()
                : PageEditor(
                    key: ValueKey(page!.id),
                    page: page!,
                    tools: tools,
                    title: cur?.page.title ?? '',
                    subtitle: cur?.nb.name ?? '',
                    onChanged: _pageChanged,
                    onPrefsChanged: _prefsChanged,
                    onMenu: () => scaffold.currentState?.openDrawer(),
                  ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No hay páginas todavía', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _addNotebook, icon: const Icon(Icons.add), label: const Text('Crear cuaderno')),
          TextButton(onPressed: () => scaffold.currentState?.openDrawer(), child: const Text('Ver cuadernos')),
        ]),
      );

  Widget _drawer(NotesIndex idx) => Drawer(
        backgroundColor: kPanel,
        width: 320,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(children: [
                const Expanded(child: Text('Apuntes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                OutlinedButton.icon(onPressed: _addNotebook, icon: const Icon(Icons.add, size: 18), label: const Text('Cuaderno')),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                children: [for (final nb in idx.notebooks) ..._notebook(nb)],
              ),
            ),
          ]),
        ),
      );

  List<Widget> _notebook(Notebook nb) {
    final open = !collapsed.contains(nb.id);
    return [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => open ? collapsed.add(nb.id) : collapsed.remove(nb.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(children: [
            AnimatedRotation(
              turns: open ? 0 : -.25,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more, size: 20, color: Color(0xFF7A776E)),
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(nb.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            IconButton(onPressed: () => _addPage(nb), icon: const Icon(Icons.add, size: 20), tooltip: 'Nueva página'),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) => v == 'rename' ? _renameNotebook(nb) : _deleteNotebook(nb),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(value: 'delete', child: Text('Borrar cuaderno', style: TextStyle(color: Color(0xFFB42318)))),
              ],
            ),
          ]),
        ),
      ),
      if (open)
        for (final p in nb.pages)
          Padding(
            padding: const EdgeInsets.only(left: 22, bottom: 2),
            child: Material(
              color: p.id == page?.id ? const Color(0x1A2F5BD3) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  await _open(p.id);
                  _closeDrawerIfNarrow();
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        p.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.id == page?.id ? kAccent : kText,
                          fontWeight: p.id == page?.id ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF7A776E)),
                      onSelected: (v) => v == 'rename' ? _renamePage(p) : _deletePage(nb, p),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                        PopupMenuItem(value: 'delete', child: Text('Borrar', style: TextStyle(color: Color(0xFFB42318)))),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
          ),
      const SizedBox(height: 6),
    ];
  }
}
