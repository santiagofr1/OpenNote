import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' show PdfLink;

import '../data/export.dart' show decodeImage;
import '../data/storage.dart';
import '../data/system_clipboard.dart';
import '../data/updates.dart' show CancelFlag;
import '../domain/domain.dart';
import '../rendering/ink_layers.dart';
import '../rendering/paper.dart';
import '../rendering/pdf_cover.dart';
import '../rendering/pdf_pages.dart';
import '../rendering/sheet_image_cache.dart';
import '../rendering/text_layout.dart';
import '../theme/colors.dart';
import '../widgets/auto_scroller.dart';
import '../widgets/dialogs.dart';
import 'context_menu.dart';
import 'dock_layout.dart';
import 'fast_scroller.dart';
import 'format_bar.dart';
import 'handwriting.dart';
import 'heading_dialog.dart';
import 'history.dart';
import 'ink.dart';
import 'items_layer.dart';
import 'link_dialog.dart';
import 'live_layer.dart';
import 'pen_panel.dart';
import 'pull_to_add.dart';
import 'selection.dart';
import 'selection_handles.dart';
import 'selection_menu.dart';
import 'slop_drag.dart';
import 'text_blocks.dart';
import 'toolbar.dart';
import 'voice_recorder.dart';
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

  /// Cambiaron las hojas desde el editor (deshacer / rehacer una operación de hojas, hoja agregada tirando o con el menú):
  /// el panel tiene que redibujarse. Recibe la hoja que conviene mostrar (null si no hay que moverse).
  final ValueChanged<int?>? onSheetsChanged;

  /// Cambiaron los títulos del índice (se marcó uno, o se movieron / ocultaron / mudaron de hoja con lo que marcan).
  final VoidCallback? onHeadingsChanged;

  /// La grabación de voz en curso (el audio que se graba se dibuja como etiqueta "Grabando") y qué hacer al tocar parar.
  final VoiceRecorder? recorder;
  final VoidCallback? onStopRecording;

  /// Se tocó un link (de OpenNote o de un PDF importado): quien lo muestra lo abre (web, otra hoja u otro cuaderno).
  final ValueChanged<LinkTarget>? onOpenLink;

  /// Los otros cuadernos a los que se puede apuntar con un link.
  final List<Notebook> linkNotebooks;
  const PageEditor({
    this.onOpenLink,
    this.linkNotebooks = const [],
    this.onSheetsChanged,
    this.onHeadingsChanged,
    this.recorder,
    this.onStopRecording,
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
  double _pressScrollY = 0; // scroll vertical al apoyar el dedo (para el menú de la hoja)
  // elementos de cada hoja (por id) ya ordenados y agrupados en tandas; se rehacen solo cuando esa hoja cambia
  final _sheetRuns = <String, List<ZRun>>{};
  int _runsCount = -1;
  final history = History();
  final sel = Selection();
  late final texts = TextFields(onFocusChange: _rebuild, onLeftEmpty: _removeText, onEdited: _textEdited);
  late final pull = PullToAddSheet(vsync: this, onComplete: _addSheetFromPull);
  final touch = TouchTracker();
  late final stillPress = StillPressTimer(_onStillPress);

  /// Dedo apoyado que todavía puede ser un toque (para elegir un elemento): dónde y con qué scroll apoyó.
  ({int pointer, Offset global, double scrollY})? _tapCand;
  // arrastre de la hoja con dos dedos (con el zoom fijado): punto medio y scrolls de partida, y la velocidad para la inercia
  Offset _panMid0 = Offset.zero;
  double _panY0 = 0, _panX0 = 0;
  VelocityTracker? _panVel;

  /// Dedo (o clic del mouse) apoyado que todavía puede ser un toque corto para abrir un link.
  ({int pointer, Offset global, Duration t})? _linkCand;

  /// Un toque más largo que esto no abre links (es un apoyo, no un toque).
  static const kLinkTapMax = Duration(milliseconds: 350);

  /// Punteros apoyados sobre la barrita o las manijas de la selección: no cuentan como un toque sobre la hoja.
  final _selUiPointers = <int>{};
  SheetLayout layout = SheetLayout.initial;
  double get scale => layout.scale;

  // trazo o goma en curso: un solo puntero de lápiz/mouse a la vez
  int? pointer;
  Stroke? live;

  // figuras inteligentes: lápiz quieto al final de un trazo lo vuelve figura limpia; apoyado, arrastrar la agranda
  Timer? _shapeHold;
  Offset? _holdAnchor; // dónde empezó la quietud
  ShapeFit? _snapFit, _snapBase; // figura actual y la que salió del reconocimiento (se escala siempre desde ésta)
  Offset? _snapGrab; // dónde estaba el lápiz al convertirse
  double _snapPressure = .5;

  @visibleForTesting
  ShapeKind? get snappedKind => _snapFit?.kind;

  bool get _snapOn => (ts.tool == Tool.pen || ts.tool == Tool.hl) && ts.shapeSnap;

  void _endShapeHold() {
    _shapeHold?.cancel();
    _shapeHold = null;
    _snapFit = _snapBase = _snapGrab = _holdAnchor = null;
  }

  // formas exactas (herramienta Formas): la que se está arrastrando, la recién hecha (con manijas y medidas) y el
  // arrastre de una manija o de la forma entera (el trazo de trabajo se ve en la capa en vivo y se oculta el fijo)
  _ShapeDraft? _draft;
  _ActiveShape? _shape;
  _ShapeDrag? _shapeDrag;
  Stroke? _shapeEdit;

  Offset? eraserAt;
  List<Stroke>? erased;

  bool _zoomPill = false;
  Timer? _zoomPillTimer;
  final _saveTimers = <String, Timer>{}; // textos y notas: se guarda al dejar de escribir
  final _viewportKey = GlobalKey(), _sheetKey = GlobalKey();

  // scroll solo al llevar lo seleccionado hasta el borde del visor (solo al mover, no con las manijas)
  late final _edgeY = AutoScroller(scroll, _viewportKey, onScrolled: _edgeScrolled);
  late final _edgeX = AutoScroller(hscroll, _viewportKey, axis: Axis.horizontal, onScrolled: _edgeScrolled);
  Offset? _edgeGlobal; // última posición global del puntero mientras se mueve la selección

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
  bool _selectingAll = false; // "Seleccionar todo el cuaderno" cargando hojas: ninguna se suelta mientras tanto

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
    _imgs.busy = () => pointer != null || live != null || _shapeEdit != null || _cover != null || erased != null || touch.pinching; // no generar con el lápiz en uso
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
      _edgeStop();
      sel.clear();
      _outline = null;
      pointer = null;
      live = null;
      _draft = _shape = _shapeDrag = _shapeEdit = null;
      _endShapeHold();
      _endCover();
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
    _edgeStop();
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
    _shapeHold?.cancel();
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

  /// Ajusta el borde difuminado de las mallas ([meshFeather]) al zoom y la densidad de píxeles actuales: 1 px de
  /// pantalla en escalones (ver [featherForPxPerUnit]). Nunca durante el pellizco (se rearmaría todo a cada cuadro):
  /// al soltar, el rebuild vuelve a pasar por acá. Las mallas se rehacen solas al pintar ([Stroke.ensureMesh]) y las
  /// imágenes de la caché se regeneran solas porque el cambio de escala cambia su tamaño (no hace falta invalidarlas).
  void _syncMeshFeather() {
    if (touch.pinching) return;
    final f = featherForPxPerUnit(scale * _dpr);
    if (f == meshFeather) return;
    meshFeather = f;
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

  /// La hoja con más área visible en la vista (en un empate, la de arriba): donde entra lo que se importa.
  int get mostVisibleSheet {
    final off = scroll.hasClients && scroll.position.hasPixels ? scroll.offset : widget.initialSheet * kSheetStep * scale;
    final top = (off - kTopPad) / scale;
    return mostVisibleSheetFor(top, top + _viewH / scale, doc.sheetCount);
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
    if (_selectingAll) return _scheduleUnload(tries: tries + 1);
    final far = developer.Timeline.timeSync('ON farLoaded', _farLoaded);
    if (far.isEmpty) return;
    _trimHistory(far);
    final r = await widget.store.unloadSheets(doc, far, canUnload: (id) => mounted && !_pinnedSheets().contains(id));
    if (!mounted) return;
    if (r.healed.isNotEmpty) _changed(); // lo que no coincidía con el disco: que se guarde
    if (r.unloaded.length < far.length) _scheduleUnload(tries: tries + 1); // algo no se pudo (sucia, guardando...)
  }

  /// Poda del historial (ver [History.trim]): las hojas lejanas fijadas solo por el historial no pasan de
  /// [kHistoryMaxFarSheets]. No se muestra nada al usuario.
  void _trimHistory(List<String> far) {
    final v = _visibleSheets();
    final visible = {for (var k = v.first; k <= v.last; k++) doc.sheets[k].id};
    final exempt = _pinnedSheets(withHistory: false);
    if (history.trim(doc, far: far.toSet(), exempt: exempt, visible: visible) && mounted) setState(() {});
  }

  /// Hojas que NO se pueden descargar: con selección (o arrastre), texto o nota con foco, trazo o borrador en curso,
  /// audios, elementos caídos en una hoja sin cargar, y las que tocan las acciones del historial (deshacer / rehacer
  /// las necesitan en memoria). Las hojas con cambios sin guardar las protege la `Storage`.
  Set<String> _pinnedSheets({bool withHistory = true}) {
    final out = <String>{...doc.misplacedSheets};
    void byId(String id) {
      final s = doc.sheetIdOfElementId(id);
      if (s != null) out.add(s);
    }

    sel.allIds.forEach(byId);
    final f = texts.focused;
    if (f != null) byId(f.block.id);
    _stickyFocus.forEach(byId);
    for (final s in [?live, ?_cover, ...?erased]) {
      out.addAll(doc.sheetIdsOfRect(s.bounds));
    }
    for (final it in doc.items.values) {
      if (it.type == 'audio') byId(it.id);
    }
    if (withHistory) out.addAll(history.sheetIds(doc));
    if (_selectingAll) out.addAll(doc.loadedSheets);
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

  void _changed() {
    if (syncHeadings(doc)) {
      _outline = null;
      widget.onHeadingsChanged?.call();
    }
    widget.onChanged();
  }

  void _saveSoon(String id, Duration delay) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] = Timer(delay, _changed);
  }

  Offset _toPage(Offset local) => local / scale;

  /// Última posición del mouse sobre la hoja, en coordenadas de la página (null si nunca pasó). Para Ctrl+V.
  Offset? _hover;

  /// Agrega hojas si [y] quedó cerca del final del cuaderno.
  /// En un lienzo, [right] (borde derecho de lo nuevo) también hace crecer el ancho (ver [grownCanvasW]); se guarda
  /// con el índice, que `_changed` ya manda a guardar.
  void _growIfNeeded(double y, {double? right}) {
    final nb = doc.nb;
    final w = right != null && nb.canvas ? grownCanvasW(nb.canvasW, right) : nb.canvasW;
    if (y > doc.h - 250 || w != nb.canvasW) {
      setState(() {
        doc.growFor(y);
        nb.canvasW = w;
      });
    }
  }

  // ---------------- lápiz: dibujar, borrar, seleccionar ----------------
  void _down(PointerDownEvent e) {
    _linkCand = e.kind == PointerDeviceKind.mouse && e.buttons == kPrimaryMouseButton ? (pointer: e.pointer, global: e.position, t: e.timeStamp) : _linkCand;
    if (widget.readOnly || pointer != null || sel.moving) return;
    final action = penActionFor(e, ts.tool);
    if (action == null) return;
    final p = _toPage(e.localPosition);
    if (!_loadedAt(p.dy)) {
      _requestSync(); // la hoja todavía no se leyó de disco: no se escribe encima hasta que cargue
      return;
    }
    pointer = e.pointer;
    if (_shape != null && (action != PenAction.draw || ts.tool != Tool.shape)) _endShape();
    switch (action) {
      case PenAction.erase:
        _startErase(p);
      case PenAction.select:
        _selDown(p);
      case PenAction.title:
        _clearSel();
        sel.bandA = sel.bandB = p;
        sel.titleBand = true;
        liveTick.value++;
      case PenAction.draw:
        if (ts.tool == Tool.shape) {
          _shapeDown(e, p);
          return;
        }
        final pr = ts.current;
        live = Stroke(newId('s'), ts.tool == Tool.hl ? 'hl' : pr.tip, pr.color,
            pr.width * kMm / unitsPerMm(doc.sizeAt(p.dy)), // mismo grosor en papel: en A3 las unidades son más chicas
            [], pr.opacity,
            ts.tool == Tool.paint ? ts.paintParams : null);
        appendInkPoint(live!, p, pressureOf(e));
        _snapFit = _snapBase = _snapGrab = null;
        _shapeHold?.cancel();
        if (_snapOn) {
          _holdAnchor = p;
          _shapeHold = Timer(const Duration(milliseconds: 550), _snapShape);
        }
        liveTick.value++;
    }
  }

  /// El lápiz quedó quieto: si el trazo parece una figura, se reemplaza por la figura limpia.
  void _snapShape() {
    final s = live;
    if (s == null || pointer == null || !mounted) return;
    final fit = recognizeShape(s.pts);
    if (fit == null) return;
    var sum = 0.0;
    for (var i = 2; i < s.pts.length; i += 3) {
      sum += s.pts[i];
    }
    _snapPressure = (sum / s.n).clamp(.3, 1.0);
    s.pts
      ..clear()
      ..addAll(fit.toPoints(_snapPressure));
    s.invalidate();
    _snapBase = _snapFit = fit;
    _snapGrab = _holdAnchor;
    HapticFeedback.selectionClick();
    liveTick.value++;
  }

  /// Con la figura ya hecha y el lápiz apoyado: arrastrar la agranda/achica (la recta mueve su extremo).
  void _dragSnap(Stroke s, Offset p) {
    final base = _snapBase!;
    final ShapeFit fit;
    if (base.kind == ShapeKind.line) {
      fit = base.withLineEnd(p);
    } else {
      final d0 = (_snapGrab! - base.center).distance;
      final k = d0 < 1e-6 ? 1.0 : ((p - base.center).distance / d0).clamp(.15, 8.0);
      fit = base.scaled(k);
    }
    _snapFit = fit;
    s.pts
      ..clear()
      ..addAll(fit.toPoints(_snapPressure));
    s.invalidate();
  }

  void _move(PointerMoveEvent e) {
    final lc = _linkCand;
    if (lc != null && lc.pointer == e.pointer && (e.position - lc.global).distance > kTouchSlop) _linkCand = null;
    if (e.pointer != pointer) return;
    if (_shapeDrag != null) {
      _shapeDragMove(_toPage(e.localPosition));
      return;
    }
    if (_draft != null) {
      _shapeMove(_toPage(e.localPosition));
      return;
    }
    if (sel.moving) {
      // desde la posición global: el localPosition usa el scroll de cuando se apoyó el lápiz, y con el desplazamiento
      // al borde la hoja ya se corrió (cada temblor del lápiz devolvía lo seleccionado a la pantalla de arriba)
      _selDrag(_pageOfGlobal(e.position));
      if (sel.drag?.handle == Handle.move) _edgeMoved(e.position);
      return;
    }
    final p = _toPage(e.localPosition);
    if (sel.bandA != null) {
      sel.bandB = p;
      liveTick.value++;
      return;
    }
    final s = live;
    if (s != null && wantsEraser(e)) {
      // apretó el botón a mitad del trazo: lo que venía queda, y sigue borrando
      live = null;
      final snapped = _snapFit != null;
      _endShapeHold();
      _commitStroke(s, smooth: !snapped);
      _startErase(p);
      return;
    }
    if (erased != null) {
      _eraseAt(p);
      _coverAdd(p);
      eraserAt = p;
    } else if (s != null) {
      if (_snapFit != null) {
        _dragSnap(s, p);
      } else {
        appendInkPoint(s, p, pressureOf(e));
        final a = _holdAnchor;
        if (a != null && (p - a).distance * scale > 6) {
          _holdAnchor = p; // se movió: la quietud empieza de nuevo
          _shapeHold?.cancel();
          _shapeHold = Timer(const Duration(milliseconds: 550), _snapShape);
        }
      }
    }
    liveTick.value++;
  }

  void _up(PointerEvent e) {
    final lc = _linkCand;
    if (lc != null && lc.pointer == e.pointer) {
      _linkCand = null;
      // clic corto del mouse sobre un link: lo abre (el lápiz y el dedo no pasan por acá)
      if (e is PointerUpEvent && e.timeStamp - lc.t < kLinkTapMax) _linkTapAt(_toPage(e.localPosition));
    }
    if (e.pointer != pointer) return;
    pointer = null;
    if (_shapeDrag != null) {
      _shapeDragEnd();
      return;
    }
    if (_draft != null) {
      _shapeEnd(cancel: e is PointerCancelEvent);
      return;
    }
    if (sel.moving) {
      _selDrop();
      return;
    }
    final band = sel.band;
    if (band != null && sel.titleBand) {
      sel.bandA = sel.bandB = null;
      sel.titleBand = false;
      liveTick.value++;
      if (band.longestSide * scale < 6) return; // un toque: nada
      // en modo ventana (no captura): solo lo que está adentro del recuadro, para no arrastrar renglones ni letras vecinas
      final hit = Selection()..selectIn(doc, band, capture: false);
      if (!hit.isEmpty) {
        unawaited(_markHeading(hit.strokesOf(doc), hit.textsOf(doc), hit.itemsOf(doc)));
        return;
      }
      // sin nada entero adentro: un renglón impreso de una página de PDF (la más superpuesta con el recuadro)
      Item? pdf;
      var best = 0.0;
      for (final it in doc.items.values) {
        if (it.type != 'pdf') continue;
        final c = band.intersect(it.rect);
        final a = c.width > 0 && c.height > 0 ? c.width * c.height : 0.0;
        if (a > best) {
          best = a;
          pdf = it;
        }
      }
      if (pdf != null) unawaited(_markPdfHeading(pdf, band));
      return;
    }
    if (band != null) {
      if (band.longestSide * scale < 6) {
        // un toque, no un recuadro: elige el elemento de más arriba bajo el lápiz (o nada)
        sel.bandA = sel.bandB = null;
        if (_selBefore.isNotEmpty) {
          // había selección y el toque cayó afuera: solo la cancela (ya se soltó en _selDown); no elige nada
          _tapAt = null;
          setState(() {});
          liveTick.value++;
          return;
        }
        _tapSelect(band.topLeft, _selBefore);
        return;
      }
      sel.selectIn(doc, band, capture: sel.capture);
      sel.bandA = sel.bandB = null;
      setState(() {});
      liveTick.value++;
      return;
    }
    if (erased != null) {
      if (_cover != null) {
        _commitCover(erased!);
      } else if (erased!.isNotEmpty) {
        _pushUndo(EditAction(removed: erased!));
      }
      erased = null;
      eraserAt = null;
      liveTick.value++;
      return;
    }
    final s = live;
    live = null;
    final snapped = _snapFit != null;
    _endShapeHold();
    liveTick.value++;
    // cancelado por el sistema (ej. lo tomó como palma) apenas empezó: se descarta
    if (s == null || (e is PointerCancelEvent && s.n < 3)) return;
    _commitStroke(s, smooth: !snapped);
  }

  // ---------------- formas exactas ----------------
  /// ¿Se pega a la cuadrícula de la hoja [k]? (prendido en las opciones y el fondo tiene cuadrícula)
  bool _gridded(int k) => ts.shapeGrid && const {'grid', 'dots', 'axes', 'mm'}.contains(doc.sheets[k].bg);

  /// El punto [p] de la página llevado a la intersección más cercana de la hoja [k].
  Offset _gridPt(Offset p, int k) {
    final m = doc.sheets[k], top = k * kSheetStep;
    final q = snapToGrid(Offset(p.dx, p.dy - top), m.bg, m.spacing, m.size);
    return Offset(q.dx, q.dy + top);
  }

  /// Imanes de un punto: la cuadrícula si la hoja la tiene; si no, en recta y flecha el ángulo de 15 grados respecto de [from].
  Offset _magnet(String kind, Offset? from, Offset p, int k) {
    if (_gridded(k)) return _gridPt(p, k);
    if (from != null && (kind == 'line' || kind == 'arrow')) return snapAngle15(from, p);
    return p;
  }

  /// ¿[p] está a menos de 14 dp del contorno del trazo [s]?
  bool _nearOutline(Stroke s, Offset p) {
    final lim = 14 / scale, q = s.pts;
    if (!s.bounds.inflate(lim).contains(p)) return false;
    for (var i = 3; i < q.length; i += 3) {
      if (distToSegment(p, Offset(q[i - 3], q[i - 2]), Offset(q[i], q[i + 1])) < lim) return true;
    }
    return false;
  }

  void _endShape() {
    _shape = null;
    liveTick.value++;
  }

  void _shapeDown(PointerDownEvent e, Offset p) {
    final sh = _shape, old = sh == null ? null : doc.strokes[sh.id];
    if (sh != null && old != null && _nearOutline(old, p)) {
      _shapeDragStart(-1, p); // sobre el contorno de la forma activa: la mueve entera
      return;
    }
    _shape = null;
    final kind = ts.shapeKind, k = doc.sheetOfY(p.dy), a = _magnet(kind, null, p, k);
    _draft = _ShapeDraft(kind, k, a, e.kind == PointerDeviceKind.touch);
    final pr = ts.pen;
    live = Stroke(newId('s'), 'fine', pr.color, pr.width * kMm / unitsPerMm(doc.sizeAt(p.dy)), [], pr.opacity, null,
        shapeFillable(kind) && ts.shapeFill ? ts.shapeFillColor : null);
    liveTick.value++;
  }

  void _shapeMove(Offset p) {
    final d = _draft!, s = live;
    if (s == null) return;
    d.b = _magnet(d.kind, d.a, p, d.sheet);
    s.pts
      ..clear()
      ..addAll(exactShapePoints(d.kind, d.a, d.b));
    s.invalidate();
    liveTick.value++;
  }

  /// Soltó (o se canceló) la forma: si el arrastre fue de 6 unidades o más, entra con su paso de deshacer y queda activa.
  void _shapeEnd({bool cancel = false}) {
    final d = _draft!, s = live;
    _draft = null;
    live = null;
    liveTick.value++;
    if (cancel || s == null || (d.b - d.a).distance < 6) return;
    _commitStroke(s, smooth: false);
    _shape = _ActiveShape(d.kind, d.a, d.b, s.id, d.sheet);
    liveTick.value++;
  }

  /// Un dedo apoyó con otro: es zoom, no una forma.
  void _cancelTouchShape() {
    final d = _draft;
    if (d == null || !d.touch) return;
    pointer = null;
    _draft = null;
    live = null;
    liveTick.value++;
  }

  /// Empieza a arrastrar la manija [handle] de la forma activa (-1: la forma entera) con el puntero en [p].
  void _shapeDragStart(int handle, Offset p) {
    final sh = _shape, old = sh == null ? null : doc.strokes[sh.id];
    if (sh == null || old == null) {
      pointer = null;
      return;
    }
    final off = handle < 0 ? Offset.zero : shapeHandlePoints(sh.kind, sh.a, sh.b)[handle] - p;
    _shapeEdit = Stroke(old.id, old.k, old.c, old.w, List<double>.of(old.pts), old.o, null, old.fill)..z = old.z;
    _shapeDrag = _ShapeDrag(handle, old, sh.a, sh.b, p, off);
    _touchStrokes([old]); // el fijo deja de dibujarlo: se ve el de trabajo en la capa en vivo
    liveTick.value++;
  }

  void _shapeDragMove(Offset p) {
    final sh = _shape, d = _shapeDrag, w = _shapeEdit;
    if (sh == null || d == null || w == null) return;
    final k = sh.sheet;
    Offset a, b;
    if (d.handle < 0) {
      var na = d.a0 + (p - d.grab);
      if (_gridded(k)) na = _gridPt(na, k);
      a = na;
      b = d.b0 + (na - d.a0);
    } else {
      final line = sh.kind == 'line' || sh.kind == 'arrow';
      final q = _magnet(sh.kind, line ? (d.handle == 0 ? d.b0 : d.a0) : null, p + d.off, k);
      (a, b) = dragShapeHandle(sh.kind, d.a0, d.b0, d.handle, q);
    }
    sh.a = a;
    sh.b = b;
    w.pts
      ..clear()
      ..addAll(exactShapePoints(sh.kind, a, b));
    w.invalidate();
    liveTick.value++;
  }

  /// Soltó la manija: el trazo (mismo id) pasa a sus puntos nuevos con UN paso de deshacer (antes / después).
  void _shapeDragEnd() {
    final sh = _shape, d = _shapeDrag, w = _shapeEdit;
    _shapeDrag = null;
    _shapeEdit = null;
    if (sh == null || d == null || w == null) return;
    final moved = sh.a != d.a0 || sh.b != d.b0;
    if (!moved || !_loadedAt(w.bounds.top) || !_loadedAt(w.bounds.bottom)) {
      if (moved) _requestSync(); // caería en una hoja sin cargar: queda como estaba
      sh.a = d.a0;
      sh.b = d.b0;
      _touchStrokes([d.before]);
      liveTick.value++;
      return;
    }
    doc.strokes.remove(d.before.id);
    doc.strokes[w.id] = w;
    _pushUndo(EditAction(removed: [d.before], added: [w]));
    _growIfNeeded(w.bounds.bottom);
    _changed();
    liveTick.value++;
  }

  /// Manijas y medidas de la forma en curso o activa, sobre la hoja (se redibujan con la capa en vivo, sin setState).
  Widget _shapeOverlay() => Positioned.fill(
        child: ValueListenableBuilder<int>(
          valueListenable: liveTick,
          builder: (context, _, _) {
            final dr = _draft, sh = _shape != null && doc.strokes[_shape!.id] != null ? _shape : null;
            final String kind;
            final Offset a, b;
            if (dr != null) {
              (kind, a, b) = (dr.kind, dr.a, dr.b);
              if (live?.pts.isEmpty ?? true) return const SizedBox.shrink();
            } else if (sh != null) {
              (kind, a, b) = (sh.kind, sh.a, sh.b);
            } else {
              return const SizedBox.shrink();
            }
            final k = doc.sheetOfY(a.dy), top = k * kSheetStep * scale, width = kW * scale;
            final box = shapeBox(kind, a, b);
            final text = shapeMeasure(kind, a, b, unitsPerMm(doc.sizeAt(a.dy)));
            const bw = 300.0, bh = 28.0;
            final left = (box.center.dx * scale - bw / 2).clamp(0.0, max(0.0, width - bw)).toDouble();
            final above = box.top * scale - 8 - bh >= top;
            final bubble = Positioned(
              left: left,
              width: bw,
              top: above ? box.top * scale - 8 - bh : box.bottom * scale + 8,
              height: bh,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const Key('shapeMeasure'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xE6222222), borderRadius: BorderRadius.circular(12)),
                    child: Text(text,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
            );
            return Stack(clipBehavior: Clip.none, children: [
              bubble,
              if (dr == null)
                for (final (i, h) in shapeHandlePoints(kind, a, b).indexed)
                  Positioned(
                    left: h.dx * scale - 22,
                    top: h.dy * scale - 22,
                    width: 44,
                    height: 44,
                    child: Listener(
                      key: ValueKey('shapeHandle-$i'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _handleDown(i, e),
                      onPointerMove: (e) {
                        if (e.pointer == pointer && _shapeDrag != null) _shapeDragMove(_pageOfGlobal(e.position));
                      },
                      onPointerUp: _handleUp,
                      onPointerCancel: _handleUp,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle, border: Border.all(color: kAccent, width: 2)),
                        ),
                      ),
                    ),
                  ),
            ]);
          },
        ),
      );

  void _handleDown(int i, PointerDownEvent e) {
    if (widget.readOnly || pointer != null || _shape == null) return;
    pointer = e.pointer;
    _shapeDragStart(i, _pageOfGlobal(e.position));
  }

  void _handleUp(PointerEvent e) {
    if (e.pointer != pointer) return;
    pointer = null;
    if (_shapeDrag != null) _shapeDragEnd();
  }

  /// El trazo terminado pasa a la página (suavizado), con su deshacer.
  void _commitStroke(Stroke s, {bool smooth = true}) {
    if (s.n < 2) return;
    if (smooth) s.smooth(); // una figura limpia no se suaviza
    s.z = doc.nextZ(); // arriba de todo
    doc.strokes[s.id] = s; // avisa a las hojas que toca
    _pushUndo(EditAction(added: [s]));
    _growIfNeeded(s.bounds.bottom, right: s.bounds.right);
    _changed();
  }

  void _startErase(Offset p) {
    erased = [];
    _endCover();
    // sobre un PDF y sin tocar tinta: la goma corrige (pinta del color del fondo) todo el gesto
    final pdf = strokesHit(doc, p, ts.eraserRadius).isEmpty ? _pdfAt(p) : null;
    if (pdf != null) _startCover(pdf, p);
    _eraseAt(p);
    eraserAt = p;
    liveTick.value++;
  }

  // ---- corrector: la goma sobre un PDF importado ----
  Item? _coverItem; // PDF sobre el que va el gesto
  Stroke? _cover; // corrector en curso (se dibuja en vivo)
  bool _coverColored = false; // ya llegó el color real
  final _pendingCovers = <String, EditAction>{}; // confirmados que todavía esperan su color

  /// El PDF (el de z más alta) que contiene [p], o null.
  Item? _pdfAt(Offset p) {
    Item? best;
    for (final it in doc.items.values) {
      if (it.type != 'pdf' || it.file == null || !it.rect.contains(p)) continue;
      if (best == null || it.z > best.z) best = it;
    }
    return best;
  }

  void _endCover() {
    _coverItem = null;
    _cover = null;
    _coverColored = false;
  }

  void _startCover(Item pdf, Offset p) {
    final r = ts.eraserRadius;
    final c = _cover = Stroke(newId('s'), kCoverTip, '#ffffff', 2 * r, [], 1);
    _coverItem = pdf;
    _coverColored = false;
    _coverAdd(p);
    final path = widget.store.media(pdf.file!).path;
    unawaited(pdfCoverColor(pdf, p, r, path).then((argb) => _coverColorArrived(c.id, argb), onError: (_) {}));
  }

  /// Suma [p] (recortado al PDF) al corrector en curso.
  void _coverAdd(Offset p) {
    final c = _cover, it = _coverItem;
    if (c == null || it == null) return;
    final q = Offset(p.dx.clamp(it.x, it.x + it.w), p.dy.clamp(it.y, it.y + it.h));
    appendInkPoint(c, q, .5);
  }

  /// Mismo corrector con otro color (el color de un trazo es final).
  Stroke _recolored(Stroke s, String hex) => Stroke(s.id, s.k, hex, s.w, s.pts, s.o, null, s.fill)..z = s.z;

  void _coverColorArrived(String id, int argb) {
    if (!mounted) return;
    final hex = '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final cur = _cover;
    if (cur != null && cur.id == id) {
      _coverColored = true;
      _cover = _recolored(cur, hex);
      liveTick.value++;
      return;
    }
    final act = _pendingCovers.remove(id);
    if (act == null) return;
    final i = act.added.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final old = act.added[i], fin = _recolored(old, hex);
    act.added[i] = fin; // deshacer/rehacer usan el trazo final
    if (identical(doc.strokes[id], old)) {
      doc.strokes[id] = fin;
      doc.markDirtyElement(fin);
      _changed();
    }
  }

  /// Suelta el gesto: el corrector pasa a la página junto con la tinta que se llevó, en un solo paso de deshacer.
  void _commitCover(List<Stroke> removed) {
    final s = _cover!;
    final colored = _coverColored;
    _endCover();
    s.z = doc.nextZ(); // arriba de todo
    doc.strokes[s.id] = s;
    final act = EditAction(added: [s], removed: removed);
    if (!colored) _pendingCovers[s.id] = act;
    _pushUndo(act);
    _growIfNeeded(s.bounds.bottom, right: s.bounds.right);
    _changed();
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
    _shape = null; // deshacer / rehacer: la forma ya no es "la recién hecha"
    liveTick.value++;
    if (a.sheetOps.isNotEmpty) {
      _afterSheetOps();
      widget.onSheetsChanged?.call(a.sheetFocus(doc, undo: undo));
      return;
    }
    _clearSel();
    _touchAll();
    _changed();
    setState(() {});
  }

  // ---------------- selección ----------------
  void _clearSel() {
    if (sel.isEmpty && sel.bandA == null) return;
    _edgeStop();
    sel.clear();
    if (mounted) setState(() {});
    liveTick.value++;
  }

  /// Lo que estaba seleccionado al apoyar el lápiz (el toque de afuera lo deselecciona antes de resolverse; si había algo,
  /// ese toque solo cancela y no elige).
  Set<String> _selBefore = const {};

  /// Dónde fue el último toque que eligió algo (para alternar al tocar de nuevo en el mismo lugar).
  Offset? _tapAt;

  /// Toque con "seleccionar" en [p]: elige UN elemento, el de más arriba que se ve bajo el lápiz. Si ya era lo único
  /// seleccionado ([current]) y el toque cae en el mismo lugar (~12 px), pasa al siguiente hacia abajo (cíclico).
  /// Sin nada bajo el lápiz queda deseleccionado (salvo con [keepIfEmpty]). No entra al historial.
  void _tapSelect(Offset p, Set<String> current, {bool keepIfEmpty = false}) {
    final stack = sel.hitStack(doc, p, 6 / scale);
    if (stack.isEmpty && keepIfEmpty) return; // toque en un hueco del recuadro de la selección: no pasa nada
    var pick = stack.isEmpty ? null : stack.first;
    final at = _tapAt;
    if (stack.length > 1 && current.length == 1 && at != null && (p - at).distance * scale <= 12) {
      final i = stack.indexWhere((e) => e.id == current.first);
      if (i >= 0) pick = stack[(i + 1) % stack.length];
    }
    _tapAt = pick == null ? null : p;
    if (pick == null) {
      sel.clear();
    } else {
      sel.selectOne(pick);
    }
    setState(() {});
    liveTick.value++;
  }

  /// Lápiz abajo con "seleccionar": dentro de la selección la mueve; afuera estira un rectángulo nuevo
  /// (y si queda en un toque, deselecciona: con algo seleccionado no elige nada, un segundo toque elige).
  void _selDown(Offset p) {
    _selBefore = sel.allIds;
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
    sel.dragTo(p);
    setState(() => sel.applyToBlocks(doc));
    liveTick.value++;
  }

  // ---- scroll solo al arrastrar lo seleccionado hasta el borde ----
  void _edgeMoved(Offset g) {
    _edgeGlobal = g;
    _edgeY.moved(g);
    _edgeX.moved(g);
  }

  /// La hoja se corrió bajo el puntero quieto: lo seleccionado sigue al puntero.
  void _edgeScrolled() {
    final g = _edgeGlobal;
    if (g != null && sel.moving && sel.drag?.handle == Handle.move) _selDrag(_pageOfGlobal(g));
  }

  void _edgeStop() {
    _edgeGlobal = null;
    _edgeY.stop();
    _edgeX.stop();
  }

  // ---- manijas (escalar con las esquinas, rotar con la de arriba) ----
  Offset _pageOfGlobal(Offset g) => _toPage((_sheetKey.currentContext!.findRenderObject() as RenderBox).globalToLocal(g));

  void _handleStart(Handle h, Offset global) {
    if (sel.isEmpty || sel.moving) return;
    sel.startHandle(doc, h, _pageOfGlobal(global));
    _touchStrokes(sel.strokesOf(doc)); // oculta los seleccionados de la capa fija
    setState(() {});
  }

  void _handleUpdate(Offset global) {
    if (sel.moving) _selDrag(_pageOfGlobal(global));
  }

  void _handleEnd() {
    if (sel.moving) _selDrop();
  }

  void _selDrop() {
    _edgeStop();
    final drag = sel.drag!, xf = drag.xf;
    final move = drag.handle == Handle.move;
    if (move ? xf.shift.distance < .5 : xf.isIdentity) {
      // nada cambió (un toque, o la manija quedó en el lugar): vuelve todo a donde estaba
      drag.xf = const Xform();
      sel.applyToBlocks(doc);
      sel.drag = null;
      _touchStrokes(sel.strokesOf(doc));
      if (move) {
        _tapSelect(drag.from, sel.allIds, keepIfEmpty: true); // fue un toque: elige (o alterna) lo que haya bajo el lápiz
      } else {
        setState(() {});
        liveTick.value++;
      }
      return;
    }
    // si algo va a caer en una hoja sin cargar, se deshace el cambio (y se pide cargarla): nada se pierde
    final olds = sel.strokesOf(doc), news = [for (final s in olds) s.transformed(xf)];
    var lands = true;
    for (final s in news) {
      lands &= _loadedAt(s.bounds.top) && (move || _loadedAt(s.bounds.bottom));
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
      drag.xf = const Xform();
      sel.applyToBlocks(doc);
      sel.drag = null;
      _touchStrokes(olds);
      _requestSync();
      setState(() {});
      liveTick.value++;
      return;
    }
    sel.drag = null;
    final removed = <Stroke>[], added = <Stroke>[];
    for (var i = 0; i < olds.length; i++) {
      doc.strokes.remove(olds[i].id);
      removed.add(olds[i]);
      added.add(news[i]);
      doc.strokes[news[i].id] = news[i];
    }
    final textBefore = <String, TextBlock?>{}, textAfter = <String, TextBlock?>{};
    drag.textOrig.forEach((id, o) {
      final t = doc.texts[id];
      if (t == null) return;
      doc.markDirtyElement(t);
      if (t.transformed) {
        t.y = max(0.0, t.y); // con escala o giro queda libre donde se lo dejó
      } else {
        t.y = max(0.0, doc.snapTextY(t.y)); // que caiga sobre el renglón de su hoja
        t.x = t.x.clamp(0.0, doc.width - 60);
      }
      doc.markDirtyElement(t);
      final st = drag.textState[id] ?? (t.scale, t.angle, t.w);
      textBefore[id] = t.copy(d: o.topLeft - Offset(t.x, t.y))
        ..scale = st.$1
        ..angle = st.$2
        ..w = st.$3;
      textAfter[id] = t.copy();
    });
    final itemBefore = <String, Item?>{}, itemAfter = <String, Item?>{};
    drag.itemOrig.forEach((id, o) {
      final it = doc.items[id];
      if (it == null) return;
      itemBefore[id] = it.copy(d: o.topLeft - Offset(it.x, it.y))..w = o.width..h = o.height;
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
    if (r != null) _growIfNeeded(r.bottom, right: r.right);
    _changed();
    setState(() {});
  }

  void _copySel() {
    final c = ts.clipboard;
    c.strokes = sel.strokesOf(doc);
    c.texts = [for (final t in sel.textsOf(doc)) t.copy()];
    c.items = [for (final it in sel.itemsOf(doc)) it.copy()];
    // lo último que se copió gana: el portapapeles del sistema pasa a tener el texto copiado (y ya no una imagen vieja)
    unawaited(Clipboard.setData(ClipboardData(text: c.texts.map((t) => t.text).join('\n'))).catchError((_) {}));
    setState(() {});
  }

  /// "Enderezar": los textos elegidos vuelven a escala 1 y giro 0 y se acomodan al renglón (desde su esquina de arriba).
  /// Un solo paso de deshacer.
  void _straightenSel() {
    final before = <String, TextBlock?>{}, after = <String, TextBlock?>{};
    for (final t in sel.textsOf(doc)) {
      if (!t.transformed) continue;
      before[t.id] = t.copy();
      doc.markDirtyElement(t);
      t.scale = 1;
      t.angle = 0;
      t.y = max(0.0, doc.snapTextY(t.y));
      t.x = t.x.clamp(0.0, doc.width - 60);
      doc.markDirtyElement(t);
      after[t.id] = t.copy();
    }
    if (before.isEmpty) return;
    _pushUndo(EditAction(textBefore: before, textAfter: after));
    _changed();
    setState(() {});
    liveTick.value++;
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

  // ---------------- links ----------------
  /// El link elegido si lo único elegido es un link.
  Item? get _singleLink {
    if (sel.strokes.isNotEmpty || sel.texts.isNotEmpty || sel.items.length != 1) return null;
    final it = doc.items[sel.items.first];
    return it != null && it.type == 'link' ? it : null;
  }

  List<({String id, String label})> get _sheetChoices => [
        for (var k = 0; k < doc.sheetCount; k++)
          (id: doc.sheets[k].id, label: 'Hoja ${k + 1}${doc.sheets[k].title.isEmpty ? '' : ' · ${doc.sheets[k].title}'}')
      ];

  Future<String?> _askLink([String initial = '']) => showLinkDialog(context,
      initial: initial,
      sheets: _sheetChoices,
      notebooks: [for (final n in widget.linkNotebooks) (id: n.id, label: n.name)]);

  /// "Link" del menú de la selección: una zona de link sobre lo elegido (arriba de todo, con deshacer).
  Future<void> _linkSel() async {
    final r0 = sel.contentRect(doc);
    if (r0 == null) return;
    final dest = await _askLink();
    final r = sel.contentRect(doc) ?? r0;
    if (dest == null || !mounted) return;
    final pad = _loadedAt(r.top - 4) && _loadedAt(r.bottom + 4) ? 4.0 : 0.0;
    final it = Item(newId('i'), 'link', r.left - pad, r.top - pad, r.width + 2 * pad, r.height + 2 * pad, text: dest)..z = doc.nextZ();
    doc.items[it.id] = it;
    _pushUndo(EditAction(itemBefore: absent([it.id]), itemAfter: {it.id: it.copy()}));
    _changed();
    liveTick.value++;
  }

  /// "Editar link": cambia a dónde lleva el link elegido (con deshacer).
  Future<void> _editLinkSel() async {
    final it = _singleLink;
    if (it == null) return;
    final before = it.copy();
    final dest = await _askLink(it.text);
    if (dest == null || !mounted || dest == before.text || !doc.items.containsKey(it.id)) return;
    it.text = dest;
    doc.markDirtyElement(it);
    _pushUndo(EditAction(itemBefore: {it.id: before}, itemAfter: {it.id: it.copy()}));
    _changed();
    liveTick.value++;
  }

  /// El Item (link o PDF) de z más alta bajo [p] si es un link; null si no hay o lo de arriba es otra cosa.
  Item? _topItemAt(Offset p) {
    Item? best;
    for (final it in doc.items.values) {
      if (it.rect.contains(p) && (best == null || it.z > best.z)) best = it;
    }
    return best;
  }

  Item? _linkItemAt(Offset p) {
    final it = _topItemAt(p);
    return it != null && it.type == 'link' && parseLink(it.text) != null ? it : null;
  }

  /// Toque corto del dedo en [global]: abre el link que haya ahí. true si lo tomó (el toque no elige nada).
  /// [fallback]: qué hacer si era un PDF y no había link en ese punto (se sabe recién al leer sus links).
  bool _linkTapGlobal(Offset global, {VoidCallback? fallback}) {
    if (!mounted) return false;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(global);
    if (!(Offset.zero & box.size).contains(local)) return false;
    return _linkTapAt(_toPage(local), fallback: fallback);
  }

  bool _linkTapAt(Offset p, {VoidCallback? fallback}) {
    if (ts.tool == Tool.select || (ts.tool == Tool.text && texts.anyFocused) || !_loadedAt(p.dy)) return false;
    final it = _topItemAt(p);
    if (it == null) return false;
    if (it.type == 'link') {
      final t = parseLink(it.text);
      if (t == null) return false;
      widget.onOpenLink?.call(t);
      return true;
    }
    if (it.type == 'pdf' && it.file != null && widget.onOpenLink != null) {
      unawaited(_pdfLinkTap(it, p, fallback));
      return true;
    }
    return false;
  }

  /// Toque sobre una página de PDF importada: abre el link del PDF que haya en ese punto (si no, [fallback]).
  Future<void> _pdfLinkTap(Item it, Offset p, VoidCallback? fallback) async {
    final f = widget.store.media(it.file!);
    LinkTarget? target;
    var missing = false;
    try {
      final sizes = await pdfPages.pageSizes(f);
      if (it.page < sizes.length) {
        final pt = pdfPointFor(it, p, sizes[it.page]);
        final links = pt == null ? const <PdfLink>[] : await pdfPages.links(f, it.page);
        PdfLink? hit;
        for (final l in links) {
          if (l.rects.any((r) => r.containsXy(pt!.dx, pt.dy, margin: 4))) {
            hit = l;
            break;
          }
        }
        final dest = hit?.dest, url = hit?.url;
        if (url != null && (url.scheme == 'http' || url.scheme == 'https' || url.scheme == 'mailto')) {
          target = LinkWeb(url);
        } else if (dest != null) {
          final id = await _sheetOfPdfPage(it.file!, dest.pageNumber - 1);
          if (id == null) {
            missing = true;
          } else {
            target = LinkSheet(id);
          }
        }
      }
    } catch (e) {
      developer.log('no se pudo leer el link del PDF: $e', name: 'editor', level: 900);
    }
    if (!mounted) return;
    if (target != null) {
      widget.onOpenLink?.call(target);
    } else if (missing) {
      snack(context, 'Esa página no está en el cuaderno');
    } else {
      fallback?.call();
    }
  }

  /// El id de la hoja de la sección abierta que muestra la página [page] (desde 0) del PDF [file]; null si no está.
  /// Mira las hojas cargadas; si no, prueba la que le toca según otra página del mismo PDF; si no, lee las demás de disco.
  Future<String?> _sheetOfPdfPage(String file, int page) async {
    bool match(Item i) => i.type == 'pdf' && i.file == file && i.page == page;
    Item? anchor;
    for (final it in doc.items.values) {
      if (match(it)) return doc.sheets[doc.sheetOfElement(it)].id;
      if (anchor == null && it.type == 'pdf' && it.file == file) anchor = it;
    }
    Future<bool> has(SheetMeta m) async =>
        !doc.isLoaded(m.id) && (await widget.store.readSheetContent(doc.nb, m)).items.any(match);
    final tried = <String>{};
    if (anchor != null) {
      final k = doc.sheetOfElement(anchor) + page - anchor.page;
      if (k >= 0 && k < doc.sheetCount) {
        tried.add(doc.sheets[k].id);
        if (await has(doc.sheets[k])) return doc.sheets[k].id;
      }
    }
    for (final m in doc.sheets) {
      if (!tried.contains(m.id) && await has(m)) return m.id;
    }
    return null;
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
      for (final t in textBlocks) t.copy(id: newId('t'), d: Offset((t.x + d.dx).clamp(0.0, doc.width - 60) - t.x, max(0.0, t.y + d.dy) - t.y))
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
    if (r != null) _growIfNeeded(r.bottom, right: r.right);
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

  /// Pegar desde el menú de la hoja: la esquina de lo copiado va a [p].
  void _pasteAt(Offset p) {
    final c = ts.clipboard;
    final r = clipboardBounds(c);
    if (r == null) return;
    _insert(c.strokes, c.texts, p - r.topLeft, c.items);
  }

  /// Pega la imagen del portapapeles del sistema en [p] (con [center], el centro de la imagen va a [p]; si no, su esquina).
  Future<void> _pasteImageAt(Offset p, {bool center = false}) async {
    var bytes = await SystemClipboard.readImage();
    if (bytes == null || !mounted) return;
    ui.Image img;
    try {
      img = await decodeImage(bytes);
    } catch (_) {
      return;
    }
    var ext = imageExt(bytes);
    if (img.width > 2400 || ext == null) {
      // muy ancha u otro formato: se recodifica a PNG (con tope de 2400 de ancho)
      final big = img.width > 2400;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: big ? 2400 : null);
      final f = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await f.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      img = f;
      if (data == null) {
        img.dispose();
        return;
      }
      bytes = data.buffer.asUint8List();
      ext = 'png';
    }
    final w = min(560.0, doc.width - 40), h = w * img.height / img.width;
    img.dispose();
    final name = await widget.store.addMedia(bytes, ext);
    if (!mounted) return;
    final x = max(0.0, min(center ? p.dx - w / 2 : p.dx, doc.width - w));
    final y = max(0.0, center ? p.dy - h / 2 : p.dy);
    _insert([], [], Offset(x, y), [Item(newId('i'), 'image', 0, 0, w, h, file: name)]);
  }

  @visibleForTesting
  Future<void> pasteImageAt(Offset p) => _pasteImageAt(p);

  /// Ctrl+V: la imagen del sistema si hay; si no, lo copiado en la app. Va al puntero (si está sobre la hoja) o al centro de lo visible.
  Future<void> pasteFromKeyboard() async {
    if (widget.readOnly) return;
    final img = await SystemClipboard.hasImage();
    if (!mounted) return;
    final h = _hover;
    final p = h != null && _viewRect.contains(h) ? h : viewCenter; // mouse que quedó fuera de lo visible: al centro
    if (img) return _pasteImageAt(p, center: true);
    if (!ts.clipboard.isEmpty) _pasteAt(p);
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
    if (d.kind != PointerDeviceKind.stylus && _linkItemAt(_toPage(d.localPosition)) != null) return; // eso abrió el link
    _createTextAt(_toPage(d.localPosition));
  }

  /// Un toque en modo texto en el punto [p] de la hoja (para los tests).
  @visibleForTesting
  void tapTextAt(Offset p) => _createTextAt(p);

  void _createTextAt(Offset p) {
    if (!_loadedAt(p.dy)) {
      _requestSync();
      return;
    }
    final x = p.dx.clamp(4.0, doc.width - 40);
    var y = doc.snapTextY(p.dy, floor: true); // el renglón de esa hoja (puede ser uno virtual, arriba del primero)
    // pasa a la hoja siguiente solo si el renglón no entra en esta (o cae en el espacio entre hojas)
    if (!doc.nb.canvas && y % kSheetStep + doc.lineAt(y) > kSheetH && y ~/ kSheetStep < doc.sheetCount - 1) {
      y = doc.snapTextY((y ~/ kSheetStep + 1) * kSheetStep, floor: true);
    }
    if (_followBlockAbove(p)) return;
    _placeText(x.toDouble(), y);
  }

  /// Tocar debajo del último renglón de un bloque (a lo sumo 3 renglones) y en su ancho sigue ese bloque:
  /// agrega los párrafos que faltan y deja el cursor en el último. false si no hay bloque así.
  bool _followBlockAbove(Offset p) {
    final k = p.dy ~/ kSheetStep;
    TextBlock? best;
    var bestRows = 0, bestGap = double.infinity;
    for (final t in doc.texts.values) {
      if (t.y ~/ kSheetStep != k || t.transformed) continue;
      final line = doc.lineAt(t.y), r = textRect(t, line), gap = p.dy - r.bottom;
      if (gap < 0 || p.dx < t.x - 2 * line || p.dx > t.x + t.w) continue;
      final rows = (gap / line).floor() + 1;
      if (rows > 3 || gap >= bestGap) continue;
      best = t;
      bestRows = rows;
      bestGap = gap;
    }
    final ed = best == null ? null : texts.editor(best.id);
    if (best == null || ed == null) return false;
    ed.appendParagraphs(bestRows);
    showKeyboard();
    _textEdited(best);
    _changed();
    return true;
  }

  /// Un bloque nuevo y vacío en ([x], [y]) (y ya sobre el renglón), con el foco y el teclado.
  void _placeText(double x, double y) {
    final t = TextBlock(newId('t'), x.roundToDouble(), y, (doc.nb.canvas ? min(doc.width - x - 30, kW - 60) : kW - x - 30).roundToDouble(), '')..z = doc.nextZ();
    setState(() => texts.put(t.id, t));
    texts.editor(t.id)?.focusAt(0, 0);
    showKeyboard();
    _growIfNeeded(y + doc.lineAt(y), right: x + t.w);
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
    final region = Rect.fromLTRB(0, max(top, sheetTop), doc.width, min(top + vh, sheetTop + (doc.nb.canvas ? kSheetStep : kSheetH)));
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
        : doc.snapTextY(max(region.top + line * .5, sheetTop + topMarginUnits(doc.sheets[k].size) - line) + line - 0.01, floor: true);
    if (!doc.nb.canvas && y - sheetTop > kSheetH - line && k < doc.sheetCount - 1) {
      y = doc.snapTextY((k + 1) * kSheetStep + 1, floor: false); // no entra: a la hoja siguiente
    }
    _placeText(marginUnits(doc.sheets[k].size) + 10, y);
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
    _growIfNeeded(t.y + lines * doc.lineAt(t.y), right: t.x + t.w);
    _saveSoon(t.id, const Duration(milliseconds: 300));
  }

  // ---------------- herramientas ----------------
  void _setTool(Tool t) {
    if (t != Tool.select) _clearSel();
    if (t != Tool.shape) _shape = null;
    setState(() => ts.tool = t);
    if (t != Tool.text) FocusScope.of(context).unfocus();
    // por si al abrir la app no había internet: reintenta la bajada del modelo de la letra, en silencio
    if (t == Tool.title) unawaited(handwriting?.ensureModel());
  }

  // ---- atajos de teclado de la pantalla del cuaderno (fuera de los textos) ----
  /// Algún campo de texto del editor tiene el foco.
  bool get textFocused => texts.anyFocused;

  void undo() => _undoRedo(undo: true);
  void redo() => _undoRedo(undo: false);

  /// Elegir una herramienta con una tecla suelta (P, H, F, T, S). Texto abre un bloque, como el botón.
  void pickTool(Tool t) {
    if (widget.readOnly) return;
    if (t != Tool.text && ts.tool == t) return;
    _toolTap(t);
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

  Future<void> _openPanel({int? editFav}) async {
    final align = switch (ts.dock) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.topCenter
    };
    await showPenPanel(context, ts, () {
      if (!mounted) return; // el panel se cierra (dispose) después del editor: ya no hay a quién avisar
      setState(() {});
      widget.onPrefsChanged();
    }, align: align, editFav: editFav);
    if (mounted) setState(() {});
  }

  /// Colores y grosor: desde texto/seleccionar, vuelve al lápiz.
  void _openPanelForDrawing() {
    if (!ts.drawing) _setTool(Tool.pen);
    _openPanel();
  }

  /// Mantener un favorito de la barra: abre el panel editando ese favorito.
  void _editFavorite(int slot) {
    if (!ts.drawing) _setTool(Tool.pen);
    _openPanel(editFav: slot);
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
    _sheetAddedAtEnd();
    _changed();
    // lleva a la hoja nueva
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll.animateTo(min(scroll.position.maxScrollExtent, (oldH + kGap) * scale),
          duration: const Duration(milliseconds: 420), curve: Curves.easeOutQuart);
    });
  }

  // ---------------- dedos: zoom y menú de la hoja ----------------
  Offset get _scrollOffset => Offset(hscroll.hasClients ? hscroll.offset : 0, scroll.hasClients ? scroll.offset : 0);

  // Al abrir o cerrar un panel lateral el ancho del visor cambia y con él la escala: el scroll en píxeles pasaría a ser
  // otra posición del cuaderno. Se guarda la escala del último layout para reubicar la vista (ver [_keepPlaceOnResize]).
  double? _lastLayoutScale;
  SheetLayout? _lastLayout;
  bool _zoomApplied = false; // el layout de este cuadro ya acomodó el scroll por un zoom
  // destino de un scroll animado en curso, en unidades del documento: pos = docY * escala + kTopPad + px
  ({double docY, double px})? _scrollTarget;
  int _scrollTargetTurn = 0; // sube con cada animación: la que fue reemplazada no borra el destino de la nueva
  bool _retargetQueued = false;

  Offset? _zoomScrollTo; // scroll que deja el foco del pellizco en su lugar, se aplica en el próximo layout

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
    // el scroll se corrige en el layout de este mismo cuadro (ver _applyZoomScroll); si no, se pinta un cuadro con el
    // zoom nuevo y el scroll viejo y la hoja tiembla
    _zoomScrollTo = SheetLayout(_viewW, z, units: doc.width).scrollFor(anchor, f);
  }

  /// Aplica el scroll pendiente del zoom antes de que el visor arme su layout (mismo cuadro, sin notificar).
  void _applyZoomScroll() {
    final to = _zoomScrollTo;
    if (to == null) return;
    _zoomScrollTo = null;
    _zoomApplied = true;
    if (hscroll.hasClients && hscroll.position.hasPixels) hscroll.position.correctPixels(max(0.0, to.dx));
    if (scroll.hasClients && scroll.position.hasPixels) scroll.position.correctPixels(max(0.0, to.dy));
    _clampScrollSoon();
  }

  /// El máximo real recién se conoce después del layout: si el scroll quedó afuera, se recorta.
  void _clampScrollSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hscroll.hasClients && hscroll.offset > hscroll.position.maxScrollExtent) {
        hscroll.jumpTo(hscroll.position.maxScrollExtent);
      }
      if (scroll.hasClients && scroll.offset > scroll.position.maxScrollExtent) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }

  /// Si cambió la escala por el ancho del visor (se abrió o cerró un panel, giró la pantalla), deja la vista en el mismo
  /// lugar del cuaderno; con un scroll animado en curso, le recalcula el destino con la escala nueva.
  void _keepPlaceOnResize() {
    final oldScale = _lastLayoutScale, oldLayout = _lastLayout;
    _lastLayoutScale = layout.scale;
    _lastLayout = layout;
    final byZoom = _zoomApplied;
    _zoomApplied = false;
    if (oldScale == null || oldLayout == null || byZoom || (layout.scale - oldScale).abs() < 1e-6) return;
    final newScale = layout.scale;
    final target = _scrollTarget;
    if (scroll.hasClients && scroll.position.hasPixels) {
      if (target == null) {
        final docTop = (scroll.offset - kTopPad) / oldScale;
        scroll.position.correctPixels(max(0.0, docTop * newScale + kTopPad));
      } else if (!_retargetQueued) {
        _retargetQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _retargetQueued = false;
          final t = _scrollTarget;
          if (!mounted || t == null || !scroll.hasClients) return;
          _animateToTarget(t, const Duration(milliseconds: 200));
        });
      }
    }
    if (hscroll.hasClients && hscroll.position.hasPixels) {
      final docLeft = (hscroll.offset - oldLayout.sheetLeft) / oldScale;
      hscroll.position.correctPixels(max(0.0, docLeft * newScale + layout.sheetLeft));
    }
    _clampScrollSoon();
    // correctPixels no avisa: lo que depende del scroll (hoja visible, rango armado) se pone al día después
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  /// Anima el scroll vertical a [t] (docY * escala + kTopPad + px) y lo recuerda hasta que termine, para poder
  /// recalcularlo si cambia la escala mientras tanto.
  Future<void> _animateToTarget(({double docY, double px}) t, Duration d) {
    _scrollTarget = t;
    final turn = ++_scrollTargetTurn;
    final pos = (t.docY * scale + kTopPad + t.px).clamp(0.0, scroll.position.maxScrollExtent);
    // al relanzar con el mismo destino, la animación vieja termina igual (cortada): solo la última lo borra
    return scroll.animateTo(pos, duration: d, curve: Curves.easeOutQuart).whenComplete(() {
      if (turn == _scrollTargetTurn) _scrollTarget = null;
    });
  }

  void _touchDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _scrollTarget = null; // el dedo toma el control: ya no hay destino que sostener
    touch.down(e.pointer, e.position);
    if (touch.length == 2) _cancelTouchShape();
    final onSelUi = _selUiPointers.remove(e.pointer);
    _linkCand = touch.length == 1 && pointer == null && !onSelUi ? (pointer: e.pointer, global: e.position, t: e.timeStamp) : null;
    if (touch.length == 1 && pointer == null) {
      stillPress.start(e.position);
      _pressScrollY = scroll.hasClients ? scroll.offset : 0;
      _tapCand = widget.readOnly || onSelUi ? null : (pointer: e.pointer, global: e.position, scrollY: _pressScrollY);
    } else {
      stillPress.cancel(); // segundo dedo: es zoom, no menú
      _tapCand = null;
    }
    // dos dedos = pellizco (salvo que el zoom esté fijado o se esté escribiendo con el lápiz)
    if (touch.length == 2 && !ts.zoomLocked && pointer == null) {
      touch.startPinch(ts.zoom);
      pull.cancel();
      setState(() {});
    }
    // con el zoom fijado, dos dedos arrastran la hoja (con inercia al soltar)
    if (touch.length == 2 && ts.zoomLocked && pointer == null) {
      final mid = touch.midpoint!;
      touch.startPan();
      pull.cancel();
      _panMid0 = mid;
      _panY0 = scroll.hasClients ? scroll.offset : 0;
      _panX0 = hscroll.hasClients ? hscroll.offset : 0;
      _panVel = VelocityTracker.withKind(PointerDeviceKind.touch)..addPosition(e.timeStamp, mid);
    }
  }

  void _touchMove(PointerMoveEvent e) {
    if (!touch.tracks(e.pointer)) return;
    touch.move(e.pointer, e.position);
    stillPress.moved(e.position);
    final c = _tapCand;
    if (c != null && c.pointer == e.pointer && (e.position - c.global).distance > 10) _tapCand = null; // arrastra: no es un toque
    final lc = _linkCand;
    if (lc != null && lc.pointer == e.pointer && (e.position - lc.global).distance > kTouchSlop) _linkCand = null;
    if (touch.panning) {
      final mid = touch.midpoint;
      if (mid == null) return;
      final d = mid - _panMid0;
      if (scroll.hasClients) {
        final want = _panY0 - d.dy, end = scroll.position.maxScrollExtent;
        if (end > 0) scroll.jumpTo(want.clamp(0.0, end));
        pull.pulledPastEnd(want - end); // tirar más allá del final: hoja nueva (como con un dedo sin el zoom fijado)
      }
      if (hscroll.hasClients && hscroll.position.maxScrollExtent > 0) {
        hscroll.jumpTo((_panX0 - d.dx).clamp(0.0, hscroll.position.maxScrollExtent));
      }
      _panVel?.addPosition(e.timeStamp, mid);
      return;
    }
    final p = touch.pinch();
    if (p == null) return;
    final box = _viewportKey.currentContext!.findRenderObject() as RenderBox;
    _setZoom(p.zoom, box.globalToLocal(p.focal));
  }

  void _touchUp(PointerEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    final cand = _tapCand, lcand = _linkCand;
    _tapCand = null;
    _linkCand = null;
    final wasAlone = touch.length == 1 && touch.tracks(e.pointer) && !touch.pinching;
    touch.up(e.pointer);
    stillPress.cancel();
    // un toque corto y quieto sobre un link lo abre; si no, es el toque de siempre (elegir un elemento)
    var opened = false;
    if (lcand != null && lcand.pointer == e.pointer && e is PointerUpEvent && wasAlone && e.timeStamp - lcand.t < kLinkTapMax &&
        (!scroll.hasClients || (scroll.offset - _pressScrollY).abs() < 1)) {
      opened = _linkTapGlobal(lcand.global, fallback: cand == null ? null : () => _fingerTap(cand.global));
    }
    if (!opened && cand != null && cand.pointer == e.pointer && e is PointerUpEvent && wasAlone && (!scroll.hasClients || (scroll.offset - cand.scrollY).abs() < 1)) {
      _fingerTap(cand.global);
    }
    if (touch.pinching && touch.length < 2) {
      setState(() => touch.pinching = false);
      widget.onPrefsChanged();
    }
    if (touch.panning && touch.length < 2) {
      touch.endPan();
      _panInertia();
    } else if (touch.panning && touch.midpoint != null) {
      // se levantó uno de los dedos y quedan otros dos: el arrastre sigue desde acá, sin salto
      _panMid0 = touch.midpoint!;
      _panY0 = scroll.hasClients ? scroll.offset : 0;
      _panX0 = hscroll.hasClients ? hscroll.offset : 0;
    }
    if (touch.count == 0) pull.cancel(); // soltó antes de completar: vuelve
  }

  /// Inercia al soltar el arrastre de dos dedos: sigue con la velocidad que llevaba.
  void _panInertia() {
    final v = _panVel?.getVelocity().pixelsPerSecond;
    _panVel = null;
    if (v == null) return;
    void go(ScrollController c, double vel) {
      if (!c.hasClients || vel.abs() <= 50) return;
      final pos = c.position;
      if (pos is ScrollPositionWithSingleContext) pos.goBallistic(-vel);
    }

    go(scroll, v.dy);
    go(hscroll, v.dx);
  }

  void _toggleZoomLock() {
    setState(() => ts.zoomLocked = !ts.zoomLocked);
    HapticFeedback.selectionClick();
    _flashZoom();
    widget.onPrefsChanged();
  }

  /// Un dedo quieto sobre la hoja: menú contextual (si no se está scrolleando ni escribiendo).
  void _onStillPress(Offset g) {
    _tapCand = null; // mantener quieto abre el menú: al levantar no es un toque que elige
    _linkCand = null;
    if (!mounted || touch.pinching || touch.length != 1 || pointer != null) return;
    // Ojo: `isScrollingNotifier` no sirve acá: con un solo scroll posible (zoom 1, sin scroll horizontal) el dedo
    // gana la arena apenas toca y el scroll figura "en curso" aunque no se mueva. Se mira si la hoja se movió.
    if (scroll.hasClients && (scroll.offset - _pressScrollY).abs() > 1) return;
    // sobre un texto en modo texto, mantener apretado es de la selección del texto (y de arrastrarla entre párrafos)
    if (ts.tool == Tool.text && texts.textAt(g)) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(g);
    if (!(Offset.zero & box.size).contains(local)) return;
    touch.clear(); // el menú se abre con el dedo apoyado: si el "levantó" no llega, no queda un dedo fantasma
    _sheetMenu(g, _toPage(local));
  }

  /// Ancho (unidades de la hoja, desde el borde izquierdo del audio) del botón de reproducir: un toque ahí reproduce y
  /// no elige (ver `AudioChip`).
  static const kAudioPlayZone = 54.0;

  /// Toque con el dedo en [global] (en cualquier herramienta menos texto, donde tocar es para escribir): sobre una imagen,
  /// un audio o una nota adhesiva la elige (la misma barrita y manijas que con el lápiz, sin cambiar de herramienta);
  /// afuera, si había algo elegido, lo deselecciona. No entra al historial.
  void _fingerTap(Offset global) {
    if (!mounted || widget.readOnly || ts.tool == Tool.text) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    if (!(Offset.zero & box.size).contains(local)) return;
    final p = _toPage(local);
    if (!_loadedAt(p.dy)) return;
    Item? hit;
    for (final e in sel.hitStack(doc, p, 4 / scale)) {
      if (e is Item) {
        hit = e;
        break;
      }
    }
    if (hit == null) {
      final r = sel.bounds(doc);
      if (!sel.isEmpty && !(r != null && r.inflate(12).contains(p))) _clearSel();
      return;
    }
    if (hit.type == 'audio') {
      final dx = p.dx - hit.x;
      // el botón de reproducir (a la izquierda) o el de parar de la grabación (a la derecha) tienen su propio toque
      if (widget.recorder?.isRecording(hit.id) ?? false) {
        if (dx > hit.w - RecordingChip.stopZone) return;
      } else if (dx < kAudioPlayZone) {
        return;
      }
    }
    if (sel.items.length == 1 && sel.strokes.isEmpty && sel.texts.isEmpty && sel.items.contains(hit.id)) return;
    setState(() => sel.selectOne(hit!));
    liveTick.value++;
  }

  void _selUiDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch) _selUiPointers.add(e.pointer);
  }

  // ---- mover con el dedo lo ya seleccionado ----
  void _fingerMoveStart(Offset global) {
    if (sel.isEmpty || sel.moving) return;
    stillPress.cancel();
    _tapCand = null;
    sel.startDrag(doc, _pageOfGlobal(global));
    _touchStrokes(sel.strokesOf(doc)); // oculta los seleccionados de la capa fija
    setState(() {});
  }

  void _fingerMoveUpdate(Offset global) {
    if (!sel.moving) return;
    _selDrag(_pageOfGlobal(global));
    if (sel.drag?.handle == Handle.move) _edgeMoved(global);
  }

  void _fingerMoveEnd() {
    _edgeStop();
    if (sel.moving) _selDrop();
  }

  Future<void> _sheetMenu(Offset global, Offset p) async {
    final img = await SystemClipboard.hasImage();
    if (!mounted) return;
    if (ts.clipboard.isEmpty && !img) return; // sin nada copiado no hay menú (ni vibra)
    HapticFeedback.mediumImpact();
    final v = await showSheetMenu(context, global);
    if (!mounted) return;
    if (v == SheetMenuAction.paste) img ? unawaited(_pasteImageAt(p)) : _pasteAt(p);
  }

  /// Hojas que se piden juntas al cargar para "Seleccionar todo el cuaderno" (entre tanda y tanda se puede cancelar).
  static const kSelectAllBatch = 4;

  /// Carga las hojas que faltan (de a [kSelectAllBatch], mirando [cancel] entre tandas) y selecciona todo el cuaderno.
  /// Mientras carga ninguna hoja se suelta; después las protege la propia selección. Devuelve false si se canceló
  /// o falló una lectura (la selección queda como estaba; lo cargado se suelta solo más tarde).
  Future<bool> selectAllNotebook({CancelFlag? cancel, ValueNotifier<double>? progress}) async {
    if (_selectingAll) return false;
    _selectingAll = true;
    try {
      final missing = [for (final m in doc.sheets) if (!doc.isLoaded(m.id)) m.id];
      for (var i = 0; i < missing.length; i += kSelectAllBatch) {
        if (cancel?.cancelled ?? false) return false;
        await widget.store.loadSheets(doc, missing.sublist(i, min(i + kSelectAllBatch, missing.length)));
        if (!mounted) return false;
        progress?.value = min(i + kSelectAllBatch, missing.length) / missing.length;
      }
      if (cancel?.cancelled ?? false) return false;
      _setTool(Tool.select);
      setState(() => sel.selectAll(doc));
      liveTick.value++;
      return true;
    } catch (e) {
      developer.log('no se pudo cargar el cuaderno para seleccionar todo: $e', name: 'editor', level: 900);
      return false;
    } finally {
      _selectingAll = false;
      if (mounted) _scheduleUnload();
    }
  }

  // ---------------- lo que usa la pantalla del cuaderno ----------------
  /// Centro de lo que se está viendo, en coordenadas de la página.
  Offset get viewCenter {
    final vw = hscroll.hasClients ? hscroll.position.viewportDimension : kW * scale;
    final vh = scroll.hasClients ? scroll.position.viewportDimension : 600.0;
    final c = layout.toPage(Offset(vw / 2, vh / 2), _scrollOffset);
    return Offset(c.dx.clamp(0, doc.width), c.dy.clamp(0, doc.h));
  }

  /// Lo que se está viendo, en coordenadas de la página.
  Rect get _viewRect {
    final vw = hscroll.hasClients ? hscroll.position.viewportDimension : kW * scale;
    final vh = scroll.hasClients ? scroll.position.viewportDimension : 600.0;
    return Rect.fromPoints(layout.toPage(Offset.zero, _scrollOffset), layout.toPage(Offset(vw, vh), _scrollOffset));
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
      _animateToTarget((docY: k.clamp(0, doc.sheetCount - 1) * kSheetStep, px: -kTopPad), const Duration(milliseconds: 380));
    } else {
      scroll.jumpTo(y);
    }
  }

  /// Después de agregar, duplicar, mover o borrar hojas desde afuera: lo que dependía del orden anterior
  /// (selección, campos de texto) ya no sirve. Con [action] la operación queda en el historial y se puede deshacer;
  /// sin ella (algo que no se sabe deshacer) el historial se vacía.
  void sheetsChanged([EditAction? action]) {
    if (action != null) {
      history.push(action);
    } else {
      history.clear();
    }
    _afterSheetOps();
  }

  void _afterSheetOps() {
    texts.attach(doc);
    _edgeStop();
    sel.clear();
    pointer = null;
    live = null;
    _endCover();
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

  /// Hoja agregada al final (tirar o menú): se puede deshacer.
  void _sheetAddedAtEnd() {
    _pushUndo(EditAction(sheetOps: [SheetPresenceOp.added(doc, doc.sheets.last)]));
    widget.onSheetsChanged?.call(null);
  }

  /// Agrega un elemento centrado en lo que se está viendo y lo deja seleccionado. [onInserted] avisa cuando ya está en la hoja
  /// (puede tardar si hay que cargar la hoja de destino).
  void insertItem(Item it, {VoidCallback? onInserted}) {
    final c = viewCenter;
    final y = max(0.0, c.dy - it.h / 2);
    if (!_loadedAt(y)) {
      _whenLoaded([doc.sheets[doc.sheetOfY(y)].id], () => insertItem(it, onInserted: onInserted));
      return;
    }
    it.x = (c.dx - it.w / 2).clamp(10.0, max(10.0, doc.width - it.w - 10));
    it.y = y;
    it.z = doc.nextZ();
    doc.items[it.id] = it;
    _pushUndo(EditAction(itemBefore: {it.id: null}, itemAfter: {it.id: it.copy()}));
    _setTool(Tool.select);
    sel.replace(items: [it.id]);
    _growIfNeeded(it.y + it.h, right: it.x + it.w);
    onInserted?.call();
    _changed();
    setState(() {});
    liveTick.value++;
  }

  /// Termina la grabación del audio [id]: le pone la duración [ms] (también en las copias del historial, así deshacer y
  /// rehacer lo devuelven con su duración) y marca la hoja para guardar. false si el elemento ya no está.
  bool setAudioDuration(String id, int ms) {
    final it = doc.items[id];
    if (it == null) return false;
    doc.markDirtyElement(it);
    it.dur = ms;
    doc.markDirtyElement(it);
    history.patchItem(id, (c) => c.dur = ms);
    setState(() {});
    _changed();
    return true;
  }

  /// Cancela una grabación: saca el audio [id] de la hoja SIN dejar entrada en el historial y lo borra también de las
  /// entradas que ya lo mencionaban (la inserción, un movimiento): así deshacer nunca lo resucita sin archivo.
  void removeItemForgetting(String id) {
    final it = doc.items[id];
    if (it == null) return;
    doc.items.remove(id);
    history.forgetItem(id);
    sel.items.remove(id);
    _changed();
    setState(() {});
    liveTick.value++;
  }

  /// Le cambia el nombre al audio [id] (deshacible). Vacío o igual al de ahora: no hace nada.
  void renameItem(String id, String name) {
    final it = doc.items[id];
    name = name.trim();
    if (it == null || it.type != 'audio' || name == it.text) return;
    final before = it.copy();
    it.text = name;
    doc.markDirtyElement(it);
    _pushUndo(EditAction(itemBefore: {id: before}, itemAfter: {id: it.copy()}));
    _changed();
    setState(() {});
  }

  /// Pide el nombre del audio elegido (barrita de la selección).
  Future<void> _renameSel() async {
    final it = sel.itemsOf(doc).singleOrNull;
    if (it == null || it.type != 'audio') return;
    // askText: el diálogo de siempre (no libera el controlador mientras se anima al cerrarse)
    final name = await askText(context, 'Renombrar audio', initial: it.text, hint: 'Audio', ok: 'Guardar');
    if (!mounted) return;
    if (name != null) renameItem(it.id, name);
  }

  /// Lleva la vista al elemento [id] sin elegirlo ni cambiar de herramienta (el indicador de grabación).
  void scrollToItem(String id) {
    final it = doc.items[id];
    if (it == null || !scroll.hasClients) return;
    _animateToTarget((docY: it.y, px: -120), const Duration(milliseconds: 380));
  }

  /// Lleva la vista a la altura [yLocal] (local a la hoja) de la hoja [k], dejándola a ~120 px de arriba (el índice).
  void scrollToSheetY(int k, double yLocal) {
    if (!mounted) return;
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToSheetY(k, yLocal));
      return;
    }
    k = k.clamp(0, doc.sheetCount - 1);
    widget.sheetNotifier?.value = k;
    _animateToTarget((docY: k * kSheetStep + yLocal, px: -120), const Duration(milliseconds: 380));
  }

  // ---------------- índice ----------------
  /// El índice del cuaderno armado (lo usa la capa en vivo con la herramienta Título); null = hay que rehacerlo.
  List<OutlineEntry>? _outline;

  /// Los títulos cambiaron desde afuera (el panel del índice): se rehace la numeración y se repinta.
  void headingsChanged() {
    _outline = null;
    liveTick.value++;
  }

  /// Marca [strokes], [texts] e [items] como un título del índice: pregunta el nombre y el nivel y lo agrega a su hoja.
  Future<void> _markHeading(List<Stroke> strokes, List<TextBlock> texts, List<Item> items) async {
    final tops = [for (final s in strokes) s.bounds.top, for (final t in texts) t.y, for (final i in items) i.y];
    if (tops.isEmpty) return;
    var initial = '';
    Future<String?>? recognizing;
    var downloading = false;
    if (texts.isNotEmpty) {
      final first = (List.of(texts)..sort((a, b) => a.y.compareTo(b.y))).first;
      initial = first.text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (initial.length > 120) initial = initial.substring(0, 120);
    } else if (strokes.isNotEmpty && handwriting != null) {
      final hw = handwriting!;
      downloading = !await hw.isModelReady();
      if (!mounted) return;
      recognizing = hw.recognize(strokes);
    }
    await _addHeading(tops.reduce(min), [for (final s in strokes) s.id, for (final t in texts) t.id, for (final it in items) it.id],
        initial: initial, recognizing: recognizing, downloading: downloading);
  }

  /// Marca un renglón impreso de la página de PDF [it] (el recuadro [band]): el título sugerido es el texto del PDF ahí.
  Future<void> _markPdfHeading(Item it, Rect band) async {
    final zone = band.intersect(it.rect);
    if (zone.right <= zone.left || zone.bottom <= zone.top) return;
    if (it.file == null) return;
    var initial = '';
    final f = widget.store.media(it.file!);
    final sizes = await pdfPages.pageSizes(f);
    if (!mounted) return;
    if (it.page >= 0 && it.page < sizes.length) {
      final r = pdfRectFor(it, zone, sizes[it.page]);
      if (r != null) {
        initial = await pdfPages.textIn(f, it.page, r.left, r.top, r.right, r.bottom);
        if (!mounted) return;
        if (initial.length > 120) initial = initial.substring(0, 120);
      }
    }
    await _addHeading(zone.top, [it.id], initial: initial, box: zone.shift(-it.rect.topLeft));
  }

  /// Pregunta nombre y nivel de un título cuyo borde de arriba está en [top] (global) y lo agrega a su hoja.
  Future<void> _addHeading(double top, List<String> ids,
      {String initial = '', Future<String?>? recognizing, bool downloading = false, Rect? box}) async {
    final k = doc.sheetOfY(top);
    if (!doc.isLoadedAt(k)) return;
    final sheetId = doc.sheets[k].id, local = top - k * kSheetStep;
    // nivel del título anterior (en la misma sección)
    var level = 1;
    for (final e in buildOutline(doc.nb)) {
      if (e.sectionId != doc.nb.activeSection.id) continue;
      if (e.sheet < k || (e.sheet == k && e.y < local)) level = e.level;
    }
    final r = await showHeadingDialog(context,
        initialTitle: initial, initialLevel: level, recognizing: recognizing, downloading: downloading);
    if (r == null || !mounted) return;
    final i = doc.indexOfSheet(sheetId); // pudo moverse mientras se escribía
    if (i < 0) return;
    final m = doc.sheets[i];
    m.heads.add(Heading(newId('h'), level: r.level, title: r.title, y: local, ids: ids, box: box));
    m.updated = DateTime.now().millisecondsSinceEpoch;
    syncHeadings(doc);
    _outline = null;
    liveTick.value++;
    widget.onHeadingsChanged?.call();
    _changed();
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
        _animateToTarget((docY: y, px: -120), const Duration(milliseconds: 380));
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
          onToolTap: _toolTap,
          onToolLongPress: (t) {
            _setTool(t);
            _openPanel();
          },
          onPickColor: _pickQuick,
          onEditFavorite: _editFavorite,
          onOpenPanel: _openPanelForDrawing,
          onUndo: () => _undoRedo(undo: true),
          onRedo: () => _undoRedo(undo: false),
          onToggleZoomLock: _toggleZoomLock,
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
        layout = SheetLayout(box.maxWidth, ts.zoom, units: doc.width);
        _viewH = box.maxHeight;
        _viewW = box.maxWidth;
        _applyZoomScroll();
        _keepPlaceOnResize();
        _dpr = View.of(context).devicePixelRatio;
        _syncMeshFeather();
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
              onNotification: (n) => doc.nb.canvas ? false : pull.onScroll(n, touching: touch.count > 0),
              child: ScrollConfiguration(
                // el lápiz NO scrollea: solo dedo y touchpad
                // con el zoom fijado el dedo solo NO mueve la hoja (así la palma no la corre al escribir): se mueve con
                // dos dedos; la rueda del mouse y el trackpad siguen andando
                // (la barra vertical la reemplaza el scroll rápido; la horizontal tiene la suya más abajo)
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {if (!ts.zoomLocked) PointerDeviceKind.touch, PointerDeviceKind.trackpad},
                  scrollbars: false,
                ),
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: physics,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {if (!ts.zoomLocked) PointerDeviceKind.touch, PointerDeviceKind.trackpad},
                      scrollbars: true,
                    ),
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
                        if (doc.nb.canvas)
                          const SizedBox(height: 70) // el lienzo crece solo: no hay que agregar hojas
                        else
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
          ),
          // hermano del visor: el dedo sobre el pulgar no llega a los manejadores de toque del visor
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 200,
            child: FastScroller(
              controller: scroll,
              label: doc.nb.canvas ? null : () => 'Hoja ${visibleSheet + 1} de ${doc.sheetCount}',
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

  /// La página: capas + menú de la selección + manijas para escalar y rotar.
  Widget _sheet() {
    final textMode = ts.tool == Tool.text;
    final idle = !sel.isEmpty && !sel.moving;
    final r = idle ? sel.bounds(doc) : null;
    // las manijas siguen a la transformación en curso (mientras se mueve a mano, no se ven)
    final drag = sel.drag;
    final handled = !sel.isEmpty && (idle || (drag != null && drag.handle != Handle.move));
    final box = handled ? sel.bounds(doc) : null;
    final canRotate = sel.strokes.isNotEmpty || sel.texts.isNotEmpty;
    final xf = drag?.xf ?? const Xform();
    Offset px(Offset p) => xf.apply(p) * scale;
    final up = Offset(sin(xf.angle), -cos(xf.angle)); // "arriba" del recuadro, ya rotado
    final topMid = box == null ? null : px(box.topCenter);
    // manijas de los lados: solo si el lado en pantalla es largo (que no se encimen con las esquinas)
    // (además, el centro del recuadro queda libre de manijas: un toque ahí sigue siendo un toque sobre la tinta)
    final wpx = box == null ? 0.0 : box.width * scale * xf.scale * xf.kx, hpx = box == null ? 0.0 : box.height * scale * xf.scale * xf.ky;
    final wide = wpx >= 3 * SelectionHandles.hit && hpx >= 2 * SelectionHandles.hit;
    final tall = hpx >= 3 * SelectionHandles.hit && wpx >= 2 * SelectionHandles.hit;
    final sides = box == null
        ? null
        : <Offset?>[
            wide ? px(box.topCenter) : null,
            tall ? px(box.centerRight) : null,
            wide ? px(box.bottomCenter) : null,
            tall ? px(box.centerLeft) : null,
          ];
    // dedo sobre lo seleccionado: lo mueve (la zona queda montada mientras se arrastra, o el gesto se perdería)
    final body = !widget.readOnly && !sel.isEmpty && (idle || (drag != null && drag.handle == Handle.move)) ? sel.bounds(doc) : null;
    return Stack(clipBehavior: Clip.none, children: [
      _layers(textMode),
      if (ts.tool == Tool.shape && !widget.readOnly) _shapeOverlay(),
      if (body != null)
        Positioned.fromRect(
          key: const ValueKey('selBody'),
          rect: Rect.fromLTWH(body.left * scale, body.top * scale, body.width * scale, body.height * scale).inflate(12),
          child: SlopDrag(
            devices: const {PointerDeviceKind.touch},
            canStart: () => touch.length == 1 && !touch.pinching && !sel.moving,
            onStart: _fingerMoveStart,
            onUpdate: _fingerMoveUpdate,
            onEnd: _fingerMoveEnd,
          ),
        ),
      if (r != null)
        Positioned.fill(
            key: const ValueKey('selMenu'),
            child: CustomSingleChildLayout(
          // con la manija de rotar arriba, la barrita se sube para no taparla
          delegate: _MenuLayout(max(0.0, r.left * scale), r.top * scale - 8 - (canRotate ? 40 : 0), r.bottom * scale + 8),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _selUiDown,
            child: FittedBox(fit: BoxFit.scaleDown, child: SelectionMenu(
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
            onRename: sel.strokes.isEmpty &&
                    sel.texts.isEmpty &&
                    sel.items.length == 1 &&
                    sel.itemsOf(doc).any((i) => i.type == 'audio')
                ? _renameSel
                : null,
            onStraighten: sel.textsOf(doc).any((t) => t.transformed) ? _straightenSel : null,
            onLink: sel.itemsOf(doc).any((i) => i.type == 'link') ? null : _linkSel,
            onEditLink: _singleLink != null ? _editLinkSel : null,
            onRemoveLink: _singleLink != null ? _deleteSel : null,
            onClose: _clearSel,
            onOrder: _reorderSel,
          ))),
        )),
      if (box != null)
        SelectionHandles(
          key: const ValueKey('selHandles'), // la misma al pasar de quieta a arrastrada: no pierde el gesto
          corners: [for (final c in [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]) px(c)],
          sides: sides,
          topMid: canRotate ? topMid : null,
          rotateAt: canRotate ? topMid! + up * 34 : null,
          onPointerDown: _selUiDown,
          onStart: _handleStart,
          onUpdate: (_, g) => _handleUpdate(g),
          onEnd: _handleEnd,
        ),
      // los grados del giro, solo mientras se rota (sobre la manija, siguiendo el giro)
      if (drag != null && drag.handle == Handle.rotate && canRotate && box != null)
        Builder(builder: (context) {
          final cs = Theme.of(context).colorScheme;
          final at = topMid! + up * 64;
          return Positioned(
            key: const ValueKey('rotateAngle'),
            left: at.dx - 40,
            top: at.dy - 14,
            width: 80,
            height: 28,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(14)),
                  child: Text(angleLabel(xf.angle),
                      key: const Key('rotateAngleText'),
                      style: TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
            ),
          );
        }),
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
      onPointerHover: (e) => _hover = _toPage(e.localPosition),
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: textMode ? _tapPage : null,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(
                painter: doc.nb.canvas
                    ? CanvasPainter(doc.sheets.isEmpty ? '#fffefb' : doc.sheets.first.paper, doc.h, doc.width, scale)
                    : SheetPainter(doc.sheets, scale, first, last))),
          ),
          // fondos de imagen: la imagen que no está todavía (sin sincronizar) no muestra nada
          for (var k = first; k <= last; k++)
            if (!doc.nb.canvas && doc.sheets[k].bg == 'image' && doc.sheets[k].image != null)
              Positioned(
                key: ValueKey('bgImage-${doc.sheets[k].id}'),
                left: 0,
                top: k * kSheetStep * scale,
                width: kW * scale,
                height: kSheetH * scale,
                child: IgnorePointer(
                  child: Image.file(widget.store.media(doc.sheets[k].image!),
                      fit: BoxFit.contain,
                      cacheWidth: 1600,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const SizedBox()),
                ),
              ),
          for (var k = first; k <= last; k++) ...[
            if (!doc.isLoadedAt(k)) _loadingMark(k),
            for (final (i, run) in _sheetRuns[doc.sheets[k].id]!.indexed) _run(run, i, textMode, k),
          ],
          for (final (i, run) in splitHighlighters(zRuns(sortByZ(extras))).indexed) _run(run, i, textMode, -1),
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
        if (b.overlaps(doc.bandRect(k))) buckets[k]?.add(s);
      }
    }
    for (final it in doc.items.values) {
      buckets[doc.sheetOfY(it.y)]?.add(it);
    }
    for (final t in doc.texts.values) {
      buckets[doc.sheetOfY(t.y)]?.add(t);
    }
    buckets.forEach((k, els) => _sheetRuns[doc.sheets[k].id] = splitHighlighters(zRuns(sortByZ(els))));
  }

  /// Aviso (sin animación) en una hoja visible que todavía no se leyó de disco: se ve el papel y nada más.
  Widget _loadingMark(int k) => Positioned(
        key: ValueKey('loading-${doc.sheets[k].id}'),
        left: 0,
        top: k * kSheetStep * scale,
        width: doc.width * scale,
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
      final r = doc.bandRect(sheet);
      final id = doc.sheets[sheet].id;
      return Positioned(
        key: ValueKey('ink-$id-$i'),
        left: 0,
        top: r.top * scale,
        width: r.width * scale,
        height: r.height * scale,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
                painter: InkPainter(doc, strokes, r, scale, _verOf(id), () => sel.moving ? sel.strokes : (_shapeEdit != null ? {_shapeEdit!.id} : const {}),
                    cache: _imgs, cacheKey: 'ink-$id-$i', sheetId: id, dpr: _dpr, maxPx: 2 * _viewW * _dpr, multiply: run.multiply),
                // la tanda multiplicada no se rasteriza aparte: perdería la mezcla con el PDF de abajo
                isComplex: !run.multiply,
                willChange: run.multiply),
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
        recorder: widget.recorder,
        onStopRecording: widget.onStopRecording,
      );
    }
    return _textBlock(e as TextBlock, textMode);
  }

  void _paintLive(Canvas c) => paintLiveLayer(c,
      doc: doc,
      scale: scale,
      sel: sel,
      live: _cover ?? live ?? _shapeEdit,
      eraserAt: eraserAt,
      eraserRadius: ts.eraserRadius,
      visible: _visiblePage(),
      outline: _outline ??= buildOutline(doc.nb));

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
        t.x = (t.x + delta.dx / scale).clamp(0.0, doc.width - 60);
        t.y = max(0.0, t.y + delta.dy / scale);
        if (!t.transformed) t.w = min(t.w, doc.width - t.x - 10).clamp(120.0, doc.width);
        doc.markDirtyElement(t);
      }),
      onHandleDragEnd: () => setState(() {
        doc.markDirtyElement(t);
        if (!t.transformed) t.y = doc.snapTextY(t.y);
        doc.markDirtyElement(t);
        _growIfNeeded(t.y, right: t.x + t.w);
        _changed();
      }),
    );
  }
}

