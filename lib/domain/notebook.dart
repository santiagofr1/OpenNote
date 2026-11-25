import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'paper_layout.dart';
import 'folders.dart';
import 'outline.dart';
import 'values.dart';

/// Ancho inicial (y mínimo) de un lienzo infinito, en unidades lógicas.
const kCanvasW0 = 2000.0;

/// Ancho nuevo del lienzo de ancho [canvasW] si el contenido llega hasta [right]: crece de a 500 cuando el borde queda a
/// menos de 400 del final, dejando 800 de aire. Nunca achica.
double grownCanvasW(double canvasW, double right) =>
    right > canvasW - 400 ? ((right + 800) / 500).ceil() * 500.0 : canvasW;

/// Una hoja del cuaderno: lo que se guarda en `notebook.json` (el contenido está en su `.sheet`).
class SheetMeta {
  final String id;
  String title; // opcional, vacío si no tiene
  bool bookmark;
  String bg; // lined | grid | dots | mm | axes | blank | plantillas de la app | image (ver backgrounds.dart)
  String? image; // archivo de media/ del fondo (solo con bg == 'image')
  String paper; // color del papel
  double spacing; // interlineado / paso de la cuadrícula en mm (ver paper_layout.dart)
  String size; // a4 | a3 | a5 (ver paper_layout.dart)
  int rev; // sube cada vez que cambia el contenido guardado
  int updated; // ms epoch, para sincronizar algún día
  String section; // id de la sección a la que pertenece ('' = sin decir: es de la primera, ver [Notebook.loadSheetsJson])
  List<Heading> heads; // títulos del índice que marcan cosas de esta hoja
  SheetMeta(this.id,
      {this.title = '',
      this.bookmark = false,
      this.bg = 'lined',
      this.image,
      this.paper = '#fffefb',
      double? spacing,
      this.size = 'a4',
      this.rev = 0,
      this.updated = 0,
      this.section = '',
      List<Heading>? heads})
      : spacing = spacing ?? defaultSpacing(bg),
        heads = heads ?? [];

  /// Cambia el fondo; el espaciado vuelve al por defecto si el actual no existe en el fondo nuevo.
  void setBg(String v) {
    bg = v;
    if (v != 'image') image = null;
    spacing = validSpacing(v, spacing);
  }

  /// Con [id] nuevo (duplicar la hoja) los títulos del índice no se copian: siguen marcando lo de la hoja original.
  SheetMeta copy({String? id, String? title, bool? bookmark}) => SheetMeta(id ?? this.id,
      title: title ?? this.title,
      bookmark: bookmark ?? this.bookmark,
      bg: bg,
      image: image,
      paper: paper,
      spacing: spacing,
      size: size,
      rev: rev,
      updated: updated,
      section: section,
      heads: id != null ? null : [for (final h in heads) h.copy()]);

  factory SheetMeta.fromJson(Map j) => SheetMeta(
        j['id'] as String,
        title: (j['title'] ?? '') as String,
        bookmark: (j['bookmark'] ?? false) as bool,
        bg: (j['bg'] ?? 'lined') as String,
        image: j['image'] as String?,
        paper: (j['paper'] ?? '#fffefb') as String,
        spacing: (j['spacing'] as num?)?.toDouble(), // los archivos viejos no lo tienen: el por defecto del fondo
        size: validPaperSize(j['size']), // los archivos viejos no lo tienen: A4
        rev: (j['rev'] ?? 0) as int,
        updated: (j['updated'] ?? 0) as int,
        section: (j['section'] ?? '') as String, // los archivos viejos no la tienen
        heads: [for (final h in (j['heads'] as List? ?? const [])) Heading.fromJson(h as Map)],
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (bookmark) 'bookmark': true,
        'bg': bg,
        if (image != null) 'image': image,
        'paper': paper,
        'spacing': spacing,
        if (size != 'a4') 'size': size,
        'rev': rev,
        'updated': updated,
        if (section.isNotEmpty) 'section': section,
        if (heads.isNotEmpty) 'heads': [for (final h in heads) h.toJson()],
      };
}

/// Id de la sección que se inventa para los cuadernos sin secciones. Es FIJO (no aleatorio) para que dos
/// dispositivos que sincronizan el mismo cuaderno viejo no se inventen dos "General" distintas.
const kGeneralSection = 'general';

