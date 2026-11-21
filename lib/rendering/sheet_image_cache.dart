import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../domain/domain.dart';

/// Cómo se dibujó por última vez una tanda de tinta (lo mira el benchmark; no se usa para decidir nada).
enum InkPaintMode {
  /// poca tinta: vectorial barato, sin caché
  small,

  /// hoja que todavía no se ve y no tiene imagen: no se dibujó nada (solo quedó registrada para el prefetch)
  skipped,

  /// todas las franjas listas: solo imágenes
  image,

  /// sin (o con pocas) franjas: se ve la versión de baja resolución en lo que falta
  lowRes,

  /// hay algo dibujado trazo por trazo (lo que más cuesta al rasterizar)
  vector,
}

/// Caché de imágenes de la tinta: una tanda de tinta de una hoja que no cambia se rasteriza a un [ui.Image] y mientras
/// se scrollea se dibuja esa imagen (una sola textura) en vez de volver a rasterizar decenas de miles de puntos en
/// cada cuadro (Impeller no tiene caché de pictures).
///
/// Franjas: la imagen de una tanda se arma en franjas horizontales que se generan en cuadros distintos (un trabajo
/// por cuadro, después del cuadro y fuera de él; [_kick]). La cantidad sale de los puntos ([stripCountFor]): ~[maxPointsPerStrip] (3000, con 25% de tolerancia) por franja, entre [minStrips] (4) y [maxStrips] (32); una hoja de 46k puntos son ~16.
/// Cada franja es un `toImage` mucho más chico que el de la hoja entera, así ningún cuadro paga la hoja de golpe, y
/// nunca hay dos `toImage` a la vez (el raster es un solo hilo). Mientras faltan franjas se dibujan las listas como
/// imagen y el resto como baja resolución ([InkImage.low]) o, si no hay, vectorial recortado a esa franja.
/// Cada franja tiene su clave ([InkImage.stripKey], `<tanda>#<n>`).
///
/// Cuándo se genera: (1) por adelantado ([prefetch]): el editor dice qué hojas se ven y cuáles vienen en la dirección
/// del scroll (la próxima y la siguiente) y se las va generando sin esperar a que queden quietas; (2) una tanda visible
/// que queda quieta [quiet] (300 ms) también se genera. Siempre de a una franja por cuadro, y sin interrumpir al lápiz
/// ([busy]). Los trabajos se reeligen en cada paso: si la hoja dejó de ser relevante, no se genera.
///
/// Baja resolución: de cada tanda del plan se genera primero una miniatura (ancho [lowWidth] px, ~0,6 MB) grabada
/// desde los trazos salteando puntos (1 de cada [lowStep]; grabar es la parte cara y en chico no se nota), antes que
/// las franjas. Sobrevive al desalojo de la imagen grande: si la hoja
/// vuelve a verse antes de que se regenere, se muestra esa miniatura estirada en vez de rasterizar todos sus trazos.
/// Se descarta al editar la hoja (así el trazo nuevo se ve al instante, vectorial) y en cuanto llega la imagen buena
/// no se usa más.
///
/// Cuándo se invalida: cuando cambia su hoja ([invalidateSheet], lo llama el editor junto con la versión de la hoja),
/// cuando la tanda tiene trazos distintos, cuando hay trazos ocultos por un arrastre, o cuando el tamaño en píxeles
/// pedido es otro (zoom): ahí sigue usando las franjas viejas (estiradas) hasta que se regeneran, así el pellizco no
/// vuelve a rasterizar todo.
///
/// Presupuesto (GPU/RAM), elegido para que entre la ventana de scroll normal sin desalojos: una hoja a 1000 px
/// lógicos x dpr 1,5 = 1500 x 2121 x 4 B ≈ 12,7 MB. La ventana es 2-3 hojas visibles + 2 de prefetch + 1 detrás = ~6;
/// [maxImages] = 8 tandas deja margen (una hoja con una imagen o nota en el medio suma tandas) y [maxBytes] = 112 MB
/// entra 8 hojas de ese tamaño y soporta zoom hasta ~1,2x sin desalojar. Con más zoom caben menos (se desalojan las
/// de hojas fuera de la ventana, nunca las visibles ni las del prefetch). Más las miniaturas (80 x 0,6 MB ≈ 46 MB):
/// unos 160 MB como techo, contra 4 GB de la tablet. Ninguna imagen pasa del tope de ancho que pone el editor (2x
/// el ancho de pantalla): más zoom que eso se dibuja vectorial.
class SheetImageCache {
  int maxImages;
  int maxBytes;