/// Ubica la barrita de la selección en ([x], [y]), corrida a la izquierda si no entra en el ancho de la hoja
/// (con los filtros de tinta / resaltador es larga; fuera del ancho de la hoja no recibiría toques).
class _MenuLayout extends SingleChildLayoutDelegate {
  final double x, top, bottom;
  _MenuLayout(this.x, this.top, this.bottom);
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints.loose(c.biggest);
  @override
  Offset getPositionForChild(Size size, Size child) => Offset(x.clamp(0.0, max(0.0, size.width - child.width)), top - child.height >= 0 ? top - child.height : bottom);
  @override
  bool shouldRelayout(_MenuLayout o) => o.x != x || o.top != top || o.bottom != bottom;
}

/// Forma que se está arrastrando: de A (en [sheet], donde empezó) a B. [touch]: la dibuja un dedo.
class _ShapeDraft {
  final String kind;
  final int sheet;
  final bool touch;
  Offset a, b;
  _ShapeDraft(this.kind, this.sheet, this.a, this.touch) : b = a;
}

/// La forma recién hecha: con manijas y medidas hasta que se empieza otra, se cambia de herramienta o se deshace.
class _ActiveShape {
  final String kind, id;
  final int sheet;
  Offset a, b;
  _ActiveShape(this.kind, this.a, this.b, this.id, this.sheet);
}

/// Arrastre de una manija ([handle] -1: la forma entera) con el trazo de antes y los extremos de partida.
class _ShapeDrag {
  final int handle;
  final Stroke before;
  final Offset a0, b0, grab, off; // [off]: de donde apoyó el puntero al centro de la manija
  _ShapeDrag(this.handle, this.before, this.a0, this.b0, this.grab, this.off);
}
