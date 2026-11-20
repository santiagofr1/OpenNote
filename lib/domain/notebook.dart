import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'paper_layout.dart';
import 'folders.dart';
import 'values.dart';

/// Una hoja del cuaderno: lo que se guarda en `notebook.json` (el contenido está en su `.sheet`).
class SheetMeta {
  final String id;
  String title; // opcional, vacío si no tiene
  bool bookmark;
  String bg; // lined | grid | dots | blank
  String paper; // color del papel
  double spacing; // interlineado / paso de la cuadrícula en mm (ver paper_layout.dart)
  int rev; // sube cada vez que cambia el contenido guardado
  int updated; // ms epoch, para sincronizar algún día
  SheetMeta(this.id,
      {this.title = '',
      this.bookmark = false,
      this.bg = 'lined',
      this.paper = '#fffefb',
      double? spacing,
      this.rev = 0,
      this.updated = 0})
      : spacing = spacing ?? defaultSpacing(bg);

  /// Cambia el fondo; el espaciado vuelve al por defecto si el actual no existe en el fondo nuevo.
  void setBg(String v) {
    bg = v;
    spacing = validSpacing(v, spacing);
  }

  SheetMeta copy({String? id, String? title, bool? bookmark}) => SheetMeta(id ?? this.id,
      title: title ?? this.title,
      bookmark: bookmark ?? this.bookmark,
      bg: bg,
      paper: paper,
      spacing: spacing,
      rev: rev,
      updated: updated);

  factory SheetMeta.fromJson(Map j) => SheetMeta(
        j['id'] as String,
        title: (j['title'] ?? '') as String,
        bookmark: (j['bookmark'] ?? false) as bool,
        bg: (j['bg'] ?? 'lined') as String,
        paper: (j['paper'] ?? '#fffefb') as String,
        spacing: (j['spacing'] as num?)?.toDouble(), // los archivos viejos no lo tienen: el por defecto del fondo
        rev: (j['rev'] ?? 0) as int,
        updated: (j['updated'] ?? 0) as int,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (bookmark) 'bookmark': true,
        'bg': bg,
        'paper': paper,
        'spacing': spacing,
        'rev': rev,
        'updated': updated,
      };
}

/// Un cuaderno: una tira continua de hojas. En `index.json` va todo menos [sheets],
/// que viven en `notebooks/<id>/notebook.json` (la [Storage] los completa al leer el índice).
class Notebook {
  final String id;
  String name;
  final List<SheetMeta> sheets; // en orden
  String bg, paper; // estilo de las hojas nuevas
  double spacing; // espaciado (mm) de las hojas nuevas
  int updated; // última edición (ms)
  int last; // índice de la última hoja vista
  bool favorite;
  String? pin; // hash del PIN (ver hashPin), si está bloqueado
  String? folder; // id de la carpeta donde está (null = inicio)
  Notebook(this.id, this.name,
      {List<SheetMeta>? sheets,
      this.bg = 'lined',
      this.paper = '#fffefb',
      double? spacing,
      this.updated = 0,
      this.last = 0,
      this.favorite = false,
      this.pin,
      this.folder})
      : sheets = sheets ?? [],
        spacing = spacing ?? defaultSpacing(bg);

  /// Cuaderno nuevo con una hoja en blanco.
  factory Notebook.create(String name) {
    final nb = Notebook(newId('n'), name);
    nb.sheets.add(nb.newSheet());
    return nb;
  }

  /// Hoja nueva con el estilo del cuaderno (no la agrega).
  SheetMeta newSheet() => SheetMeta(newId('h'), bg: bg, paper: paper, spacing: spacing);

  /// Marca la edición ahora (ordena la biblioteca por esto).
  void touch() => updated = DateTime.now().millisecondsSinceEpoch;

  factory Notebook.fromJson(Map n) => Notebook(
        n['id'] as String,
        n['name'] as String,
        bg: (n['bg'] ?? 'lined') as String,
        paper: (n['paper'] ?? '#fffefb') as String,
        spacing: (n['spacing'] as num?)?.toDouble(),
        updated: (n['updated'] ?? 0) as int,
        last: (n['last'] ?? 0) as int,
        favorite: (n['favorite'] ?? false) as bool,
        pin: n['pin'] as String?,
        folder: n['folder'] as String?,
      );

  /// Entrada del índice (sin las hojas).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'updated': updated,
        'bg': bg,
        'paper': paper,
        'spacing': spacing,
        'last': last,
        if (favorite) 'favorite': true,
        if (pin != null) 'pin': pin,
        if (folder != null) 'folder': folder,
      };

  /// Lo que va en `notebook.json`.
  Map<String, dynamic> sheetsJson() => {'format': kFormat, 'sheets': sheets.map((s) => s.toJson()).toList()};

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
String hashPin(String pin) => sha256.convert(utf8.encode('apuntes:$pin')).toString();