/// Una sección del cuaderno (como las hojas de Excel): tiene sus propias hojas. Va en `notebook.json`.
class Section {
  final String id;
  String name;
  int updated; // ms epoch (la fusión de la sync se queda con la más nueva)
  int last; // índice de la última hoja vista dentro de esta sección
  Section(this.id, this.name, {this.updated = 0, this.last = 0});

  factory Section.fromJson(Map j) => Section(
        j['id'] as String,
        ((j['name'] ?? '') as String).isEmpty ? 'Sección' : j['name'] as String,
        updated: (j['updated'] ?? 0) as int,
        last: (j['last'] ?? 0) as int,
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'updated': updated, 'last': last};
  Section copy() => Section(id, name, updated: updated, last: last);
}

/// Un cuaderno: varias secciones, cada una con su tira continua de hojas. En `index.json` va todo menos las hojas y
/// las secciones, que viven en `notebooks/<id>/notebook.json` (la [Storage] los completa al leer el índice).
///
/// En memoria, [sheets] tiene SOLO las hojas de la sección activa (así `NotebookDoc` y el editor no se enteran de que
/// hay secciones: los índices y las coordenadas globales siguen siendo las de la tira que se ve). Las hojas de las
/// demás secciones están en [otherSheets] y nadie las toca mientras se edita.
class Notebook {
  final String id;
  String name;
  final List<SheetMeta> sheets; // en orden; solo las de la sección activa
  final List<SheetMeta> otherSheets = []; // las de las otras secciones, agrupadas en el orden de las secciones
  final List<Section> sections; // en orden; nunca vacía
  String active; // id de la sección abierta
  String bg, paper; // estilo de las hojas nuevas
  String? image; // fondo de imagen de las hojas nuevas (con bg == 'image')
  double spacing; // espaciado (mm) de las hojas nuevas
  String size; // tamaño de las hojas nuevas
  int updated; // última edición (ms)
  int last; // índice de la última hoja vista (dentro de la sección activa)
  bool favorite;
  String? pin; // hash del PIN (ver hashPin), si está bloqueado
  String? folder; // id de la carpeta donde está (null = inicio)
  bool canvas; // lienzo infinito: sin cortes, crece hacia abajo y a la derecha (fijo desde que se crea)
  double canvasW; // ancho del lienzo en unidades lógicas (solo crece); kW es el ancho de una hoja A4
  Notebook(this.id, this.name,
      {List<SheetMeta>? sheets,
      List<Section>? sections,
      String? active,
      this.bg = 'lined',
      this.image,
      this.paper = '#fffefb',
      double? spacing,
      this.size = 'a4',
      this.updated = 0,
      this.last = 0,
      this.favorite = false,
      this.pin,
      this.folder,
      this.canvas = false,
      this.canvasW = kCanvasW0})
      : sheets = sheets ?? [],
        sections = sections == null || sections.isEmpty ? [Section(kGeneralSection, 'General')] : sections,
        active = active ?? (sections == null || sections.isEmpty ? kGeneralSection : sections.first.id),
        spacing = spacing ?? defaultSpacing(bg);

  /// Cuaderno nuevo con una hoja en blanco.
  factory Notebook.create(String name, {bool canvas = false}) {
    final nb = Notebook(newId('n'), name, canvas: canvas, bg: canvas ? 'blank' : 'lined');
    nb.sheets.add(nb.newSheet());
    return nb;
  }

  /// Hoja nueva con el estilo del cuaderno, de la sección [section] (o la activa). No la agrega.
  SheetMeta newSheet({String? section}) =>
      SheetMeta(newId('h'),
          bg: canvas ? 'blank' : bg, image: canvas ? null : image, paper: paper, spacing: spacing, size: size, section: section ?? active);

