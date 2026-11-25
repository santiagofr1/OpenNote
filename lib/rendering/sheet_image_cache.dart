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

  /// hay algo dibujado trazo por trazo (lo que más cuesta al rasterizar)
  vector,
}

/// Caché de imágenes de la tinta: una tanda de tinta de una hoja que no cambia se rasteriza a un [ui.Image] y mientras
/// se scrollea se dibuja esa imagen (una sola textura) en vez de volver a rasterizar decenas de miles de puntos en
/// cada cuadro (Impeller no tiene caché de pictures).
///
/// Franjas: la imagen de una tanda se arma en franjas horizontales que se generan en trabajos separados. La cantidad
/// sale de los puntos ([stripCountFor]): ~[maxPointsPerStrip] (8000, con 25% de tolerancia) por franja, entre [minStrips] (4) y [maxStrips] (32); una hoja de 46k puntos son ~6.
/// Cada franja es un `toImage` mucho más chico que el de la hoja entera, así ningún cuadro paga la hoja de golpe, y
/// nunca hay dos `toImage` a la vez (el raster es un solo hilo). Mientras faltan franjas en una hoja que se ve, se
/// dibujan las listas como imagen y el resto vectorial recortado a esa franja: la nitidez manda, no hay versión de baja
/// resolución. Cada franja tiene su clave ([InkImage.stripKey], `<tanda>#<n>`).
///
/// Cuándo se genera: (1) por adelantado ([prefetch]): el editor dice qué hojas se ven y cuáles vienen en la dirección
/// del scroll ([prefetchAhead] = 2) y se las va generando sin esperar a que queden quietas; (2) una tanda visible que
/// queda quieta [quiet] (300 ms) también se genera. Sin interrumpir al lápiz ([busy]). Los trabajos se reeligen en
/// cada paso: si la hoja dejó de ser relevante, no se genera.
///
/// Prioridad ([_nextJob]): primero las franjas de las hojas visibles que intersectan el viewport ([viewFractions]),
/// después el resto de las franjas de las visibles, después las hojas siguientes del plan en el sentido del scroll.
///
/// Varios trabajos por cuadro: un trabajo termina y, si el UI del cuadro más lo ya grabado desde entonces no pasó de
/// [maxFrameMs] (8 ms) y no se llegó a [maxJobsPerFrame], el siguiente arranca enseguida (sin esperar al próximo
/// cuadro); si no, espera al post-frame como siempre. Sigue habiendo un solo `toImage` en vuelo. Con el scroll quieto
/// ([still]) y franjas faltantes en una hoja visible no hay presupuesto: se generan una tras otra hasta completar.
///
/// Cuándo se invalida: cuando cambia su hoja ([invalidateSheet], lo llama el editor junto con la versión de la hoja),
/// cuando la tanda tiene trazos distintos, cuando hay trazos ocultos por un arrastre, o cuando el tamaño en píxeles
/// pedido es otro (zoom): ahí sigue usando las franjas viejas (estiradas) hasta que se regeneran, así el pellizco no
/// vuelve a rasterizar todo.
///
/// Presupuesto (GPU/RAM): una hoja a ~1650 px de ancho = 1650 x 2333 x 4 B ≈ 15,4 MB. La ventana protegida es hasta
/// 2 visibles + [prefetchAhead] (2) adelante + 1 detrás = 5 hojas ≈ 77 MB; [maxBytes] = 96 MB entra eso con zoom ~1,1x
/// y [maxImages] = 8 tandas deja margen para hojas con varias tandas (una imagen o nota en el medio). Con más zoom
/// caben menos (se desalojan las de fuera de la ventana, nunca las visibles ni las del prefetch; si ni así entra,
/// esa tanda queda vectorial, que con mallas es barato). Antes (etapa 4): 12 tandas / 192 MB / 3 adelante, y las
/// imágenes de hojas que ya se pasaron quedaban hasta que otra necesitara el lugar (tras desplazar mucho: PSS 583 MB
/// medido en la tablet); ahora [releaseOutsideWindow] las suelta al cambiar la ventana, así la RAM de imágenes queda
/// acotada por la ventana (<= 96 MB) y no por el tiempo que se scrollea. Contra 4 GB de la tablet. Ninguna imagen
/// pasa del tope de ancho que pone el editor (2x el ancho de pantalla): más zoom que eso se dibuja vectorial.
class SheetImageCache {
  int maxImages;
  int maxBytes;

  /// Franjas por tanda fijas (null: según los puntos, ver [stripCountFor]; 1 = una sola imagen).
  int? stripCount;

  /// Máximo de puntos por franja y límites de la cantidad de franjas (modo adaptativo).
  int maxPointsPerStrip;
  int minStrips, maxStrips;

  /// Si el cuadro que acaba de dibujarse pasó de estos ms de UI, el trabajo se posterga al próximo (hasta
  /// [maxDeferrals] veces seguidas, para no quedarse sin generar nunca). Mientras el UI del cuadro (más lo grabado
  /// por los trabajos desde entonces) esté por debajo, se encadenan trabajos dentro del mismo cuadro, hasta
  /// [maxJobsPerFrame].
  double maxFrameMs = 8;
  int maxDeferrals = 4;
  int maxJobsPerFrame = 4;

