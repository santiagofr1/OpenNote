import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/storage.dart';
import '../domain/domain.dart';
import '../rendering/ink_layers.dart';
import '../rendering/paper.dart';
import '../rendering/sheet_image_cache.dart';
import '../rendering/text_layout.dart';
import '../widgets/dialogs.dart';
import 'context_menu.dart';
import 'dock_layout.dart';
import 'format_bar.dart';
import 'history.dart';
import 'ink.dart';
import 'items_layer.dart';
import 'live_layer.dart';
import 'pen_panel.dart';
import 'pull_to_add.dart';
import 'selection.dart';
import 'selection_menu.dart';
import 'text_blocks.dart';
import 'toolbar.dart';
import 'touch_gestures.dart';
import 'viewport.dart';
import 'zoom_indicator.dart';

/// Hojas que se cargan de disco más allá del rango armado (de cada lado).
const kLoadMargin = 2;

/// Las hojas más lejos que esto del rango armado (de cada lado) se descargan (si se puede). Mayor que [kLoadMargin]:
/// así una hoja no se carga y se descarga en loop al scrollear de un lado a otro.
const kKeepMargin = 6;

/// Editor del cuaderno: la tira continua de hojas, con tinta, textos y elementos y su barra de herramientas.
///
/// Quién hace qué con cada puntero:
/// - lápiz (y mouse): dibuja, borra (botón del S Pen, punta goma o clic derecho) o selecciona;
/// - dedo: scrollea; dos dedos hacen zoom; uno quieto abre el menú de la hoja;
///   tirar hacia arriba al final agrega una hoja.
class PageEditor extends StatefulWidget {
  final NotebookDoc doc;
  final ToolState tools;
  final Storage store;
  final bool readOnly; // modo lectura: no se edita y no hay barra de herramientas
  final int initialSheet; // hoja a la que se va al abrir
  final ValueNotifier<int>? sheetNotifier; // hoja que se está viendo (la actualiza el editor al scrollear)
  final VoidCallback onChanged; // cambió el cuaderno (hay que guardarlo)
  final VoidCallback onPrefsChanged; // cambiaron las herramientas (prefs.json)
  const PageEditor({
    super.key,
    required this.doc,
    required this.tools,
    required this.store,
    this.readOnly = false,
    this.initialSheet = 0,
    this.sheetNotifier,
    required this.onChanged,
    required this.onPrefsChanged,
  });

  @override
  State<PageEditor> createState() => PageEditorState();
}

class PageEditorState extends State<PageEditor> with SingleTickerProviderStateMixin {
  NotebookDoc get doc => widget.doc;
  ToolState get ts => widget.tools;

  final scroll = ScrollController(), hscroll = ScrollController();
  final _versions = <String, ValueNotifier<int>>{}; // por hoja (id): repinta solo la tinta de esa hoja
  final liveTick = ValueNotifier(0); // repinta la capa en vivo
  // imágenes de la tinta quieta (ver [SheetImageCache]); a lo sumo [maxImages] a la vez, soltadas al descargar la hoja
  final _imgs = SheetImageCache();
  double _dpr = 1, _viewW = 800; // para el tamaño en píxeles de esas imágenes
  double _lastOff = 0; // para la dirección del scroll (prefetch de imágenes)
  int _scrollDir = 0, _prefKey = -1;
  Timer? _stillTimer;
  // elementos de cada hoja (por id) ya ordenados y agrupados en tandas; se rehacen solo cuando esa hoja cambia
  final _sheetRuns = <String, List<ZRun>>{};
  int _runsCount = -1;
  final history = History();
  final sel = Selection();
  late final texts = TextFields(onFocusChange: _rebuild, onLeftEmpty: _removeText, onEdited: _textEdited);
  late final pull = PullToAddSheet(vsync: this, onComplete: _addSheetFromPull);
  final touch = TouchTracker();
  late final stillPress = StillPressTimer(_onStillPress);
  SheetLayout layout = SheetLayout.initial;
  double get scale => layout.scale;

  // trazo o goma en curso: un solo puntero de lápiz/mouse a la vez
  int? pointer;
  Stroke? live;
  Offset? eraserAt;
  List<Stroke>? erased;

  bool _zoomPill = false;
  Timer? _zoomPillTimer;
  final _saveTimers = <String, Timer>{}; // textos y notas: se guarda al dejar de escribir
  final _viewportKey = GlobalKey(), _sheetKey = GlobalKey();

  // hojas armadas: las que se ven más un margen (ver [_calcRange]); las demás no tienen widgets
  ({int first, int last}) _range = (first: 0, last: 0);
  double _viewH = 800; // alto del visor
  final _stickyFocus = <String>{}; // notas con el teclado abierto: se quedan armadas aunque se scrolleen lejos

  // carga perezosa de hojas (ver [_syncLoaded] y [_unloadFar])
  final _loading = <String>{}; // hojas que se están leyendo de disco
  ({int first, int last})? _syncedRange; // rango para el que ya se pidieron las hojas
  int _syncedCount = -1;
  bool _syncPending = false;
  Timer? _unloadTimer, _retryTimer;

  /// Ids de los elementos seleccionados (lo usan los tests).
  Set<String> get selI => sel.items;

