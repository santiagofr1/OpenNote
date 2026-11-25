// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../l10n/l10n.dart';

const _kMaxTitle = 120, _kMaxLevel = 9;

/// Diálogo "Agregar al índice": nombre y nivel del título. [recognizing] es la lectura de la letra, que llega después
/// (completa el nombre si el usuario todavía no escribió nada). Devuelve null si se cancela.
Future<({String title, int level})?> showHeadingDialog(BuildContext context,
        {required String initialTitle, required int initialLevel, Future<String?>? recognizing, bool downloading = false}) =>
    showDialog<({String title, int level})>(
      context: context,
      builder: (_) => _HeadingDialog(
          initialTitle: initialTitle, initialLevel: initialLevel, recognizing: recognizing, downloading: downloading),
    );

class _HeadingDialog extends StatefulWidget {
  final String initialTitle;
  final int initialLevel;
  final Future<String?>? recognizing;
  final bool downloading;
  const _HeadingDialog({required this.initialTitle, required this.initialLevel, this.recognizing, this.downloading = false});
  @override
  State<_HeadingDialog> createState() => _HeadingDialogState();
}

class _HeadingDialogState extends State<_HeadingDialog> {
  late final _ctrl = TextEditingController(text: widget.initialTitle);
  final _focus = FocusNode();
  late int _level = widget.initialLevel.clamp(1, _kMaxLevel);
  late bool _waiting = widget.recognizing != null;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.recognizing?.then((text) {
      if (!mounted) return;
      setState(() {
        _waiting = false;
        if (text == null || text.trim().isEmpty) {
          _failed = true;
        } else if (_ctrl.text.trim().isEmpty) {
          // se puede pisar de una: queda todo seleccionado
          _ctrl.value = TextEditingValue(text: text.trim(), selection: TextSelection(baseOffset: 0, extentOffset: text.trim().length));
        }
      });
      _focus.requestFocus();
    }, onError: (Object _) {
      if (mounted) {
        setState(() {
          _waiting = false;
          _failed = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ok() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, (title: t.length > _kMaxTitle ? t.substring(0, _kMaxTitle) : t, level: _level));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final help = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    return AlertDialog(
      scrollable: true,
      title: Text(context.l10n.headingTitle),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListenableBuilder(
            listenable: _ctrl,
            builder: (_, _) => TextField(
              key: const Key('headingName'),
              controller: _ctrl,
              focusNode: _focus,
              autofocus: widget.recognizing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: _failed ? context.l10n.headingFailed : context.l10n.headingHint),
              onSubmitted: (_) => _ok(),
            ),
          ),
          if (_waiting)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      widget.downloading
                          ? context.l10n.headingDownloading
                          : context.l10n.headingReading,
                      style: help),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                key: const Key('headingLevelDown'),
                tooltip: context.l10n.headingMoreImportant,
                onPressed: _level > 1 ? () => setState(() => _level--) : null,
                icon: const Icon(Symbols.remove, weight: 300)),
            SizedBox(
              width: 84,
              child: Text(context.l10n.headingLevel(_level),
                  key: const Key('headingLevel'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            IconButton(
                key: const Key('headingLevelUp'),
                tooltip: context.l10n.headingLessImportant,
                onPressed: _level < _kMaxLevel ? () => setState(() => _level++) : null,
                icon: const Icon(Symbols.add, weight: 300)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        ListenableBuilder(
          listenable: _ctrl,
          builder: (_, _) => FilledButton(
              key: const Key('headingOk'), onPressed: _ctrl.text.trim().isEmpty ? null : _ok, child: Text(context.l10n.headingAdd)),
        ),
      ],
    );
  }
}