  // ---------- secciones ----------
  Section get activeSection => sectionById(active) ?? sections.first;
  Section? sectionById(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Cantidad de hojas de todo el cuaderno (todas las secciones).
  int get totalSheets => sheets.length + otherSheets.length;

  /// Cantidad de hojas de la sección [id].
  int sheetCountOf(String id) => id == activeSection.id ? sheets.length : otherSheets.where((m) => m.section == id).length;

  /// Todas las hojas del cuaderno, agrupadas en el orden de las secciones (lo que se escribe en `notebook.json`).
  List<SheetMeta> get allSheets {
    final act = activeSection.id;
    return [
      for (final s in sections)
        if (s.id == act) ...sheets else ...otherSheets.where((m) => m.section == s.id)
    ];
  }

  /// Las hojas de la sección [id] (si es la activa, las mismas de [sheets]).
  List<SheetMeta> sheetsOf(String id) => id == activeSection.id ? sheets : [for (final m in otherSheets) if (m.section == id) m];

  /// Reparte [all] entre [sheets] (las de la sección activa) y [otherSheets], agrupadas por el orden de las secciones.
  /// Es estable: dentro de cada sección las hojas quedan en el orden en que venían (la fusión de la sync las puede
  /// intercalar). Una hoja sin sección, o de una que no existe, es de la primera.
  void _regroup(List<SheetMeta> all) {
    final first = sections.first.id, act = activeSection.id;
    for (final m in all) {
      if (sectionById(m.section) == null) m.section = first;
    }
    sheets.clear();
    otherSheets.clear();
    for (final s in sections) {
      (s.id == act ? sheets : otherSheets).addAll(all.where((m) => m.section == s.id));
    }
  }

  /// Completa secciones y hojas con lo que dice un `notebook.json` ([j] ya decodificado). Los archivos viejos (sin
  /// `sections`) tienen una sola sección "General" con id fijo.
  void loadSheetsJson(Map j) {
    final secs = <Section>[];
    for (final e in (j['sections'] as List? ?? const [])) {
      if (e is Map && e['id'] is String && (e['id'] as String).isNotEmpty && !secs.any((s) => s.id == e['id'])) secs.add(Section.fromJson(e));
    }
    if (secs.isEmpty) secs.add(Section(kGeneralSection, 'General'));
    final all = [for (final s in (j['sheets'] as List)) SheetMeta.fromJson(s as Map)];
    sections
      ..clear()
      ..addAll(secs);
    active = secs.any((s) => s.id == j['active']) ? j['active'] as String : secs.first.id;
    _regroup(all);
    if (last == 0) last = activeSection.last; // sin dato de este dispositivo (el índice): el del archivo
    last = last.clamp(0, sheets.isEmpty ? 0 : sheets.length - 1);
  }

  /// Vacía las hojas y deja las secciones como un cuaderno nuevo (para releer un `notebook.json` roto o faltante).
  void clearSheets() {
    sheets.clear();
    otherSheets.clear();
  }

  /// Pasa a la sección [id]: guarda en la que se deja la última hoja vista, y en [sheets] quedan las de [id]. Una
  /// sección sin hojas (la dejó así una fusión de la sync) recibe una en blanco. OJO: cambia el contenido de [sheets]:
  /// el `NotebookDoc` que estaba abierto ya no vale (hay que reabrir con `Storage.openNotebook`).
  void activate(String id) {
    final target = sectionById(id);
    if (target == null || target.id == activeSection.id) return;
    activeSection.last = last.clamp(0, sheets.isEmpty ? 0 : sheets.length - 1);
    final all = allSheets;
    active = id;
    _regroup(all);
    if (sheets.isEmpty) sheets.add(newSheet());
    last = target.last.clamp(0, sheets.length - 1);
  }

  /// Agrega una sección al final con una hoja en blanco (del estilo del cuaderno). No la abre.
  Section addSection(String name) {
    final s = Section(newId('c'), name, updated: DateTime.now().millisecondsSinceEpoch);
    sections.add(s);
    otherSheets.add(newSheet(section: s.id));
    return s;
  }

  void renameSection(String id, String name) {
    final s = sectionById(id);
    if (s == null) return;
    s.name = name;
    s.updated = DateTime.now().millisecondsSinceEpoch;
  }

  /// Mueve la sección [id] [delta] lugares (−1 sube, +1 baja). Falso si no se puede.
  bool moveSection(String id, int delta) {
    final i = sections.indexWhere((s) => s.id == id), j = i + delta;
    if (i < 0 || j < 0 || j >= sections.length) return false;
    final all = allSheets;
    sections.insert(j, sections.removeAt(i));
    sections[j].updated = DateTime.now().millisecondsSinceEpoch;
    _regroup(all);
    return true;
  }

  /// Saca la sección [id] y devuelve sus hojas (el guardado borra sus archivos). No se puede sacar la activa (hay que
  /// pasar a otra antes) ni la última que queda: en ese caso devuelve null.
  List<SheetMeta>? removeSection(String id) {
    if (sections.length < 2 || id == activeSection.id || sectionById(id) == null) return null;
    final gone = [for (final m in otherSheets) if (m.section == id) m];
    otherSheets.removeWhere((m) => m.section == id);
    sections.removeWhere((s) => s.id == id);
    return gone;
  }

  /// Copia las secciones y hojas de [src] en este cuaderno (duplicar): mismos ids de hoja, porque los archivos se copian.
  void copySectionsFrom(Notebook src) {
    sections
      ..clear()
      ..addAll(src.sections.map((s) => s.copy()));
    active = src.active;
    sheets
      ..clear()
      ..addAll(src.sheets.map((m) => m.copy()));
    otherSheets
      ..clear()
      ..addAll(src.otherSheets.map((m) => m.copy()));
    last = src.last;
  }

  /// Marca la edición ahora (ordena la biblioteca por esto).
  void touch() => updated = DateTime.now().millisecondsSinceEpoch;

  factory Notebook.fromJson(Map n) => Notebook(
        n['id'] as String,
        n['name'] as String,
        bg: (n['bg'] ?? 'lined') as String,
        image: n['image'] as String?,
        paper: (n['paper'] ?? '#fffefb') as String,
        spacing: (n['spacing'] as num?)?.toDouble(),
        size: validPaperSize(n['size']),
        updated: (n['updated'] ?? 0) as int,
        last: (n['last'] ?? 0) as int,
        favorite: (n['favorite'] ?? false) as bool,
        pin: n['pin'] as String?,
        folder: n['folder'] as String?,
        canvas: (n['canvas'] ?? false) as bool,
        canvasW: ((n['canvasW'] as num?)?.toDouble() ?? kCanvasW0).clamp(kCanvasW0, 1e6).toDouble(),
      );

  /// Entrada del índice (sin las hojas).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'updated': updated,
        'bg': bg,
        if (image != null) 'image': image,
        'paper': paper,
        'spacing': spacing,
        if (size != 'a4') 'size': size,
        'last': last,
        if (favorite) 'favorite': true,
        if (pin != null) 'pin': pin,
        if (folder != null) 'folder': folder,
        if (canvas) 'canvas': true,
        if (canvas) 'canvasW': canvasW,
      };

