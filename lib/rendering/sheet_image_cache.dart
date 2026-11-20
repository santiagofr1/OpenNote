import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/domain.dart';

/// Caché de imágenes de la tinta: una tanda de tinta de una hoja que no cambia se rasteriza UNA vez a un [ui.Image]
/// y mientras se scrollea se dibuja esa imagen (una sola textura) en vez de volver a rasterizar decenas de miles
/// de puntos en cada cuadro (Impeller no tiene caché de pictures).
///
/// Cuándo se genera: una tanda se pinta vectorial hasta que queda quieta [quiet] (300 ms); recién ahí se graba y se
/// pasa a imagen, de a una por vez y sin interrumpir al lápiz ([busy]). Cuándo se invalida: cuando cambia su hoja
/// ([invalidateSheet], lo llama el editor junto con la versión de la hoja), cuando la tanda tiene trazos distintos, cuando
/// hay trazos ocultos por un arrastre, o cuando el tamaño en píxeles pedido es otro (zoom): ahí sigue usando la imagen
/// vieja (estirada) hasta que se regenera, así el pellizco no vuelve a rasterizar todo.
///
/// Memoria (GPU): una hoja a 1200 px de ancho ocupa 1200 x 1700 x 4 B ≈ 8 MB. Máximo [maxImages] imágenes y [maxBytes]
/// en total (lo que se alcance primero); y ninguna imagen pasa del tope de ancho que pone el editor (2x el ancho de
/// pantalla): más zoom que eso se dibuja vectorial. Se prefiere soltar las de hojas que no están armadas
/// ([protectedSheets] son las que no se tocan); si no entra, esa tanda queda vectorial.
class SheetImageCache {
  int maxImages;
  int maxBytes;

  /// Tandas con menos puntos que esto son baratas de rasterizar: no valen una imagen.
  int minPoints;
  Duration quiet;

  /// Si devuelve true (hay lápiz en curso, pellizco...) la generación se posterga.
  bool Function()? busy;

  /// Hojas armadas (ids): sus imágenes no se sueltan para hacerle lugar a otra.
  Set<String> protectedSheets = const {};

  /// Cuántas imágenes se generaron en total (para los tests).
  int generated = 0;

  static int defaultMinPoints = 1500;

  final _entries = <String, InkImage>{};
  final _queue = <InkImage>[];
  bool _running = false, _disposed = false;
  int _stamp = 0;

  SheetImageCache({this.maxImages = 6, this.maxBytes = 64 << 20, int? minPoints, this.quiet = const Duration(milliseconds: 300)})
      : minPoints = minPoints ?? defaultMinPoints;

  /// Entrada de la tanda [key] de la hoja [sheetId] (se crea vacía).
  InkImage entry(String key, String sheetId) => _entries.putIfAbsent(key, () => InkImage._(this, key, sheetId));

  /// Cambió algo de la hoja: sus imágenes ya no sirven.
  void invalidateSheet(String sheetId) {
    for (final e in _entries.values) {
      if (e.sheetId == sheetId) e.invalidate();
    }
  }

  void invalidateAll() {
    for (final e in _entries.values) {
      e.invalidate();
    }
  }

  /// La hoja se descargó: se sueltan sus imágenes y entradas.
  void dropSheet(String sheetId) {
    final gone = [for (final e in _entries.values) if (e.sheetId == sheetId) e];
    for (final e in gone) {
      _entries.remove(e.key);
      e._dispose();
    }
  }