  /// Franjas por tanda fijas (null: según los puntos, ver [stripCountFor]; 1 = una sola imagen).
  int? stripCount;

  /// Máximo de puntos por franja y límites de la cantidad de franjas (modo adaptativo).
  int maxPointsPerStrip;
  int minStrips, maxStrips;

  /// La miniatura se graba con 1 de cada [lowStep] puntos de cada trazo (conserva el primero y el último).
  int lowStep;

  /// Si el cuadro que acaba de dibujarse pasó de estos ms de UI, el trabajo se posterga al próximo (hasta
  /// [maxDeferrals] veces seguidas, para no quedarse sin generar nunca).
  double maxFrameMs = 8;
  int maxDeferrals = 4;

  /// Ancho en píxeles de la miniatura y cuántas se guardan.
  int lowWidth;
  int maxLow;

  /// Tandas con menos puntos que esto son baratas de rasterizar: no valen una imagen.
  int minPoints;
  Duration quiet;

  /// Si devuelve true (hay lápiz en curso, pellizco...) la generación se posterga.
  bool Function()? busy;

  /// Hojas que no se sueltan para hacerle lugar a otra: las visibles y las del prefetch.
  Set<String> protectedSheets = const {};

  /// Hojas visibles: cada franja nueva las repinta enseguida (las demás, solo cuando terminan todas).
  Set<String> visibleSheets = const {};

  /// Fija las hojas que se ven y repinta las que quedaron sin pintar (sin imagen y fuera de vista) o con franjas a
  /// medias, que hasta ahora no mostraban nada nuevo.
  void setVisible(Set<String> ids) {
    visibleSheets = ids;
    for (final id in ids) {
      for (final e in entriesOf(id)) {
        if (e.mode == InkPaintMode.skipped || (e.hasImage && e.mode != InkPaintMode.image)) e.notifyListeners();
      }
    }
  }

  /// true: un trabajo por cuadro, después del cuadro (lo normal). false: uno atrás del otro sin esperar cuadros (tests
  /// que no dibujan cuadros).
  bool framePaced = true;

  /// Cuántas franjas se generaron en total (para los tests).
  int generated = 0;

  /// Cuántas miniaturas se generaron.
  int lowGenerated = 0;

  /// Sube al empezar y al terminar cada trabajo de generación (el benchmark mira si cambió de un cuadro al otro).
  int activity = 0;

  /// `toImage` en curso ahora y el máximo que hubo a la vez (para los tests: tiene que ser 1).
  int rasterInFlight = 0, maxRasterInFlight = 0;

  /// Cuántos trabajos de generación empezaron (cada uno es una franja o una miniatura).
  int jobsStarted = 0;

  static int defaultMinPoints = 1500;

  final _entries = <String, InkImage>{};
  final _bySheet = <String, List<InkImage>>{};
  List<String> _wanted = const []; // hojas a generar por adelantado, en orden de prioridad
  int _dir = 0; // dirección del scroll (+1 hacia abajo)
  final _ready = <InkImage>[]; // tandas cuyo temporizador de quietud venció
  bool _running = false, _stepPending = false, _disposed = false;
  int _deferrals = 0;
  Timer? _busyTimer;
  int _stamp = 0;

  SheetImageCache({
    this.maxImages = 8,
    this.maxBytes = 112 << 20,
    this.stripCount,
    this.maxPointsPerStrip = 3000,
    this.minStrips = 4,
    this.maxStrips = 32,
    this.lowStep = 4,
    this.lowWidth = 320,
    this.maxLow = 80,
    int? minPoints,
    this.quiet = const Duration(milliseconds: 300),
  }) : minPoints = minPoints ?? defaultMinPoints;