  /// Lo que va en `notebook.json`: las secciones en orden, la activa y TODAS las hojas (de todas las secciones),
  /// agrupadas por sección. Una app vieja que lo abra ve una sola tira con todas las hojas y, si guarda, pierde
  /// la agrupación (no los datos).
  Map<String, dynamic> sheetsJson() {
    for (final m in sheets) {
      m.section = active; // las hojas de [sheets] son de la sección activa
    }
    activeSection.last = last.clamp(0, sheets.isEmpty ? 0 : sheets.length - 1);
    return {
      'format': kFormat,
      'sections': sections.map((s) => s.toJson()).toList(),
      'active': activeSection.id,
      'sheets': allSheets.map((s) => s.toJson()).toList(),
    };
  }

  /// Versión del formato en disco.
  static const kFormat = 3;
}

/// index.json: todos los cuadernos.
class NotesIndex {
  int rev;
  String? last; // id del último cuaderno abierto
  final List<Notebook> notebooks;
  final List<Folder> folders; // opcional en el archivo: los índices sin carpetas siguen cargando
  NotesIndex({this.rev = 0, this.last, List<Notebook>? notebooks, List<Folder>? folders})
      : notebooks = notebooks ?? [],
        folders = folders ?? [];

  factory NotesIndex.fromJson(Map j) => NotesIndex(
        rev: (j['rev'] ?? 0) as int,
        last: j['last'] as String?,
        notebooks: [for (final n in (j['notebooks'] as List? ?? [])) Notebook.fromJson(n as Map)],
        folders: [for (final f in (j['folders'] as List? ?? [])) Folder.fromJson(f as Map)],
      )..repairFolders();
  Map<String, dynamic> toJson() => {
        'format': Notebook.kFormat,
        'rev': rev,
        'last': last,
        'notebooks': notebooks.map((n) => n.toJson()).toList(),
        if (folders.isNotEmpty) 'folders': folders.map((f) => f.toJson()).toList(),
      };
}

/// PIN: se guarda solo su hash.
/// Los nombres que puede tener el cuaderno de ejemplo que crea cada instalación (uno por idioma; ver la clave
/// `librarySampleNotebook` de los .arb): la sincronización descarta el que sigue intacto. Si se traduce, agregar acá.
const kSampleNotebookNames = {'Mi cuaderno', 'My notebook', 'Meu caderno'};

String hashPin(String pin) => sha256.convert(utf8.encode('apuntes:$pin')).toString();