  void clear() {
    for (final e in _entries.values) {
      e._dispose();
    }
    _entries.clear();
    _queue.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  /// La hoja tiene al menos una imagen lista y del tamaño que se pide ahora (se dibuja la imagen, no los trazos).
  bool usesImage(String sheetId) => _entries.values.any((e) => e.sheetId == sheetId && e.image != null && !e.needsImage);

  int get imageCount => _entries.values.where((e) => e.image != null).length;
  int get bytes => _entries.values.fold(0, (a, e) => a + e.bytes);

  void _enqueue(InkImage e) {
    if (_disposed || e._gone) return;
    _queue.add(e);
    if (!_running) _pump();
  }

  Future<void> _pump() async {
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final e = _queue.removeAt(0);
        e._queued = false;
        await _generate(e);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _generate(InkImage e) async {
    if (e._gone || !e.needsImage) return;
    if (busy?.call() ?? false) {
      e.schedule(); // hay lápiz o pellizco: más tarde
      return;
    }
    final rec = e.record, strokes = e.recStrokes;
    if (rec == null || strokes == null) return;
    final w = e.wantW, h = e.wantH, gen = e._gen;
    final pic = rec(w, h);
    if (pic == null) return; // hay trazos ocultos: se vuelve a pedir al pintar
    ui.Image img;
    try {
      img = await pic.toImage(w, h);
    } catch (err) {
      developer.log('no se pudo rasterizar la tanda ${e.key}: $err', name: 'editor', level: 900);
      e.refused = true;
      return;
    } finally {
      pic.dispose();
    }
    if (_disposed || e._gone || gen != e._gen || w != e.wantW || h != e.wantH) {
      img.dispose(); // cambió mientras se rasterizaba
      if (!_disposed && !e._gone && e.needsImage) e.schedule();
      return;
    }
    if (!_makeRoom(e, w * h * 4)) {
      img.dispose();
      e.refused = true;
      return;
    }
    e.image?.dispose();
    e.image = img;
    e.imageStrokes = strokes;
    e.stamp = ++_stamp;
    generated++;
    e.notifyListeners(); // las pinturas de esa tanda se repintan con la imagen
  }

  /// Suelta imágenes viejas de hojas no armadas hasta que [need] bytes más entren. false si no se puede.
  bool _makeRoom(InkImage e, int need) {
    while (true) {
      final others = [for (final o in _entries.values) if (o != e && o.image != null) o];
      final total = others.fold(need, (a, o) => a + o.bytes);
      if (others.length + 1 <= maxImages && total <= maxBytes) return true;
      InkImage? victim;
      for (final o in others) {
        if (protectedSheets.contains(o.sheetId)) continue;
        if (victim == null || o.stamp < victim.stamp) victim = o;
      }
      if (victim == null) return false;
      victim.invalidate();
    }
  }
}

/// Imagen de una tanda de tinta de una hoja. Es un [Listenable]: avisa cuando hay una imagen nueva.
class InkImage extends ChangeNotifier {
  final SheetImageCache _cache;
  final String key, sheetId;
  ui.Image? image;

  /// Trazos con los que se generó [image] (la imagen solo vale mientras la tanda tenga esos mismos).
  List<Stroke>? imageStrokes;

  /// Tamaño en píxeles que haría falta ahora.
  int wantW = 0, wantH = 0;

  /// Graba la tanda (con los trazos de la última pintura) a ese tamaño; null si ahora no se puede (trazos ocultos).
  ui.Picture? Function(int w, int h)? record;
  List<Stroke>? recStrokes;

  /// No entró en el presupuesto de memoria (o falló): queda vectorial hasta que cambie algo.
  bool refused = false;
  int stamp = 0;
  Timer? _timer;
  bool _queued = false, _gone = false;
  int _gen = 0;

  InkImage._(this._cache, this.key, this.sheetId);

  int get bytes => image == null ? 0 : image!.width * image!.height * 4;

  /// Falta imagen, o la que hay es de otro tamaño (zoom).
  bool get needsImage => image == null || image!.width != wantW || image!.height != wantH;

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
    if (_gone || _cache._disposed || _timer != null || _queued || refused || !needsImage) return;
    _timer = Timer(_cache.quiet, () {
      _timer = null;
      _queued = true;
      _cache._enqueue(this);
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Suelta la imagen y cancela lo pendiente. No avisa: se llama también al pintar.
  void invalidate() {
    _gen++;
    _cancelTimer();
    image?.dispose();
    image = null;
    imageStrokes = null;
    refused = false;
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