  /// Cuántas franjas iguales de alto hacen falta para que ninguna tenga más de [maxPoints] puntos, entre [min] y
  /// [max]. Un trazo que cruza varias franjas cuenta en todas (se graba en todas).
  static int stripCountFor(Iterable<Stroke> strokes, ui.Rect sheet, {int maxPoints = 3000, int min = 4, int max = 32}) {
    var total = 0;
    for (final s in strokes) {
      total += s.n;
    }
    var n = (total / maxPoints).ceil().clamp(min, max);
    for (var it = 0; it < 3 && n < max; it++) {
      final counts = List.filled(n, 0);
      for (final s in strokes) {
        final b = s.bounds;
        final i0 = ((b.top - sheet.top) / sheet.height * n).floor().clamp(0, n - 1);
        final i1 = ((b.bottom - sheet.top) / sheet.height * n).floor().clamp(0, n - 1);
        for (var i = i0; i <= i1; i++) {
          counts[i] += s.n;
        }
      }
      var mx = 0;
      for (final c in counts) {
        if (c > mx) mx = c;
      }
      if (mx <= maxPoints * 1.25) break; // ~maxPoints: no se persigue la franja más densa hasta el máximo
      n = (n * mx / maxPoints).ceil().clamp(n + 1, max);
    }
    return n;
  }

  /// Filas de píxeles [y0, y1) de la franja [i] de [n] en una imagen de [h] de alto.
  static (int, int) stripRange(int h, int n, int i) => ((h * i) ~/ n, i == n - 1 ? h : (h * (i + 1)) ~/ n);

  /// Qué hojas (índices) conviene tener con imagen: las visibles [first]..[last] y, si el scroll va para un lado
  /// ([dir] > 0 abajo, < 0 arriba), las [ahead] siguientes en esa dirección. Quieto: solo las visibles.
  static List<int> prefetchPlan({required int first, required int last, required int dir, required int count, int ahead = 2}) {
    final r = <int>[for (var k = first; k <= last; k++) if (k >= 0 && k < count) k];
    if (dir == 0) return r;
    for (var i = 1; i <= ahead; i++) {
      final k = dir > 0 ? last + i : first - i;
      if (k >= 0 && k < count) r.add(k);
    }
    return r;
  }

  /// Entrada de la tanda [key] de la hoja [sheetId] (se crea vacía).
  InkImage entry(String key, String sheetId) => _entries.putIfAbsent(key, () {
        final e = InkImage._(this, key, sheetId);
        (_bySheet[sheetId] ??= []).add(e);
        return e;
      });

  /// Las tandas de una hoja (para los tests y el benchmark).
  Iterable<InkImage> entriesOf(String sheetId) => _bySheet[sheetId] ?? const [];

  /// Claves de todas las franjas que hay ahora en memoria.
  Iterable<String> get stripKeys => [for (final e in _entries.values) ...e.readyStripKeys];

  /// Pide generar por adelantado las imágenes de [sheetIds] (en ese orden) mientras se scrollea hacia [dir].
  void prefetch(List<String> sheetIds, {int dir = 0}) {
    _wanted = sheetIds;
    _dir = dir;
    _kick();
  }

  /// Cambió algo de la hoja: sus imágenes ya no sirven.
  void invalidateSheet(String sheetId) {
    for (final e in entriesOf(sheetId)) {
      e.invalidate();
    }
  }

  void invalidateAll() {
    for (final e in _entries.values) {
      e.invalidate();
    }
  }

  /// La hoja se descargó: se sueltan sus imágenes y entradas.
  void dropSheet(String sheetId) {
    final gone = List.of(entriesOf(sheetId));
    _bySheet.remove(sheetId);
    for (final e in gone) {
      _entries.remove(e.key);
      _ready.remove(e);
      e._dispose();
    }
  }

  void clear() {
    for (final e in _entries.values) {
      e._dispose();
    }
    _entries.clear();
    _bySheet.clear();
    _ready.clear();
  }

  void dispose() {
    _disposed = true;
    _busyTimer?.cancel();
    clear();
  }

  /// La hoja tiene una tanda con todas las franjas listas y del tamaño que se pide ahora (se dibuja imagen, no trazos).
  bool usesImage(String sheetId) => entriesOf(sheetId).any((e) => e.hasImage && !e.needsImage);

  /// Tandas con al menos una franja.
  int get imageCount => _entries.values.where((e) => e.hasImage).length;
  int get stripsReady => _entries.values.fold(0, (a, e) => a + e.readyStripKeys.length);
  int get bytes => _entries.values.fold(0, (a, e) => a + e.bytes);
  int get lowCount => _entries.values.where((e) => e.low != null).length;
  int get lowBytes => _entries.values.fold(0, (a, e) => a + e.lowBytes);

  /// Hay algo nuevo que podría generarse (se pintó por primera vez una tanda de una hoja del prefetch).
  void kick() => _kick();

  void touch(InkImage e) => e.stamp = ++_stamp;

