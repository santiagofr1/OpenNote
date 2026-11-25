import 'package:flutter/material.dart';

import '../domain/domain.dart';
import '../l10n/l10n.dart';

enum _Kind { web, sheet, nb }

/// Elegir (o cambiar) a dónde lleva un link: una página web, una hoja de este cuaderno u otro cuaderno.
/// [sheets] y [notebooks] son las opciones (id y nombre); [initial] es el destino actual al editar.
/// Devuelve el destino (`https://…`, `sheet:<id>` o `nb:<id>`) o null si se cancela.
Future<String?> showLinkDialog(
  BuildContext context, {
  String initial = '',
  required List<({String id, String label})> sheets,
  required List<({String id, String label})> notebooks,
}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _LinkDialog(initial: initial, sheets: sheets, notebooks: notebooks),
    );

class _LinkDialog extends StatefulWidget {
  final String initial;
  final List<({String id, String label})> sheets, notebooks;
  const _LinkDialog({required this.initial, required this.sheets, required this.notebooks});
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final url = TextEditingController();
  var kind = _Kind.web;
  String? sheetId, nbId;

  @override
  void initState() {
    super.initState();
    switch (parseLink(widget.initial)) {
      case LinkWeb():
        url.text = widget.initial.trim();
      case LinkSheet(:final id):
        kind = _Kind.sheet;
        sheetId = id;
      case LinkNotebook(:final id):
        kind = _Kind.nb;
        nbId = id;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  /// El destino que queda con lo elegido ('' si todavía no se puede crear).
  String get result => switch (kind) {
        _Kind.web => normalizeUrl(url.text),
        _Kind.sheet => sheetId == null ? '' : 'sheet:$sheetId',
        _Kind.nb => nbId == null ? '' : 'nb:$nbId',
      };

  Widget _list(List<({String id, String label})> items, String? picked, String keyPrefix, ValueChanged<String> onPick,
      String empty) {
    if (items.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(empty));
    return SizedBox(
      height: 260,
      child: ListView(children: [
        for (final it in items)
          ListTile(
            key: Key('$keyPrefix-${it.id}'),
            dense: true,
            selected: it.id == picked,
            title: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: it.id == picked ? const Icon(Icons.check, size: 20) : null,
            onTap: () => setState(() => onPick(it.id)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(_Kind k, String label, Key key) =>
        ChoiceChip(key: key, label: Text(label), selected: kind == k, onSelected: (_) => setState(() => kind = k));
    return AlertDialog(
      scrollable: true,
      title: Text(widget.initial.isEmpty ? context.l10n.linkTitle : context.l10n.linkTitleEdit),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            chip(_Kind.web, context.l10n.linkKindWeb, const Key('linkKindWeb')),
            chip(_Kind.sheet, context.l10n.linkKindSheet, const Key('linkKindSheet')),
            chip(_Kind.nb, context.l10n.linkKindNotebook, const Key('linkKindNb')),
          ]),
          const SizedBox(height: 12),
          switch (kind) {
            _Kind.web => TextField(
                key: const Key('linkUrl'),
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(hintText: context.l10n.linkUrlHint),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => result.isEmpty ? null : Navigator.pop(context, result),
              ),
            _Kind.sheet => _list(widget.sheets, sheetId, 'linkSheet', (id) => sheetId = id, context.l10n.linkNoSheets),
            _Kind.nb => _list(widget.notebooks, nbId, 'linkNb', (id) => nbId = id, context.l10n.linkNoNotebooks),
          },
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        FilledButton(
          key: const Key('linkOk'),
          onPressed: result.isEmpty ? null : () => Navigator.pop(context, result),
          child: Text(context.l10n.commonCreate),
        ),
      ],
    );
  }
}