  @override
  void initState() {
    super.initState();
    texts.attach(doc);
    doc.addRenderListener(_onSheetTouched);
    doc.addLoadListener(_onSheetLoaded);
    scroll.addListener(_onScroll);
    _imgs.still = true; // abierto y sin mover: lo que falte de las visibles se genera ya
    _imgs.busy = () => pointer != null || live != null || erased != null || touch.pinching; // no generar con el lápiz en uso
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToSheet(widget.initialSheet, animate: false));
  }

  @override
  void didUpdateWidget(PageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // otro cuaderno en el mismo editor: lo de la anterior (deshacer, selección, campos) no sirve acá
    if (oldWidget.doc != widget.doc) {
      oldWidget.doc.removeRenderListener(_onSheetTouched);
      oldWidget.doc.removeLoadListener(_onSheetLoaded);
      doc.addRenderListener(_onSheetTouched);
      doc.addLoadListener(_onSheetLoaded);
      _versions.clear();
      _imgs.clear();
      _sheetRuns.clear();
      _stickyFocus.clear();
      _loading.clear();
      _syncedRange = null;
      texts.attach(doc);
      history.clear();
      sel.clear();
      pointer = null;
      live = null;
      erased = null;
      eraserAt = null;
      liveTick.value++;
    }
  }

  @override
  void dispose() {
    final pending = _saveTimers.values.any((t) => t.isActive);
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    if (pending) widget.onChanged(); // lo último que se escribió también se guarda
    texts.dispose();
    scroll.dispose();
    hscroll.dispose();
    pull.dispose();
    doc.removeRenderListener(_onSheetTouched);
    doc.removeLoadListener(_onSheetLoaded);
    _unloadTimer?.cancel();
    _retryTimer?.cancel();
    for (final v in _versions.values) {
      v.dispose();
    }
    _stillTimer?.cancel();
    _imgs.dispose();
    liveTick.dispose();
    _zoomPillTimer?.cancel();
    stillPress.cancel();
    super.dispose();
  }

  /// Versión de la tinta de la hoja [sheetId] (sube cuando algo de esa hoja cambia). Para los tests.
  @visibleForTesting
  ValueNotifier<int> inkVersionOf(String sheetId) => _verOf(sheetId);

  /// Caché de imágenes de la tinta (para los tests).
  @visibleForTesting
  SheetImageCache get imageCache => _imgs;

  /// La hoja se está dibujando con imagen en vez de trazos (para los tests).
  @visibleForTesting
  bool sheetUsesImage(String sheetId) => _imgs.usesImage(sheetId);

  ValueNotifier<int> _verOf(String sheetId) => _versions.putIfAbsent(sheetId, () => ValueNotifier(0));

  /// Repinta la tinta de la hoja [id]: sube su versión y suelta sus imágenes (hay que dibujarla vectorial hasta que quede quieta).
  void _bump(String id) {
    _imgs.invalidateSheet(id);
    _versions[id]?.value++;
  }

  /// Algo de la hoja [id] cambió (null: de todas): se repinta solo su tinta.
  void _onSheetTouched(String? id) {
    if (id == null) {
      _touchAll();
    } else {
      _sheetRuns.remove(id);
      _bump(id);
      if (!doc.isLoaded(id)) _requestSync(); // algo cayó en una hoja sin cargar: hay que cargarla
    }
  }

  /// Una hoja se cargó o se descargó: se arman (o sueltan) los campos de sus textos y se rearma.
  void _onSheetLoaded(String id, bool loaded) {
    texts.adoptNew();
    texts.releaseGone();
    if (!loaded) _imgs.dropSheet(id); // la hoja salió de memoria: sus imágenes también
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuild());
    } else {
      setState(() {});
    }
  }

  void _touchAll() {
    _sheetRuns.clear();
    _imgs.invalidateAll();
    for (final v in _versions.values) {
      v.value++;
    }
  }

  /// Repinta las hojas que toca el rectángulo [r] (sin que el cuaderno haya cambiado: ej. trazos que se ocultan al arrastrar).
  void _touchRect(Rect r) {
    for (var k = doc.sheetOfY(r.top); k <= doc.sheetOfY(r.bottom); k++) {
      _bump(doc.sheets[k].id);
    }
  }

  void _touchStrokes(Iterable<Stroke> ss) {
    for (final s in ss) {
      _touchRect(s.bounds);
    }
  }

  /// Hojas que se arman: las que se ven más un margen de un alto de visor arriba y abajo.
  ({int first, int last}) _calcRange() {
    final off = scroll.hasClients && scroll.position.hasPixels ? scroll.offset : 0.0;
    // sin scroll todavía (primer cuadro): se mira desde la hoja inicial, que es adonde se va a saltar
    final top = scroll.hasClients && scroll.position.hasPixels ? (off - kTopPad) / scale : widget.initialSheet * kSheetStep;
    final span = _viewH / scale;
    var first = doc.sheetOfY(top - span), last = doc.sheetOfY(top + 2 * span);
    // al menos una hoja más en el sentido del scroll: hace falta armada para generarle la imagen por adelantado
    if (_scrollDir > 0) {
      last = max(last, min(doc.sheetCount - 1, doc.sheetOfY(top + span) + 1));
    } else if (_scrollDir < 0) {
      first = min(first, max(0, doc.sheetOfY(top) - 1));
    }
    return (first: first, last: last);
  }

  /// Hojas que se ven ahora (índices, de la primera a la última).
  ({int first, int last}) _visibleSheets() {
    final off = scroll.hasClients && scroll.position.hasPixels ? scroll.offset : widget.initialSheet * kSheetStep * scale;
    final top = (off - kTopPad) / scale;
    return (first: doc.sheetOfY(top), last: doc.sheetOfY(top + _viewH / scale));
  }

  /// Le dice a la caché de imágenes qué hojas se ven y cuáles vienen en la dirección del scroll (la próxima y la
  /// siguiente), para que las vaya generando por adelantado (ver [SheetImageCache.prefetch]). Barato: solo recalcula
  /// si cambió la hoja visible o el sentido.
  void _updatePrefetch() => developer.Timeline.timeSync('ON updatePrefetch', _updatePrefetchImpl);

  void _updatePrefetchImpl() {
    if (!scroll.hasClients || !scroll.position.hasPixels) return;
    final off = scroll.offset;
    if ((off - _lastOff).abs() > .5) _scrollDir = off > _lastOff ? 1 : -1;
    _lastOff = off;
    final v = _visibleSheets();
    final key = (v.first * 100003 + v.last) * 4 + _scrollDir + 1 + doc.sheetCount * 7919 + doc.sheets[v.first].id.hashCode + doc.sheets[v.last].id.hashCode * 31;
    if (key == _prefKey) return;
    _prefKey = key;
    final plan = SheetImageCache.prefetchPlan(first: v.first, last: v.last, dir: _scrollDir, count: doc.sheetCount);
    final ids = [for (final k in plan) doc.sheets[k].id];
    final vis = {for (var k = v.first; k <= v.last; k++) doc.sheets[k].id};
    // protegidas: el plan y una hoja detrás (la que se acaba de pasar: si se vuelve, está lista)
    final behind = _scrollDir == 0 ? -1 : (_scrollDir > 0 ? v.first - 1 : v.last + 1);
    _imgs.protectedSheets = {...ids, if (behind >= 0 && behind < doc.sheetCount) doc.sheets[behind].id};
    _imgs.prefetch(ids, dir: _scrollDir);
    _imgs.releaseOutsideWindow(); // las imágenes de las hojas que quedaron lejos se sueltan (ver SheetImageCache)
    // visibles: las que no se habían dibujado (o tenían franjas a medias sin repintar) pasan a mostrarse; sus franjas
    // que están en pantalla se generan primero
    final top = (off - kTopPad) / scale, bottom = top + _viewH / scale;
    final fr = <String, (double, double)>{
      for (var k = v.first; k <= v.last; k++)
        doc.sheets[k].id: (((top - k * kSheetStep) / kSheetH).clamp(0.0, 1.0), ((bottom - k * kSheetStep) / kSheetH).clamp(0.0, 1.0)),
    };
    _imgs.setVisible(vis, fractions: fr);
  }

  /// Un rato sin scroll: lo que falte de las hojas visibles se genera ya (sin presupuesto por cuadro).
  void _markStill() {
    _stillTimer = null;
    _imgs.still = true;
    _imgs.kick();
  }

  /// Para el benchmark: cómo se están dibujando las hojas que se ven ahora (hay alguna con trazos vectoriales de una
  /// tanda que valía una imagen) y el contador de actividad de generación de imágenes.
  @visibleForTesting
  ({bool vector, int activity, int jobs}) get imageFrameState {
    final v = _visibleSheets();
    var vec = false;
    for (var k = v.first; k <= v.last; k++) {
      for (final e in _imgs.entriesOf(doc.sheets[k].id)) {
        if (!e.cacheable) continue;
        if (e.mode == InkPaintMode.vector) vec = true;
      }
    }
    return (vector: vec, activity: _imgs.activity, jobs: _imgs.jobsStarted);
  }

  /// Zona de la página que se ve (más un margen), para no pintar de más en la capa en vivo.
  Rect _visiblePage() {
    final off = scroll.hasClients && scroll.position.hasPixels ? scroll.offset : 0.0;
    final top = (off - kTopPad) / scale, span = _viewH / scale;
    return Rect.fromLTRB(-1e6, top - span, 1e6, top + 2 * span);
  }

  /// Al scrollear solo se rearma el cuaderno si cambió el rango de hojas armadas.
  void _onScroll() => developer.Timeline.timeSync('ON onScroll', _onScrollImpl);

  void _onScrollImpl() {
    _imgs.still = false;
    _stillTimer?.cancel();
    _stillTimer = Timer(const Duration(milliseconds: 120), _markStill);
    _scheduleVisibleSheet();
    _updatePrefetch();
    if (_calcRange() == _range) return;
    _scheduleUnload();
    void rebuild() {
      if (!mounted || _calcRange() == _range) return;
      developer.Timeline.timeSync('ON rebuild-por-rango', () {
        setState(() {});
        if (sel.moving) liveTick.value++; // la capa en vivo dibuja solo lo visible
      });
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuild()); // en pleno armado no se puede
    } else {
      rebuild();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ---------------- carga perezosa de hojas ----------------
  /// Pide cargar las hojas del rango armado más [kLoadMargin] de cada lado (en el próximo cuadro).
  void _requestSync() {
    if (_syncPending || !mounted) return;
    if (_syncedRange == _range && _syncedCount == doc.sheetCount && !doc.hasMisplaced) return;
    _syncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending = false;
      if (mounted) _syncLoaded();
    });
  }

  void _syncLoaded() => developer.Timeline.timeSync('ON syncLoaded', _syncLoadedImpl);

  void _syncLoadedImpl() {
    _syncedRange = _range;
    _syncedCount = doc.sheetCount;
    final n = doc.sheetCount;
    final from = max(0, _range.first - kLoadMargin), to = min(n - 1, _range.last + kLoadMargin);
    // las del rango se piden de a una (la visible no espera a las del margen); las del margen, juntas
    final inRange = <String>[], margin = <String>[...doc.misplacedSheets];
    for (var k = from; k <= to; k++) {
      if (doc.isLoadedAt(k)) continue;
      (k >= _range.first && k <= _range.last ? inRange : margin).add(doc.sheets[k].id);
    }
    for (final batch in [for (final id in inRange) [id], margin]) {
      final ids = [for (final id in batch) if (!_loading.contains(id) && !doc.isLoaded(id)) id];
      if (ids.isEmpty) continue;
      _loading.addAll(ids);
      widget.store.loadSheets(doc, ids).then((_) {}, onError: (Object e) {
        developer.log('no se pudieron cargar las hojas $ids: $e', name: 'editor', level: 900);
        _retryTimer ??= Timer(const Duration(seconds: 2), () {
          _retryTimer = null;
          _syncedRange = null;
          _requestSync();
        });
      }).whenComplete(() {
        _loading.removeAll(ids);
        if (mounted) _scheduleUnload();
      });
    }
    _scheduleUnload();
  }

  /// Hojas cargadas lejos del rango armado (más de [kKeepMargin] hojas).
  List<String> _farLoaded() => [
        for (var k = 0; k < doc.sheetCount; k++)
          if (doc.isLoadedAt(k) && (k < _range.first - kKeepMargin || k > _range.last + kKeepMargin)) doc.sheets[k].id
      ];

  /// Un rato después de scrollear (y de que se guarde), suelta las hojas lejanas. Se reintenta unas veces si no se pudo.
  void _scheduleUnload({int tries = 0}) {
    _unloadTimer?.cancel();
    if (!mounted || tries > 20 || _farLoaded().isEmpty) return;
    _unloadTimer = Timer(Duration(milliseconds: tries == 0 ? 1200 : 2500), () => _unloadFar(tries));
  }

  Future<void> _unloadFar(int tries) async {
    if (!mounted) return;
    final far = developer.Timeline.timeSync('ON farLoaded', _farLoaded);
    if (far.isEmpty) return;
    final r = await widget.store.unloadSheets(doc, far, canUnload: (id) => mounted && !_pinnedSheets().contains(id));
    if (!mounted) return;
    if (r.healed.isNotEmpty) _changed(); // lo que no coincidía con el disco: que se guarde
    if (r.unloaded.length < far.length) _scheduleUnload(tries: tries + 1); // algo no se pudo (sucia, guardando...)
  }

  /// Hojas que NO se pueden descargar: con selección (o arrastre), texto o nota con foco, trazo o borrador en curso,
  /// audios, elementos caídos en una hoja sin cargar, y las que tocan las acciones del historial (deshacer / rehacer
  /// las necesitan en memoria). Las hojas con cambios sin guardar las protege la `Storage`.
  Set<String> _pinnedSheets() {
    final out = <String>{...doc.misplacedSheets};
    void byId(String id) {
      final s = doc.sheetIdOfElementId(id);
      if (s != null) out.add(s);
    }

    sel.allIds.forEach(byId);
    final f = texts.focused;
    if (f != null) byId(f.block.id);
    _stickyFocus.forEach(byId);
    for (final s in [?live, ...?erased]) {
      out.addAll(doc.sheetIdsOfRect(s.bounds));
    }
    for (final it in doc.items.values) {
      if (it.type == 'audio') byId(it.id);
    }
    out.addAll(history.sheetIds(doc));
    return out;
  }

  /// Corre [then] cuando las hojas [ids] estén cargadas (las pide si hace falta).
  void _whenLoaded(Iterable<String> ids, VoidCallback then) {
    final need = [for (final id in ids.toSet()) if (!doc.isLoaded(id)) id];
    if (need.isEmpty) {
      then();
      return;
    }
    widget.store.loadSheets(doc, need).then((_) {
      if (mounted && need.every(doc.isLoaded)) then();
    }, onError: (Object e) => developer.log('no se pudieron cargar $need: $e', name: 'editor', level: 900));
  }

  bool _loadedAt(double y) => doc.isLoadedAt(doc.sheetOfY(y));

  void _changed() => widget.onChanged();

  void _saveSoon(String id, Duration delay) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] = Timer(delay, _changed);
  }

  Offset _toPage(Offset local) => local / scale;

  /// Agrega hojas si [y] quedó cerca del final del cuaderno.
  void _growIfNeeded(double y) {
    if (y > doc.h - 250) setState(() => doc.growFor(y));
  }

  // ---------------- lápiz: dibujar, borrar, seleccionar ----------------
  void _down(PointerDownEvent e) {
    if (widget.readOnly || pointer != null) return;
    final action = penActionFor(e, ts.tool);
    if (action == null) return;
    final p = _toPage(e.localPosition);
    if (!_loadedAt(p.dy)) {
      _requestSync(); // la hoja todavía no se leyó de disco: no se escribe encima hasta que cargue
      return;
    }
    pointer = e.pointer;
    switch (action) {
      case PenAction.erase:
        _startErase(p);
      case PenAction.select:
        _selDown(p);
      case PenAction.draw:
        final pr = ts.current;
        live = Stroke(newId('s'), ts.tool == Tool.hl ? 'hl' : pr.tip, pr.color, pr.width, [], pr.opacity);
        appendInkPoint(live!, p, pressureOf(e));
        liveTick.value++;
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != pointer) return;
    final p = _toPage(e.localPosition);
    if (sel.moving) {
      _selDrag(p);
      return;
    }
    if (sel.bandA != null) {
      sel.bandB = p;
      liveTick.value++;
      return;
    }
    final s = live;
    if (s != null && wantsEraser(e)) {
      // apretó el botón a mitad del trazo: lo que venía queda, y sigue borrando
      live = null;
      _commitStroke(s);
      _startErase(p);
      return;
    }
    if (erased != null) {
      _eraseAt(p);
      eraserAt = p;
    } else if (s != null) {
      appendInkPoint(s, p, pressureOf(e));
    }
    liveTick.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != pointer) return;
    pointer = null;
    if (sel.moving) {
      _selDrop();
      return;
    }
    final band = sel.band;
    if (band != null) {
      sel.selectIn(doc, band, capture: sel.capture);
      sel.bandA = sel.bandB = null;
      setState(() {});
      liveTick.value++;
      return;
    }
    if (erased != null) {
      if (erased!.isNotEmpty) _pushUndo(EditAction(removed: erased!));
      erased = null;
      eraserAt = null;
      liveTick.value++;
      return;
    }
    final s = live;
    live = null;
    liveTick.value++;
    // cancelado por el sistema (ej. lo tomó como palma) apenas empezó: se descarta
    if (s == null || (e is PointerCancelEvent && s.n < 3)) return;
    _commitStroke(s);
  }

  /// El trazo terminado pasa a la página (suavizado), con su deshacer.
  void _commitStroke(Stroke s) {
    if (s.n < 2) return;
    s.smooth();
    s.z = doc.nextZ(); // arriba de todo
    doc.strokes[s.id] = s; // avisa a las hojas que toca
    _pushUndo(EditAction(added: [s]));
    _growIfNeeded(s.bounds.bottom);
    _changed();
  }

  void _startErase(Offset p) {
    erased = [];
    _eraseAt(p);
    eraserAt = p;
    liveTick.value++;
  }

  void _eraseAt(Offset pt) {
    final hits = strokesHit(doc, pt, ts.eraserRadius);
    if (hits.isEmpty) return;
    for (final s in hits) {
      doc.strokes.remove(s.id);
    }
    erased!.addAll(hits); // (cada trazo sacado ya avisó a sus hojas)
    _changed();
  }

  // ---------------- deshacer ----------------
  void _pushUndo(EditAction a) {
    history.push(a);
    setState(() {});
  }

  void _undoRedo({required bool undo}) {
    final peek = history.peek(undo: undo);
    if (peek == null) return;
    // las hojas del historial están fijadas en memoria; si por algún motivo falta alguna, se carga antes
    final ids = peek.sheetIds(doc);
    if (!ids.every(doc.isLoaded)) {
      _whenLoaded(ids, () => _undoRedo(undo: undo));
      return;
    }
    final a = undo ? history.undo() : history.redo();
    if (a == null) return;
    a.apply(doc, undo: undo, putText: texts.put);
    _clearSel();
    _touchAll();
    _changed();
    setState(() {});
  }

  // ---------------- selección ----------------
  void _clearSel() {
    if (sel.isEmpty && sel.bandA == null) return;
    sel.clear();
    if (mounted) setState(() {});
    liveTick.value++;
  }

  /// Lápiz abajo con "seleccionar": dentro de la selección la mueve; afuera estira un rectángulo nuevo.
  void _selDown(Offset p) {
    final r = sel.bounds(doc);
    if (r != null && r.inflate(12).contains(p)) {
      sel.startDrag(doc, p);
      _touchStrokes(sel.strokesOf(doc)); // oculta los seleccionados de la capa fija
      setState(() {});
      return;
    }
    _clearSel();
    sel.bandA = sel.bandB = p;
    liveTick.value++;
  }

  void _selDrag(Offset p) {
    final drag = sel.drag!;
    final d = drag.delta = p - drag.from;
    setState(() {
      drag.textOrig.forEach((id, o) {
        final t = doc.texts[id];
        if (t != null) {
          doc.markDirtyElement(t); // hoja de antes y de después: puede guardarse a mitad del arrastre
          t.x = o.dx + d.dx;
          t.y = o.dy + d.dy;
          doc.markDirtyElement(t);
        }
      });
      drag.itemOrig.forEach((id, o) {
        final it = doc.items[id];
        if (it != null) {
          doc.markDirtyElement(it);
          it.x = o.dx + d.dx;
          it.y = o.dy + d.dy;
          doc.markDirtyElement(it);
        }
      });
    });
    liveTick.value++;
  }

  void _selDrop() {
    final drag = sel.drag!, d = drag.delta;
    sel.drag = null;
    if (d.distance < .5) {
      // fue un toque: nada se movió
      _touchStrokes(sel.strokesOf(doc));
      setState(() {});
      return;
    }
    // si algo va a caer en una hoja sin cargar, se deshace el movimiento (y se pide cargarla): nada se pierde
    var lands = true;
    for (final s in sel.strokesOf(doc)) {
      lands &= _loadedAt(s.bounds.top + d.dy);
    }
    for (final id in drag.textOrig.keys) {
      final t = doc.texts[id];
      if (t != null) lands &= _loadedAt(t.y);
    }
    for (final id in drag.itemOrig.keys) {
      final it = doc.items[id];
      if (it != null) lands &= _loadedAt(it.y);
    }
    if (!lands) {
      drag.textOrig.forEach((id, o) {
        final t = doc.texts[id];
        if (t == null) return;
        doc.markDirtyElement(t);
        t.x = o.dx;
        t.y = o.dy;
        doc.markDirtyElement(t);
      });
      drag.itemOrig.forEach((id, o) {
        final it = doc.items[id];
        if (it == null) return;
        doc.markDirtyElement(it);
        it.x = o.dx;
        it.y = o.dy;
        doc.markDirtyElement(it);
      });
      _touchStrokes(sel.strokesOf(doc));
      _requestSync();
      setState(() {});
      liveTick.value++;
      return;
    }
    final removed = <Stroke>[], added = <Stroke>[];
    for (final id in sel.strokes) {
      final s = doc.strokes.remove(id);
      if (s == null) continue;
      final m = s.moved(d);
      removed.add(s);
      added.add(m);
      doc.strokes[id] = m;
    }
    final textBefore = <String, TextBlock?>{}, textAfter = <String, TextBlock?>{};
    drag.textOrig.forEach((id, o) {
      final t = doc.texts[id];
      if (t == null) return;
      doc.markDirtyElement(t);
      t.y = max(0.0, doc.snapTextY(t.y)); // que caiga sobre el renglón de su hoja
      t.x = t.x.clamp(0.0, kW - 60);
      doc.markDirtyElement(t);
      textBefore[id] = t.copy(d: o - Offset(t.x, t.y));
      textAfter[id] = t.copy();
    });
    final itemBefore = <String, Item?>{}, itemAfter = <String, Item?>{};
    drag.itemOrig.forEach((id, o) {
      final it = doc.items[id];
      if (it == null) return;
      itemBefore[id] = it.copy(d: o - Offset(it.x, it.y));
      itemAfter[id] = it.copy();
    });
    _pushUndo(EditAction(
        removed: removed,
        added: added,
        textBefore: textBefore,
        textAfter: textAfter,
        itemBefore: itemBefore,
        itemAfter: itemAfter));
    final r = sel.bounds(doc);
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  void _copySel() {
    final c = ts.clipboard;
    c.strokes = sel.strokesOf(doc);
    c.texts = [for (final t in sel.textsOf(doc)) t.copy()];
    c.items = [for (final it in sel.itemsOf(doc)) it.copy()];
    setState(() {});
  }

  void _deleteSel() {
    final removed = sel.strokesOf(doc);
    final textBefore = {for (final t in sel.textsOf(doc)) t.id: t.copy()};
    final itemBefore = {for (final it in sel.itemsOf(doc)) it.id: it.copy()};
    for (final s in removed) {
      doc.strokes.remove(s.id);
    }
    for (final id in textBefore.keys) {
      texts.put(id, null);
    }
    for (final id in itemBefore.keys) {
      doc.items.remove(id);
    }
    _pushUndo(EditAction(
      removed: removed,
      textBefore: textBefore,
      textAfter: absent(textBefore.keys),
      itemBefore: itemBefore,
      itemAfter: absent(itemBefore.keys),
    ));
    _clearSel();
    _changed();
  }

  /// Pega copias (con ids nuevos) corridas [d] y las deja seleccionadas.
  void _insert(List<Stroke> strokes, List<TextBlock> textBlocks, Offset d, List<Item> items) {
    // el destino tiene que estar cargado: si no, se carga y se vuelve a intentar
    final target = {
      for (final s in strokes) doc.sheetOfY(s.bounds.top + d.dy),
      for (final t in textBlocks) doc.sheetOfY(max(0.0, t.y + d.dy)),
      for (final it in items) doc.sheetOfY(it.y + d.dy),
    };
    if (target.any((k) => !doc.isLoadedAt(k))) {
      _whenLoaded([for (final k in target) doc.sheets[k].id], () => _insert(strokes, textBlocks, d, items));
      return;
    }
    final newStrokes = [for (final s in strokes) s.moved(d, id: newId('s'))];
    final newItems = [for (final it in items) it.copy(id: newId('i'), d: d)];
    final newTexts = [
      for (final t in textBlocks) t.copy(id: newId('t'), d: Offset((t.x + d.dx).clamp(0.0, kW - 60) - t.x, max(0.0, t.y + d.dy) - t.y))
    ];
    // las copias quedan arriba de todo, en el mismo orden que tenían entre sí
    doc.stackOnTop([...newStrokes, ...newTexts, ...newItems]);
    for (final it in newItems) {
      doc.items[it.id] = it;
    }
    for (final s in newStrokes) {
      doc.strokes[s.id] = s;
    }
    for (final t in newTexts) {
      texts.put(t.id, t);
    }
    _pushUndo(EditAction(
      added: newStrokes,
      textBefore: absent(newTexts.map((t) => t.id)),
      textAfter: {for (final t in newTexts) t.id: t.copy()},
      itemBefore: absent(newItems.map((it) => it.id)),
      itemAfter: {for (final it in newItems) it.id: it.copy()},
    ));
    if (ts.tool != Tool.select) _setTool(Tool.select);
    sel.replace(
      strokes: newStrokes.map((s) => s.id),
      texts: newTexts.map((t) => t.id),
      items: newItems.map((it) => it.id),
    );
    final r = sel.bounds(doc);
    if (r != null) _growIfNeeded(r.bottom);
    _changed();
    setState(() {});
  }

  /// Menú "Orden": mueve la selección en el orden de dibujo (con deshacer).
  void _reorderSel(ZMove m) {
    final ch = doc.reorder(sel.allIds, m, _rectOf);
    if (ch == null) return;
    _pushUndo(EditAction(zBefore: ch.before, zAfter: ch.after)); // el cambio de z ya avisó a sus hojas
    liveTick.value++;
    _changed();
  }

  Rect _rectOf(Layered e) => switch (e) {
        Stroke s => s.bounds,
        Item it => it.rect,
        TextBlock t => textRect(t, doc.lineAt(t.y)),
        _ => Rect.zero,
      };

  void _duplicateSel() => _insert(sel.strokesOf(doc), sel.textsOf(doc), const Offset(30, 30), sel.itemsOf(doc));

  /// Pegar desde la barra: si lo copiado está a la vista, corrido; si no, arriba de lo que se ve.
  void _paste() {
    final c = ts.clipboard;
    final r = clipboardBounds(c);
    if (r == null) return;
    final top = max(0.0, (scroll.offset - kTopPad) / scale);
    final bottom = top + scroll.position.viewportDimension / scale;
    final d = (r.top > top && r.top < bottom - 60) ? const Offset(30, 30) : Offset(90 - r.left, top + 60 - r.top);
    _insert(c.strokes, c.texts, d, c.items);
  }

  /// Pegar desde el menú de la hoja: la esquina de lo copiado va a [p].
  void _pasteAt(Offset p) {
    final c = ts.clipboard;
    final r = clipboardBounds(c);
    if (r == null) return;
    _insert(c.strokes, c.texts, p - r.topLeft, c.items);
  }

  // ---------------- texto ----------------
  void _removeText(String id) {
    if (!mounted) return;
    setState(() => texts.put(id, null));
    _changed();
  }

  void _tapPage(TapUpDetails d) {
    if (ts.tool != Tool.text) return;
    if (texts.anyFocused) {
      FocusScope.of(context).unfocus(); // primer toque afuera: solo cierra el texto
      return;
    }
    _createTextAt(_toPage(d.localPosition));
  }

  void _createTextAt(Offset p) {
    if (!_loadedAt(p.dy)) {
      _requestSync();
      return;
    }
    final x = p.dx.clamp(16.0, kW - 120);
    var y = max(0.0, doc.snapTextY(p.dy, floor: true)); // el renglón de esa hoja
    // en el espacio entre hojas (o sin lugar para un renglón): a la siguiente
    if (y % kSheetStep > kSheetH - doc.lineAt(y) && y ~/ kSheetStep < doc.sheetCount - 1) {
      y = doc.snapTextY((y ~/ kSheetStep + 1) * kSheetStep, floor: true);
    }
    _placeText(x, y);
  }

  /// Un bloque nuevo y vacío en ([x], [y]) (y ya sobre el renglón), con el foco y el teclado.
  void _placeText(double x, double y) {
    final t = TextBlock(newId('t'), x.roundToDouble(), y, (kW - x - 30).roundToDouble(), '')..z = doc.nextZ();
    setState(() => texts.put(t.id, t));
    texts.editor(t.id)?.focusAt(0, 0);
    showKeyboard();
    _growIfNeeded(y + doc.lineAt(y));
    _changed();
  }

  /// El tecladito de la barra: renglón nuevo debajo de lo último que se ve en la hoja visible
  /// (o en el primer renglón de la parte visible si no hay nada).
  void _newTextAtVisible() {
    final k = visibleSheet, sheetTop = k * kSheetStep, line = doc.lineAt(sheetTop + 1);
    if (!doc.isLoadedAt(k)) {
      _requestSync(); // la hoja que se ve todavía se está leyendo
      return;
    }
    final vh = scroll.hasClients ? scroll.position.viewportDimension / scale : 600 / scale;
    final top = scroll.hasClients ? max(0.0, (scroll.offset - kTopPad) / scale) : sheetTop;
    final region = Rect.fromLTRB(0, max(top, sheetTop), kW, min(top + vh, sheetTop + kSheetH));
    double? bottom;
    void see(Rect r) {
      if (r.overlaps(region)) bottom = max(bottom ?? r.bottom, r.bottom);
    }

    for (final s in doc.strokes.values) {
      see(s.bounds);
    }
    for (final t in doc.texts.values) {
      see(textRect(t, doc.lineAt(t.y)));
    }
    for (final it in doc.items.values) {
      see(it.rect);
    }
    // el renglón de abajo de lo último (se sube un renglón menos un pelo: queda en el más cercano hacia abajo)
    var y = bottom != null
        ? doc.snapTextY(bottom! + line - 0.01, floor: true)
        : doc.snapTextY(max(region.top + line * .5, sheetTop + mmToUnits(kTopMarginMm) - line) + line - 0.01, floor: true);
    if (y - sheetTop > kSheetH - line && k < doc.sheetCount - 1) {
      y = doc.snapTextY((k + 1) * kSheetStep + 1, floor: false); // no entra: a la hoja siguiente
    }
    _placeText(mmToUnits(kMarginMm) + 10, y);
    if (scroll.hasClients && y + line > region.bottom) {
      final to = (y * scale + kTopPad - scroll.position.viewportDimension * .4).clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(to, duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuart);
    }
  }

  /// Tocar el tecladito estando en modo texto: vuelve a abrir el teclado en el último bloque escrito.
  void _reopenKeyboard() {
    final id = texts.lastEdited;
    if (id != null && doc.texts.containsKey(id)) {
      texts.focusEnd(id);
    } else {
      _newTextAtVisible();
    }
  }

  void _textEdited(TextBlock t) {
    // estimación de renglones (70 letras por renglón) para agregar hojas a tiempo
    var lines = 0;
    for (final p in t.body.paras) {
      lines += 1 + p.length ~/ 70;
    }
    _growIfNeeded(t.y + lines * doc.lineAt(t.y));
    _saveSoon(t.id, const Duration(milliseconds: 300));
  }

  // ---------------- herramientas ----------------
  void _setTool(Tool t) {
    if (t != Tool.select) _clearSel();
    setState(() => ts.tool = t);
    if (t != Tool.text) FocusScope.of(context).unfocus();
  }

  void _toolTap(Tool t) {
    if (t == Tool.text) {
      if (ts.tool == Tool.text) {
        _reopenKeyboard();
      } else {
        _setTool(t);
        _newTextAtVisible();
        widget.onPrefsChanged();
      }
      return;
    }
    if (ts.tool == t && ts.drawing) {
      _openPanel(); // tocar de nuevo la herramienta elegida abre sus opciones
      return;
    }
    _setTool(t);
    widget.onPrefsChanged();
  }

  Future<void> _openPanel() async {
    final align = switch (ts.dock) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.topCenter
    };
    await showPenPanel(context, ts, () {
      setState(() {});
      widget.onPrefsChanged();
    }, align);
    if (mounted) setState(() {});
  }

  /// Colores y grosor: desde texto/seleccionar, vuelve al lápiz.
  void _openPanelForDrawing() {
    if (!ts.drawing) _setTool(Tool.pen);
    _openPanel();
  }

  void _pickQuick(String c) {
    if (!ts.drawing) _setTool(Tool.pen);
    setState(() => ts.pickColor(c));
    widget.onPrefsChanged();
  }

  // ---------------- hoja nueva tirando ----------------
  void _addSheetFromPull() {
    final oldH = doc.h;
    setState(doc.addSheet);
    _changed();
    // lleva a la hoja nueva
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll.animateTo(min(scroll.position.maxScrollExtent, (oldH + kGap) * scale),
          duration: const Duration(milliseconds: 420), curve: Curves.easeOutQuart);
    });
  }

  // ---------------- dedos: zoom y menú de la hoja ----------------
  Offset get _scrollOffset => Offset(hscroll.hasClients ? hscroll.offset : 0, scroll.hasClients ? scroll.offset : 0);

  void _flashZoom() {
    _zoomPillTimer?.cancel();
    stillPress.cancel();
    setState(() => _zoomPill = true);
    _zoomPillTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _zoomPill = false);
    });
  }

  /// Cambia el zoom dejando quieto el punto [focal] del visor (el centro si es null).
  void _setZoom(double z, [Offset? focal]) {
    z = z.clamp(.5, 4.0);
    if ((z - ts.zoom).abs() < .001) return;
    final f = focal ??
        Offset(hscroll.hasClients ? hscroll.position.viewportDimension / 2 : 0,
            scroll.hasClients ? scroll.position.viewportDimension / 2 : 0);
    final anchor = layout.toPage(f, _scrollOffset);
    setState(() => ts.zoom = z);
    _flashZoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final to = layout.scrollFor(anchor, f); // con la escala nueva
      if (hscroll.hasClients) hscroll.jumpTo(to.dx.clamp(0.0, hscroll.position.maxScrollExtent));
      if (scroll.hasClients) scroll.jumpTo(to.dy.clamp(0.0, scroll.position.maxScrollExtent));
    });
  }

  void _touchDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touch.down(e.pointer, e.position);
    if (touch.length == 1 && pointer == null) {
      stillPress.start(e.position);
    } else {
      stillPress.cancel(); // segundo dedo: es zoom, no menú
    }
    // dos dedos = pellizco (salvo que el zoom esté fijado o se esté escribiendo con el lápiz)
    if (touch.length == 2 && !ts.zoomLocked && pointer == null) {
      touch.startPinch(ts.zoom);
      pull.cancel();
      setState(() {});
    }
  }

  void _touchMove(PointerMoveEvent e) {
    if (!touch.tracks(e.pointer)) return;
    touch.move(e.pointer, e.position);
    stillPress.moved(e.position);
    final p = touch.pinch();
    if (p == null) return;
    final box = _viewportKey.currentContext!.findRenderObject() as RenderBox;
    _setZoom(p.zoom, box.globalToLocal(p.focal));
  }

  void _touchUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touch.up(e.pointer);
    stillPress.cancel();
    if (touch.pinching && touch.length < 2) {
      setState(() => touch.pinching = false);
      widget.onPrefsChanged();
    }
    if (touch.count == 0) pull.cancel(); // soltó antes de completar: vuelve
  }

  void _toggleZoomLock() {
    setState(() => ts.zoomLocked = !ts.zoomLocked);
    HapticFeedback.selectionClick();
    _flashZoom();
    widget.onPrefsChanged();
  }

  /// Un dedo quieto sobre la hoja: menú contextual (si no se está scrolleando ni escribiendo).
  void _onStillPress(Offset g) {
    if (!mounted || touch.pinching || touch.length != 1 || pointer != null) return;
    if (scroll.hasClients && scroll.position.isScrollingNotifier.value) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(g);
    if (!(Offset.zero & box.size).contains(local)) return;
    _sheetMenu(g, _toPage(local));
  }

  Future<void> _sheetMenu(Offset global, Offset p) async {
    HapticFeedback.mediumImpact();
    final v = await showSheetMenu(
      context,
      global,
      canPaste: !ts.clipboard.isEmpty,
      canSelectAll: !doc.isEmpty,
      canResetZoom: !ts.zoomLocked && (ts.zoom - 1).abs() > .01,
    );
    if (!mounted) return;
    switch (v) {
      case SheetMenuAction.paste:
        _pasteAt(p);
      case SheetMenuAction.text:
        _setTool(Tool.text);
        _createTextAt(p);
      case SheetMenuAction.selectAll:
        _setTool(Tool.select);
        setState(() => sel.selectAll(doc));
        liveTick.value++;
      case SheetMenuAction.addSheet:
        setState(doc.addSheet);
        _changed();
      case SheetMenuAction.zoomToWidth:
        _setZoom(1);
        widget.onPrefsChanged();
      case null:
        break;
    }
  }

  // ---------------- lo que usa la pantalla del cuaderno ----------------
  /// Centro de lo que se está viendo, en coordenadas de la página.
  Offset get viewCenter {
    final vw = hscroll.hasClients ? hscroll.position.viewportDimension : kW * scale;
    final vh = scroll.hasClients ? scroll.position.viewportDimension : 600.0;
    final c = layout.toPage(Offset(vw / 2, vh / 2), _scrollOffset);
    return Offset(c.dx.clamp(0, kW), c.dy.clamp(0, doc.h));
  }

  /// Hoja que se está viendo (0, 1, 2...).
  int get visibleSheet => doc.sheetOfY(viewCenter.dy);

  bool _sheetCheckPending = false;

  /// El scroll puede avisar en pleno armado de pantalla: se mira recién después del cuadro.
  void _scheduleVisibleSheet() {
    if (_sheetCheckPending) return;
    _sheetCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetCheckPending = false;
      if (mounted) _updateVisibleSheet();
    });
  }

  /// Avisa a la pantalla qué hoja se ve ahora (y refresca la barra, que muestra el fondo de esa hoja).
  void _updateVisibleSheet() {
    final k = visibleSheet, n = widget.sheetNotifier;
    if (n != null && n.value != k) {
      n.value = k;
      if (mounted) setState(() {});
    }
  }

  /// Lleva la vista al principio de la hoja [k].
  void scrollToSheet(int k, {bool animate = true}) {
    if (!mounted) return;
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToSheet(k, animate: animate));
      return;
    }
    final y = (k.clamp(0, doc.sheetCount - 1) * kSheetStep * scale).clamp(0.0, scroll.position.maxScrollExtent);
    if (animate) {
      scroll.animateTo(y, duration: const Duration(milliseconds: 380), curve: Curves.easeOutQuart);
    } else {
      scroll.jumpTo(y);
    }
  }

  /// Después de agregar, duplicar, mover o borrar hojas desde afuera: lo que dependía del orden
  /// anterior (deshacer, selección, campos de texto) ya no sirve. Las operaciones de hojas no se deshacen.
  void sheetsChanged() {
    texts.attach(doc);
    history.clear();
    sel.clear();
    pointer = null;
    live = null;
    erased = null;
    eraserAt = null;
    _changed();
    setState(() {});
    _touchAll();
    liveTick.value++;
    _updateVisibleSheet();
    _syncedRange = null;
    _requestSync();
    _scheduleUnload();
  }

  /// Agrega un elemento centrado en lo que se está viendo y lo deja seleccionado.
  void insertItem(Item it) {
    final c = viewCenter;
    final y = max(0.0, c.dy - it.h / 2);
    if (!_loadedAt(y)) {
      _whenLoaded([doc.sheets[doc.sheetOfY(y)].id], () => insertItem(it));
      return;
    }
    it.x = (c.dx - it.w / 2).clamp(10.0, max(10.0, kW - it.w - 10));
    it.y = y;
    it.z = doc.nextZ();
    doc.items[it.id] = it;
    _pushUndo(EditAction(itemBefore: {it.id: null}, itemAfter: {it.id: it.copy()}));
    _setTool(Tool.select);
    sel.replace(items: [it.id]);
    _growIfNeeded(it.y + it.h);
    _changed();
    setState(() {});
    liveTick.value++;
  }

  /// Lleva la vista a un texto o elemento y lo deja seleccionado (búsqueda).
  void reveal(String id) {
    final t = doc.texts[id], it = doc.items[id];
    final y = t?.y ?? it?.y;
    if (y == null) return;
    _setTool(Tool.select);
    setState(() => sel.replace(texts: [if (t != null) id], items: [if (it != null) id]));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo((y * scale + kTopPad - 120).clamp(0.0, scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 380), curve: Curves.easeOutQuart);
      }
    });
    liveTick.value++;
  }

  /// Después de cambiar fondo/papel desde afuera.
  void refresh() {
    setState(() {});
    _touchAll();
  }

  // ---------------- armado ----------------
  @override
  Widget build(BuildContext context) => DockLayout(
        dock: ts.dock,
        hideToolbar: widget.readOnly,
        canvas: _canvasArea(),
        toolbar: (vertical, grip) => EditorToolbar(
          ts: ts,
          vertical: vertical,
          grip: grip,
          canUndo: history.canUndo,
          canRedo: history.canRedo,
          bg: doc.sheets[visibleSheet].bg,
          onToolTap: _toolTap,
          onToolLongPress: (t) {
            _setTool(t);
            _openPanel();
          },
          onPickColor: _pickQuick,
          onBg: (v) {
            setState(() => doc.sheets[visibleSheet].setBg(v)); // la hoja que se está viendo
            _changed();
          },
          onOpenPanel: _openPanelForDrawing,
          onUndo: () => _undoRedo(undo: true),
          onRedo: () => _undoRedo(undo: false),
          onToggleZoomLock: _toggleZoomLock,
          onPaste: _paste,
        ),
        onDock: (d) {
          setState(() => ts.dock = d);
          widget.onPrefsChanged();
        },
      );

  /// Visor: scroll vertical y horizontal con la página centrada, y los avisos flotantes.
  Widget _canvasArea() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: LayoutBuilder(builder: (context, box) {
        layout = SheetLayout(box.maxWidth, ts.zoom);
        _viewH = box.maxHeight;
        _viewW = box.maxWidth;
        _dpr = View.of(context).devicePixelRatio;
        developer.Timeline.timeSync('ON canvas range+sync', () {
          _range = _calcRange();
          _requestSync();
        });
        final sheetSize = Size(layout.sheetWidth, doc.h * scale);
        // durante el pellizco no scrollea: si no, el zoom tironea
        final physics = touch.pinching ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics();
        return Stack(children: [
          Listener(
            key: _viewportKey,
            onPointerDown: _touchDown,
            onPointerMove: _touchMove,
            onPointerUp: _touchUp,
            onPointerCancel: _touchUp,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => pull.onScroll(n, touching: touch.count > 0),
              child: ScrollConfiguration(
                // el lápiz NO scrollea: solo dedo y touchpad
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
                  scrollbars: true,
                ),
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: physics,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  child: SingleChildScrollView(
                    controller: hscroll,
                    scrollDirection: Axis.horizontal,
                    physics: physics,
                    child: SizedBox(
                      width: layout.contentWidth,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: kTopPad),
                        Padding(
                          padding: EdgeInsets.only(left: layout.sheetLeft),
                          child: SizedBox.fromSize(key: _sheetKey, size: sheetSize, child: _sheet()),
                        ),
                        SizedBox(
                          width: layout.contentWidth,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 70),
                            child: Text(
                              'Al final, deslizá hacia arriba y mantené para agregar una hoja',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: .7), fontSize: 13),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 28, child: Center(child: PullIndicator(pull))),
          if (ts.tool == Tool.text && texts.anyFocused)
            Positioned(left: 0, right: 0, bottom: 0, child: FormatBar(fields: texts)),
          Positioned(
            left: 0,
            right: 0,
            top: 14,
            child: Center(
              child: ZoomIndicator(visible: _zoomPill || touch.pinching, zoom: ts.zoom, locked: ts.zoomLocked),
            ),
          ),
        ]);
      }),
    );
  }

  /// La página: capas + menú de la selección + esquina para agrandar un elemento.
  Widget _sheet() {
    final textMode = ts.tool == Tool.text;
    final r = !sel.isEmpty && !sel.moving ? sel.bounds(doc) : null;
    final resizable = r != null && sel.singleItem ? doc.items[sel.items.first] : null;
    return Stack(clipBehavior: Clip.none, children: [
      _layers(textMode),
      if (r != null)
        Positioned(
          left: max(0.0, r.left * scale),
          top: r.top * scale > 60 ? r.top * scale - 56 : r.bottom * scale + 8,
          child: SelectionMenu(
            onCopy: () {
              _copySel();
              snack(context, 'Copiado', duration: const Duration(milliseconds: 1200), width: 260);
            },
            onCut: () {
              _copySel();
              _deleteSel();
            },
            onDuplicate: _duplicateSel,
            onDelete: _deleteSel,
            onClose: _clearSel,
            onOrder: _reorderSel,
          ),
        ),
      if (resizable != null)
        ResizeHandle(
          item: resizable,
          scale: scale,
          onResize: () {
            doc.markDirtyElement(resizable); // cambió de tamaño en el lugar (puede pasar de hoja)
            setState(() => liveTick.value++);
          },
          onResizeEnd: (before) {
            _pushUndo(EditAction(itemBefore: {resizable.id: before}, itemAfter: {resizable.id: resizable.copy()}));
            _changed();
          },
        ),
    ]);
  }

  /// De abajo hacia arriba: papel, y después todo en el orden de dibujo (un solo orden para trazos,
  /// textos y elementos), y arriba la capa en vivo.
  ///
  /// Rendimiento: la tinta no se dibuja trazo por trazo en widgets, y solo se arma lo que se ve.
  /// - Solo hay widgets de las hojas del rango [_range] (las visibles más un margen). Además quedan armados,
  ///   aunque estén lejos, los textos y notas con foco, lo seleccionado, los audios y lo de una hoja de arriba
  ///   que se pasa a las armadas ("extras", al final del orden).
  /// - Cada hoja tiene sus propias tandas ([ZRun]) y cada tanda de tinta es una capa con caché ([RepaintBoundary])
  ///   del tamaño de UNA hoja, recortada a ella. Un trazo que cruza de una hoja a otra está en las tandas de las dos.
  ///   Una hoja normal tiene una sola tanda; cada imagen, nota o texto "en el medio" de su tinta suma una capa.
  /// - Cada hoja repinta con su propia versión ([_verOf]): borrar o dibujar en una no toca las otras.
  /// Los widgets llevan clave para conservar su estado (campos de texto, audio) al reordenarse o pasar de hoja.
  Widget _layers(bool textMode) => developer.Timeline.timeSync('ON layers', () => _layersImpl(textMode));

  Widget _layersImpl(bool textMode) {
    final first = _range.first, last = _range.last;
    final rangeTop = first * kSheetStep;
    final fixed = <String>{...sel.texts, ...sel.items, ..._stickyFocus};
    final focusedText = texts.focused?.block.id;
    if (focusedText != null) fixed.add(focusedText);
    developer.Timeline.timeSync('ON fillRuns', () => _fillRuns(first, last));
    _updatePrefetch();
    // lo que está armado fuera de las hojas del rango (textos / notas con foco, lo seleccionado, audios, desbordes de arriba)
    final extras = <Layered>[];
    for (final it in doc.items.values) {
      final k = doc.sheetOfY(it.y);
      if (k >= first && k <= last) continue;
      if (fixed.contains(it.id) || it.type == 'audio' || (k < first && it.y + it.h > rangeTop)) extras.add(it);
    }
    for (final t in doc.texts.values) {
      final k = doc.sheetOfY(t.y);
      if (k >= first && k <= last) continue;
      if (fixed.contains(t.id) || (k < first && t.y + _textExtent(t) > rangeTop)) extras.add(t);
    }
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: textMode ? _tapPage : null,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: SheetPainter(doc.sheets, scale, first, last))),
          ),
          for (var k = first; k <= last; k++) ...[
            if (!doc.isLoadedAt(k)) _loadingMark(k),
            for (final (i, run) in _sheetRuns[doc.sheets[k].id]!.indexed) _run(run, i, textMode, k),
          ],
          for (final (i, run) in zRuns(sortByZ(extras)).indexed) _run(run, i, textMode, -1),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  // método y no closure: tiene que leer el trazo en curso al pintar, no al armar
                  painter: LivePainter(_paintLive, scale, liveTick),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Rehace las tandas ([ZRun]) de las hojas [first]..[last] que no están en [_sheetRuns] (cambiaron o recién se arman).
  /// Una sola pasada por los trazos para todas las que faltan, sin ordenar todo el cuaderno: solo se ordena lo de cada hoja.
  /// Las hojas que siguen igual no cuestan nada (la lista y sus tandas se reusan, y con eso el painter no repinta).
  void _fillRuns(int first, int last) {
    if (_runsCount != doc.sheetCount) {
      _sheetRuns.clear(); // se agregaron o sacaron hojas
      _runsCount = doc.sheetCount;
    }
    final missing = [for (var k = first; k <= last; k++) if (!_sheetRuns.containsKey(doc.sheets[k].id)) k];
    if (missing.isEmpty) return;
    final lo = missing.first, hi = missing.last;
    final buckets = {for (final k in missing) k: <Layered>[]};
    for (final s in doc.strokes.values) {
      final b = s.bounds;
      for (var k = max(lo, doc.sheetOfY(b.top)); k <= min(hi, doc.sheetOfY(b.bottom)); k++) {
        if (b.overlaps(Rect.fromLTWH(0, k * kSheetStep, kW, kSheetH))) buckets[k]?.add(s);
      }
    }
    for (final it in doc.items.values) {
      buckets[doc.sheetOfY(it.y)]?.add(it);
    }
    for (final t in doc.texts.values) {
      buckets[doc.sheetOfY(t.y)]?.add(t);
    }
    buckets.forEach((k, els) => _sheetRuns[doc.sheets[k].id] = zRuns(sortByZ(els)));
  }

  /// Aviso (sin animación) en una hoja visible que todavía no se leyó de disco: se ve el papel y nada más.
  Widget _loadingMark(int k) => Positioned(
        key: ValueKey('loading-${doc.sheets[k].id}'),
        left: 0,
        top: k * kSheetStep * scale,
        width: kW * scale,
        height: 120 * scale,
        child: IgnorePointer(
          child: Center(
            child: Text('Cargando la hoja ${k + 1}…',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .55), fontSize: 14)),
          ),
        ),
      );

  /// Alto de más para un texto (unidades), sin medirlo: sirve para saber si un texto de una hoja de arriba
  /// llega hasta las hojas armadas. Pasarse solo arma un texto de más.
  double _textExtent(TextBlock t) {
    var lines = 0.0;
    for (final p in t.body.paras) {
      lines += max(1, (p.length * 26 / max(1.0, t.w)).ceil());
    }
    return (lines + 1) * doc.lineAt(t.y) * 1.8;
  }

  /// [sheet]: índice de la hoja de la tanda de tinta (-1 en los extras, que nunca llevan tinta).
  Widget _run(ZRun run, int i, bool textMode, int sheet) {
    final strokes = run.strokes;
    if (strokes != null) {
      final r = Rect.fromLTWH(0, sheet * kSheetStep, kW, kSheetH);
      final id = doc.sheets[sheet].id;
      return Positioned(
        key: ValueKey('ink-$id-$i'),
        left: 0,
        top: r.top * scale,
        width: kW * scale,
        height: kSheetH * scale,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
                painter: InkPainter(doc, strokes, r, scale, _verOf(id), () => sel.moving ? sel.strokes : const {},
                    cache: _imgs, cacheKey: 'ink-$id-$i', sheetId: id, dpr: _dpr, maxPx: 2 * _viewW * _dpr),
                isComplex: true),
          ),
        ),
      );
    }
    final e = run.single;
    if (e is Item) {
      return ItemView(
        key: ValueKey('item-${e.id}'),
        item: e,
        file: widget.store.media(e.file ?? ''),
        scale: scale,
        textMode: textMode,
        selected: sel.items.contains(e.id),
        onStickyChanged: (v) {
          e.text = v;
          doc.markDirtyElement(e);
          _saveSoon(e.id, const Duration(milliseconds: 350));
        },
        onStickyFocus: (f) => f ? _stickyFocus.add(e.id) : _stickyFocus.remove(e.id),
      );
    }
    return _textBlock(e as TextBlock, textMode);
  }

  void _paintLive(Canvas c) => paintLiveLayer(c,
      doc: doc, scale: scale, sel: sel, live: live, eraserAt: eraserAt, eraserRadius: ts.eraserRadius, visible: _visiblePage());

  Widget _textBlock(TextBlock t, bool textMode) {
    final ed = texts.editor(t.id);
    if (ed == null) return const SizedBox.shrink();
    return TextBlockView(
      key: ValueKey('text-${t.id}'),
      block: t,
      editor: ed,
      scale: scale,
      line: doc.lineAt(t.y),
      textMode: textMode,
      selected: sel.texts.contains(t.id),
      onHandleDrag: (delta) => setState(() {
        doc.markDirtyElement(t);
        t.x = (t.x + delta.dx / scale).clamp(0.0, kW - 60);
        t.y = max(0.0, t.y + delta.dy / scale);
        t.w = min(t.w, kW - t.x - 10).clamp(120.0, kW);
        doc.markDirtyElement(t);
      }),
      onHandleDragEnd: () => setState(() {
        doc.markDirtyElement(t);
        t.y = doc.snapTextY(t.y);
        doc.markDirtyElement(t);
        _changed();
      }),
    );
  }
}