  // ---------------- generación ----------------
  void _kick() {
    if (_disposed || _running || _stepPending || _nextJob() == null) return;
    _stepPending = true;
    if (!framePaced) {
      Future<void>(() {
        _stepPending = false;
        _step();
      });
      return;
    }
    final sb = SchedulerBinding.instance;
    sb.addPostFrameCallback((_) {
      if (_disposed) return;
      // el cuadro que acaba de dibujarse ya gastó mucho en el hilo UI: el trabajo espera al siguiente
      if (_deferrals < maxDeferrals && _frameUiMs() > maxFrameMs) {
        _deferrals++;
        _stepPending = false;
        _kick();
        return;
      }
      _deferrals = 0;
      // fuera del cuadro: no se suma a su build (prioridad de animación: con idle no corre mientras hay un fling)
      sb.scheduleTask(() {
        _stepPending = false;
        _step();
      }, Priority.animation, debugLabel: 'ON cache job');
    });
    sb.scheduleFrame();
  }

  /// ms de UI que lleva el cuadro actual (desde su vsync); 0 si no se puede saber.
  double _frameUiMs() {
    final st = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (st == Duration.zero) return 0;
    final ms = (developer.Timeline.now - st.inMicroseconds) / 1000;
    return ms < 0 || ms > 1000 ? 0 : ms;
  }

  void _step() => developer.Timeline.timeSync('ON cache step', _stepImpl);

  void _stepImpl() {
    if (_disposed || _running) return;
    if (busy?.call() ?? false) {
      _busyTimer ??= Timer(const Duration(milliseconds: 150), () {
        _busyTimer = null;
        _kick();
      });
      return; // hay lápiz o pellizco: más tarde
    }
    final job = _nextJob();
    if (job == null) return;
    _running = true;
    jobsStarted++;
    activity++;
    (job.strip >= 0 ? _runStrip(job.e, job.strip) : _runLow(job.e)).whenComplete(() {
      _running = false;
      activity++;
      _kick();
    });
  }

  bool _usable(InkImage e) => !e._gone && !e.refused && !e.blocked && e.record != null && e.wantW > 0;

  /// Falta la miniatura (se hace primero, no depende de las franjas).
  bool _needsLow(InkImage e) => _usable(e) && e.low == null && !e.lowRefused;

  ({InkImage e, int strip})? _stripJob(InkImage e) {
    if (!_usable(e)) return null;
    final n = e.stripN;
    for (var j = 0; j < n; j++) {
      final i = _dir < 0 ? n - 1 - j : j; // hacia arriba entra primero la parte de abajo
      if (!e.stripCurrent(i)) return (e: e, strip: i);
    }
    return null;
  }

  /// El próximo trabajo: primero las miniaturas de las hojas del prefetch, después sus franjas en orden, y por último las
  /// tandas visibles que quedaron quietas.
  ({InkImage e, int strip})? _nextJob() {
    for (final id in _wanted) {
      for (final e in entriesOf(id)) {
        if (_needsLow(e)) return (e: e, strip: -1);
      }
    }
    for (final id in _wanted) {
      for (final e in entriesOf(id)) {
        final j = _stripJob(e);
        if (j != null) return j;
      }
    }
    for (var k = 0; k < _ready.length; k++) {
      final e = _ready[k];
      if (_needsLow(e)) return (e: e, strip: -1);
      final j = _stripJob(e);
      if (j != null) return j;
      if (e._gone || (!e.needsImage && (e.low != null || e.lowRefused))) _ready.removeAt(k--); // ya está todo
    }
    return null;
  }