  /// Cuántas hojas por delante del scroll se generan por adelantado.
  static const prefetchAhead = 2;

  /// Para los tests: ms de UI del cuadro actual (null: se mide desde el vsync).
  @visibleForTesting
  double Function()? uiMsProbe;

  /// El scroll está quieto: las franjas faltantes de hojas visibles se generan ya, sin presupuesto por cuadro.
  bool still = false;

  /// Por hoja visible, qué parte de su alto se ve ahora (fracciones 0..1): sus franjas se generan primero.
  Map<String, (double, double)> viewFractions = const {};

  /// Tandas con menos puntos que esto son baratas de rasterizar: no valen una imagen. Con trazos como mallas (una
  /// `drawVertices` por lote) una hoja de 12k puntos se pinta en ~1 ms de UI.
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
  void setVisible(Set<String> ids, {Map<String, (double, double)>? fractions}) {
    visibleSheets = ids;
    viewFractions = fractions ?? const {};
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

  /// Sube al empezar y al terminar cada trabajo de generación (el benchmark mira si cambió de un cuadro al otro).
  int activity = 0;

  /// `toImage` en curso ahora y el máximo que hubo a la vez (para los tests: tiene que ser 1).
  int rasterInFlight = 0, maxRasterInFlight = 0;

  /// Cuántos trabajos de generación empezaron (cada uno es una franja).
  int jobsStarted = 0;

  static int defaultMinPoints = 12000;

  final _entries = <String, InkImage>{};
  final _bySheet = <String, List<InkImage>>{};
  List<String> _wanted = const []; // hojas a generar por adelantado, en orden de prioridad
  int _dir = 0; // dirección del scroll (+1 hacia abajo)
  final _ready = <InkImage>[]; // tandas cuyo temporizador de quietud venció
  bool _running = false, _stepPending = false, _disposed = false;
  int _deferrals = 0;
  bool _frameHooked = false;
  double _lastFrameUiMs = 0, _jobMs = 0;
  int _jobsThisFrame = 0;
  Timer? _busyTimer;
  int _stamp = 0;

  SheetImageCache({
    this.maxImages = 8,
    this.maxBytes = 96 << 20,
    this.stripCount,
    this.maxPointsPerStrip = 8000,
    this.minStrips = 4,
    this.maxStrips = 32,
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
  static List<int> prefetchPlan({required int first, required int last, required int dir, required int count, int ahead = prefetchAhead}) {
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

  /// Suelta las imágenes de las hojas que no están en la ventana protegida ni se ven (la hoja sigue cargada: si se
  /// vuelve a ella, se regenera). Con la tinta como mallas pintar una hoja vectorial es barato, así que no vale la pena
  /// tener RAM/GPU ocupada con imágenes de hojas que ya se pasaron. Devuelve cuántas tandas soltó.
  int releaseOutsideWindow() {
    var n = 0;
    for (final e in List.of(_entries.values)) {
      if (!e.hasImage || protectedSheets.contains(e.sheetId) || visibleSheets.contains(e.sheetId)) continue;
      e.evict(notify: false); // (se llama también durante el build: las hojas que no se ven no hace falta repintarlas)
      n++;
    }
    return n;
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

  /// Hay algo nuevo que podría generarse (se pintó por primera vez una tanda de una hoja del prefetch).
  void kick() => _kick();

  void touch(InkImage e) => e.stamp = ++_stamp;

  // ---------------- generación ----------------
  void _kick() {
    if (_disposed || _running || _stepPending) return;
    final job = _nextJob();
    if (job == null) return;
    _stepPending = true;
    if (!framePaced || (still && job.visible)) {
      // sin cuadros (tests) o franjas faltantes de una hoja visible quieta: ya, sin esperar al cuadro
      Future<void>(() {
        _stepPending = false;
        _step();
      });
      return;
    }
    final sb = SchedulerBinding.instance;
    sb.addPostFrameCallback((_) {
      if (_disposed) return;
      _endOfFrame();
      // el cuadro que acaba de dibujarse ya gastó mucho en el hilo UI: el trabajo espera al siguiente
      if (_deferrals < maxDeferrals && _lastFrameUiMs > maxFrameMs) {
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

  /// Al terminar un cuadro: se anota cuánto gastó de UI y se reinicia lo que gastaron los trabajos desde el anterior.
  void _endOfFrame() {
    _frameHooked = false;
    _lastFrameUiMs = uiMsProbe?.call() ?? _frameUiMs();
    _jobMs = 0;
    _jobsThisFrame = 0;
  }

  /// ms de UI que lleva el cuadro actual (desde su vsync); 0 si no se puede saber.
  double _frameUiMs() {
    final st = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (st == Duration.zero) return 0;
    final ms = (developer.Timeline.now - st.inMicroseconds) / 1000;
    return ms < 0 || ms > 1000 ? 0 : ms;
  }

  /// Después de un trabajo: ¿arranca el siguiente enseguida? Sí si hay presupuesto de UI en este cuadro, o si la hoja
  /// visible está quieta y le faltan franjas.
  bool _canChain(({InkImage e, int strip, bool visible})? next) {
    if (next == null || _disposed) return false;
    if (still && next.visible) return true;
    if (!framePaced) return false; // los tests sin cuadros ya encadenan por Future
    return _jobsThisFrame < maxJobsPerFrame && _lastFrameUiMs + _jobMs < maxFrameMs;
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
    _jobsThisFrame++;
    activity++;
    if (framePaced && !_frameHooked) {
      _frameHooked = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _endOfFrame();
      });
    }
    _runStrip(job.e, job.strip).whenComplete(() {
      _running = false;
      activity++;
      if (_disposed) return;
      if (_canChain(_nextJob())) {
        scheduleMicrotask(_step);
      } else {
        _kick();
      }
    });
  }

  bool _usable(InkImage e) => !e._gone && !e.refused && !e.blocked && e.record != null && e.wantW > 0;

  /// Primera franja que falta de [e] (en el orden del scroll). [inView]: solo las que intersectan el viewport.
  ({InkImage e, int strip, bool visible})? _stripJob(InkImage e, {bool inView = false}) {
    if (!_usable(e)) return null;
    final n = e.stripN;
    final f = inView ? viewFractions[e.sheetId] : null;
    for (var j = 0; j < n; j++) {
      final i = _dir < 0 ? n - 1 - j : j; // hacia arriba entra primero la parte de abajo
      if (f != null && !(i / n < f.$2 && (i + 1) / n > f.$1)) continue;
      if (!e.stripCurrent(i)) return (e: e, strip: i, visible: visibleSheets.contains(e.sheetId));
    }
    return null;
  }

  /// El próximo trabajo: (1) franjas de las hojas visibles que se ven en pantalla ahora, (2) el resto de las franjas de
  /// las visibles, (3) las hojas siguientes del plan en orden, (4) las tandas que quedaron quietas.
  ({InkImage e, int strip, bool visible})? _nextJob() {
    final vis = <String>[
      for (final id in _wanted)
        if (visibleSheets.contains(id)) id,
      for (final id in visibleSheets)
        if (!_wanted.contains(id)) id,
    ];
    for (final id in vis) {
      for (final e in entriesOf(id)) {
        final j = _stripJob(e, inView: true);
        if (j != null) return j;
      }
    }
    for (final id in vis) {
      for (final e in entriesOf(id)) {
        final j = _stripJob(e);
        if (j != null) return j;
      }
    }
    for (final id in _wanted) {
      if (visibleSheets.contains(id)) continue;
      for (final e in entriesOf(id)) {
        final j = _stripJob(e);
        if (j != null) return j;
      }
    }
    for (var k = 0; k < _ready.length; k++) {
      final e = _ready[k];
      final j = _stripJob(e);
      if (j != null) return j;
      if (e._gone || !e.needsImage) _ready.removeAt(k--); // ya está todo
    }
    return null;
  }

  Future<void> _runStrip(InkImage e, int i) async {
    e.ensureStrips();
    final w = e.wantW, h = e.wantH, gen = e._gen, n = e.stripN;
    final (y0, y1) = stripRange(h, n, i);
    final strokes = e.recStrokes;
    final sw = Stopwatch()..start();
    final pic = developer.Timeline.timeSync('ON cache grabar franja', () => e.record?.call(w, h, y0, y1));
    _jobMs += sw.elapsedMicroseconds / 1000;
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

  /// Trazos con los que se generaron las franjas (solo valen mientras la tanda tenga esos mismos).
  List<Stroke>? imageStrokes;

  /// Tamaño en píxeles que haría falta ahora.
  int wantW = 0, wantH = 0;

  /// Graba las filas [y0, y1) de la tanda (con los trazos de la última pintura) a [w] x [h] píxeles; null si ahora no
  /// se puede (trazos ocultos).
  ui.Picture? Function(int w, int h, int y0, int y1)? record;

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

  /// Cambió la cantidad de franjas de la tanda: lo generado no encaja.
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

  /// Suelta todo y cancela lo pendiente. No avisa: se llama también al pintar.
  void invalidate() {
    _gen++;
    _cancelTimer();
    _cache._ready.remove(this);
    for (var i = 0; i < strips.length; i++) {
      strips[i]?.image.dispose();
      strips[i] = null;
    }
    imageStrokes = null;
    refused = false;
    evicted = false;
    blocked = false;
  }

  /// Desalojo por falta de lugar: suelta las franjas y avisa (el pintor deja de usarlas).
  void evict({bool notify = true}) {
    _gen++;
    for (var i = 0; i < strips.length; i++) {
      strips[i]?.image.dispose();
      strips[i] = null;
    }
    imageStrokes = null;
    refused = false;
    evicted = true;
    if (notify) notifyListeners();
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
