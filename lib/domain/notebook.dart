import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Entrada de una página en el índice (el contenido está en `pages/<id>.json`).
class PageRef {
  final String id;
  String title;
  bool bookmark;
  PageRef(this.id, this.title, {this.bookmark = false});

  factory PageRef.fromJson(Map p) =>
      PageRef(p['id'] as String, p['title'] as String, bookmark: (p['bookmark'] ?? false) as bool);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, if (bookmark) 'bookmark': true};
}

class Notebook {
  final String id;
  String name;
  final List<PageRef> pages;
  int updated; // última edición (ms)
  String? last; // última página abierta
  bool favorite;
  String? pin; // hash del PIN (ver hashPin), si está bloqueado
  Notebook(this.id, this.name, this.pages, {this.updated = 0, this.last, this.favorite = false, this.pin});

  /// Marca la edición ahora (ordena la biblioteca por esto).
  void touch() => updated = DateTime.now().millisecondsSinceEpoch;

  factory Notebook.fromJson(Map n) => Notebook(
        n['id'] as String,
        n['name'] as String,
        [for (final p in (n['pages'] as List? ?? [])) PageRef.fromJson(p as Map)],
        updated: (n['updated'] ?? 0) as int,
        last: n['last'] as String?,
        favorite: (n['favorite'] ?? false) as bool,
        pin: n['pin'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'updated': updated,
        'last': last,
        if (favorite) 'favorite': true,
        if (pin != null) 'pin': pin,
        'pages': pages.map((p) => p.toJson()).toList(),
      };
}

/// index.json: todos los cuadernos y sus páginas.
class NotesIndex {
  int rev;
  String? last;
  final List<Notebook> notebooks;
  NotesIndex({this.rev = 0, this.last, List<Notebook>? notebooks}) : notebooks = notebooks ?? [];

  factory NotesIndex.fromJson(Map j) => NotesIndex(
        rev: (j['rev'] ?? 0) as int,
        last: j['last'] as String?,
        notebooks: [for (final n in (j['notebooks'] as List? ?? [])) Notebook.fromJson(n as Map)],
      );
  Map<String, dynamic> toJson() => {'rev': rev, 'last': last, 'notebooks': notebooks.map((n) => n.toJson()).toList()};
}

/// PIN: se guarda solo su hash.
String hashPin(String pin) => sha256.convert(utf8.encode('apuntes:$pin')).toString();