  Future<void> _runStrip(InkImage e, int i) async {
    e.ensureStrips();
    final w = e.wantW, h = e.wantH, gen = e._gen, n = e.stripN;
    final (y0, y1) = stripRange(h, n, i);
    final strokes = e.recStrokes;
    final pic = developer.Timeline.timeSync('ON cache grabar franja', () => e.record?.call(w, h, y0, y1));
    if (pic == null || strokes == null) {
      e.blocked = true; // hay trazos ocultos: se vuelve a pedir al pintar
      return;
    }
    ui.Image img;
    final tImg = developer.TimelineTask()..start('ON cache toImage franja', arguments: {'w': w, 'h': y1 - y0});
    rasterInFlight++;
    maxRasterInFlight = max(maxRasterInFlight, rasterInFlight);
    try {
      img = await pic.toImage(w, y1 - y0);
    } catch (err) {
      developer.log('no se pudo rasterizar la tanda ${e.key}: $err', name: 'editor', level: 900);
      e.refused = true;
      return;
    } finally {
      rasterInFlight--;
      tImg.finish();
      pic.dispose();
    }
    if (_disposed || e._gone || gen != e._gen || w != e.wantW || h != e.wantH || n != e.stripN) {
      img.dispose(); // cambió mientras se rasterizaba
      if (!_disposed && !e._gone && e.needsImage) e.schedule();
      return;
    }
    final old = e.strips[i];
    if (!_makeRoom(e, img.width * img.height * 4 - (old?.bytes ?? 0))) {
      img.dispose();
      e.refused = true;
      return;
    }
    old?.image.dispose();
    e.strips[i] = InkStrip(img, w, h);
    e.imageStrokes = strokes;
    e.evicted = false;
    touch(e);
    generated++;
    // las franjas de una hoja que no se ve no la repintan hasta que están todas (cada repintado graba los trazos de nuevo)
    if (e.stripCurrentAll || visibleSheets.contains(e.sheetId)) e.notifyListeners();
  }

  /// Graba la tanda entera a [lowWidth] px de ancho salteando puntos y la baja a una miniatura.
  Future<void> _runLow(InkImage e) async {
    final gen = e._gen;
    final lw = min(lowWidth, e.wantW), lh = (lw * e.wantH / e.wantW).round().clamp(1, 1 << 14);
    final pic = developer.Timeline.timeSync('ON cache grabar miniatura', () => e.record?.call(lw, lh, 0, lh, step: lowStep));
    if (pic == null) {
      e.blocked = true;
      return;
    }
    ui.Image img;
    final tLow = developer.TimelineTask()..start('ON cache toImage miniatura', arguments: {'w': lw, 'h': lh});
    rasterInFlight++;
    maxRasterInFlight = max(maxRasterInFlight, rasterInFlight);
    try {
      img = await pic.toImage(lw, lh);
    } catch (err) {
      developer.log('no se pudo hacer la miniatura de ${e.key}: $err', name: 'editor', level: 900);
      e.lowRefused = true;
      return;
    } finally {
      rasterInFlight--;
      tLow.finish();
      pic.dispose();
    }
    if (_disposed || e._gone || gen != e._gen) {
      img.dispose();
      return;
    }
    _makeRoomLow(e);
    e.low?.dispose();
    e.low = img;
    e.lowStamp = ++_stamp;
    lowGenerated++;
  }

  /// Suelta imágenes viejas de hojas fuera de la ventana hasta que [need] bytes más entren. false si no se puede.
  bool _makeRoom(InkImage e, int need) {
    while (true) {
      final others = [for (final o in _entries.values) if (o != e && o.hasImage) o];
      final total = others.fold(need + e.bytes, (a, o) => a + o.bytes);
      if (others.length + 1 <= maxImages && total <= maxBytes) return true;
      InkImage? victim;
      for (final o in others) {
        if (protectedSheets.contains(o.sheetId)) continue;
        if (victim == null || o.stamp < victim.stamp) victim = o;
      }
      if (victim == null) return false;
      victim.evict();
    }
  }

  void _makeRoomLow(InkImage e) {
    while (true) {
      final others = [for (final o in _entries.values) if (o != e && o.low != null) o];
      if (others.length + 1 <= maxLow) return;
      var victim = others.first;
      for (final o in others) {
        if (o.lowStamp < victim.lowStamp) victim = o;
      }
      victim.low?.dispose();
      victim.low = null;
    }
  }
}

/// Una franja ya generada: [fullW] x [fullH] es el tamaño de la hoja entera para la que se hizo.
class InkStrip {
  final ui.Image image;
  final int fullW, fullH;
  InkStrip(this.image, this.fullW, this.fullH);
  int get bytes => image.width * image.height * 4;
}

/// Imágenes de una tanda de tinta de una hoja. Es un [Listenable]: avisa cuando hay algo nuevo para dibujar.
class InkImage extends ChangeNotifier {
  final SheetImageCache _cache;
  final String key, sheetId;
  List<InkStrip?> strips = [];

  /// Miniatura (baja resolución) de la tanda; se usa solo mientras faltan franjas.
  ui.Image? low;
  int lowStamp = 0;
  bool lowRefused = false;

  /// Trazos con los que se generaron las franjas (solo valen mientras la tanda tenga esos mismos).
  List<Stroke>? imageStrokes;

