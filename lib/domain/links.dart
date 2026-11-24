import 'dart:ui';

import 'elements.dart';

/// A dónde lleva un link (el texto de un Item 'link'): una web, otra hoja del cuaderno u otro cuaderno.
sealed class LinkTarget {
  const LinkTarget();
}

class LinkWeb extends LinkTarget {
  final Uri uri;
  const LinkWeb(this.uri);
  @override
  bool operator ==(Object other) => other is LinkWeb && other.uri == uri;
  @override
  int get hashCode => uri.hashCode;
}

class LinkSheet extends LinkTarget {
  final String id;
  const LinkSheet(this.id);
  @override
  bool operator ==(Object other) => other is LinkSheet && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class LinkNotebook extends LinkTarget {
  final String id;
  const LinkNotebook(this.id);
  @override
  bool operator ==(Object other) => other is LinkNotebook && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Lee el destino guardado: `http(s)://…`, `sheet:<id>` o `nb:<id>`. null si no es ninguno.
LinkTarget? parseLink(String s) {
  final t = s.trim();
  if (t.startsWith('sheet:')) return t.length > 6 ? LinkSheet(t.substring(6)) : null;
  if (t.startsWith('nb:')) return t.length > 3 ? LinkNotebook(t.substring(3)) : null;
  final u = Uri.tryParse(t);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return null;
  return LinkWeb(u);
}

final _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
final _otherScheme = RegExp(r'^(mailto|javascript|data|file|tel|sms|intent):', caseSensitive: false);

/// Lo que se escribió como dirección, listo para guardar: sin espacios de los bordes y con 'https://' si no traía
/// esquema. Solo acepta http / https con un dominio (con punto, o localhost); si no, devuelve ''.
String normalizeUrl(String input) {
  final t = input.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s')) || _otherScheme.hasMatch(t)) return '';
  final s = _hasScheme.hasMatch(t) ? t : 'https://$t';
  final u = Uri.tryParse(s);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return '';
  final h = u.host;
  if (h.isEmpty || !(h.contains('.') || h == 'localhost') || h.startsWith('.') || h.endsWith('.')) return '';
  return s;
}

/// Texto corto para mostrar el destino. [sheetName] y [notebookName] dan el nombre por id (null = ya no existe).
String linkLabel(LinkTarget t, {String? Function(String id)? sheetName, String? Function(String id)? notebookName}) =>
    switch (t) {
      LinkWeb(:final uri) => '${uri.host}${uri.path == '/' ? '' : uri.path}',
      LinkSheet(:final id) => sheetName?.call(id) ?? 'Hoja que ya no existe',
      LinkNotebook(:final id) => notebookName?.call(id) ?? 'Cuaderno que ya no existe',
    };

// ---- links de las páginas de PDF importados (coordenadas del PDF: origen abajo a la izquierda, en puntos) ----

/// El punto [p] de la hoja (sobre el elemento PDF [it]) en coordenadas de su página de [pageSize] puntos, con el origen
/// ABAJO. null si [p] cae fuera del elemento.
Offset? pdfPointFor(Item it, Offset p, Size pageSize) {
  if (it.w <= 0 || it.h <= 0 || p.dx < it.x || p.dx > it.x + it.w || p.dy < it.y || p.dy > it.y + it.h) return null;
  return Offset((p.dx - it.x) / it.w * pageSize.width, pageSize.height - (p.dy - it.y) / it.h * pageSize.height);
}

/// El rectángulo de PDF ([left] <= [right], [top] >= [bottom], origen abajo) en unidades de la hoja, según donde
/// está el elemento PDF [it].
Rect itemRectForPdfRect(Item it, double left, double top, double right, double bottom, Size pageSize) {
  final kx = it.w / pageSize.width, ky = it.h / pageSize.height;
  return Rect.fromLTRB(it.x + left * kx, it.y + (pageSize.height - top) * ky, it.x + right * kx,
      it.y + (pageSize.height - bottom) * ky);
}