  /// Tamaño en píxeles que haría falta ahora.
  int wantW = 0, wantH = 0;

  /// Graba las filas [y0, y1) de la tanda (con los trazos de la última pintura) a [w] x [h] píxeles; null si ahora no
  /// se puede (trazos ocultos).
  ui.Picture? Function(int w, int h, int y0, int y1, {int step})? record;

  /// Franjas de esta tanda (las fija el pintor según los puntos).
  int stripN = 4;
  List<Stroke>? recStrokes;

  /// No entró en el presupuesto de memoria (o falló): queda vectorial hasta que cambie algo.
  bool refused = false;

  /// Había trazos ocultos al grabar: no se genera hasta la próxima pintura.
  bool blocked = false;

  /// Lo desalojó otra tanda: no se regenera solo por quietud mientras su hoja esté fuera de la ventana (si no, las
  /// hojas de afuera se desalojarían una a otra sin parar).
  bool evicted = false;
  int stamp = 0;

  /// Cómo se dibujó la última vez y si valía una imagen (para el benchmark).
  InkPaintMode mode = InkPaintMode.small;
  bool cacheable = false;
  Timer? _timer;
  bool _gone = false;
  int _gen = 0;

  InkImage._(this._cache, this.key, this.sheetId);

  String stripKey(int i) => '$key#$i';
  Iterable<String> get readyStripKeys => [for (var i = 0; i < strips.length; i++) if (strips[i] != null) stripKey(i)];
  bool get hasImage => strips.any((s) => s != null);
  int get bytes => strips.fold(0, (a, s) => a + (s?.bytes ?? 0));
  int get lowBytes => low == null ? 0 : low!.width * low!.height * 4;

  /// Cambió la cantidad de franjas de la tanda: lo generado no encaja (la miniatura sí).
  void ensureStrips() {
    if (strips.length == stripN) return;
    for (final s in strips) {
      s?.image.dispose();
    }
    strips = List.filled(stripN, null);
    _gen++;
  }

  bool stripCurrent(int i) {
    ensureStrips();
    final s = strips[i];
    return s != null && s.fullW == wantW && s.fullH == wantH;
  }

  bool get stripCurrentAll {
    ensureStrips();
    for (var i = 0; i < strips.length; i++) {
      if (!stripCurrent(i)) return false;
    }
    return true;
  }

  /// Falta alguna franja, o alguna es de otro tamaño (zoom).
  bool get needsImage => !stripCurrentAll;

  /// Cambió el tamaño pedido (zoom): se espera a que quede quieto para regenerar.
  void want(int w, int h) {
    if (w == wantW && h == wantH) return;
    wantW = w;
    wantH = h;
    _cancelTimer();
    refused = false;
  }

  /// Programa la generación (a los [SheetImageCache.quiet] ms) si hace falta y todavía no está programada.
  void schedule() {
    if (_gone || _cache._disposed || _timer != null || _cache._ready.contains(this) || refused || !needsImage) return;
    if (evicted && !_cache.protectedSheets.contains(sheetId)) return;
    _timer = Timer(_cache.quiet, () {
      _timer = null;
      if (_gone || _cache._disposed) return;
      _cache._ready.add(this);
      _cache._kick();
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Suelta todo (franjas y miniatura) y cancela lo pendiente. No avisa: se llama también al pintar.
  void invalidate() {
    _gen++;
    _cancelTimer();
    _cache._ready.remove(this);
    for (var i = 0; i < strips.length; i++) {
      strips[i]?.image.dispose();
      strips[i] = null;
    }
    low?.dispose();
    low = null;
    imageStrokes = null;
    refused = false;
    evicted = false;
    lowRefused = false;
    blocked = false;
  }

  /// Desalojo por falta de lugar: suelta las franjas pero se queda con la miniatura, y avisa (el pintor deja de usarlas).
  void evict() {
    _gen++;
    for (var i = 0; i < strips.length; i++) {
      strips[i]?.image.dispose();
      strips[i] = null;
    }
    imageStrokes = null;
    refused = false;
    evicted = true;
    notifyListeners();
  }

  void _dispose() {
    _gone = true;
    invalidate();
    record = null;
    recStrokes = null;
    dispose();
  }

  @override
  void notifyListeners() {
    if (!_gone) super.notifyListeners();
  }

  static bool sameStrokes(List<Stroke>? a, List<Stroke> b) {
    if (a == null) return false;
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
