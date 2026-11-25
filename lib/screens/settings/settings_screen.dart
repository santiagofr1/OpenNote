import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/storage.dart';
import '../../data/updates.dart';
import '../../editor/link_open.dart';
import '../../l10n/l10n.dart';
import '../../l10n/language_settings.dart';

const kSourceUrl = 'https://github.com/santiagofr1/Vynote';
const kPrivacyUrl = 'https://github.com/santiagofr1/Vynote/blob/main/PRIVACY.md';

/// Nombre de cada idioma, siempre en su propio idioma (no se traduce).
const kLanguageNames = {'es': 'Español', 'en': 'English', 'pt': 'Português'};

/// Ajustes: idiomas (de la app y de la escritura a mano), actualizaciones y "Acerca de". Se abre desde el menú ⋮ de la
/// biblioteca; nada de esto está dentro del cuaderno.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.updates, required this.onCheckUpdates});

  /// Donde se guardan las preferencias (prefs.json).
  final Storage store;

  /// Las preferencias de actualización (el interruptor las cambia y las guarda).
  final UpdatePrefs updates;

  /// "Buscar actualizaciones" a mano.
  final Future<void> Function() onCheckUpdates;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<String> _version = _loadVersion();

  Future<String> _loadVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      return '${i.version} (${i.buildNumber})';
    } catch (_) {
      return '?';
    }
  }

  Future<void> _open(String url) async {
    try {
      await linkLauncher(Uri.parse(url));
    } catch (_) {}
  }

  /// Diálogo con una opción por idioma (radio). Devuelve el valor elegido o null si se cierra sin elegir.
  Future<String?> _pick(String title, String current, List<(String, String)> options, String keyPrefix) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 360,
          child: RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (value, label) in options)
                RadioListTile<String>(key: Key('$keyPrefix-$value'), value: value, title: Text(label)),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonCancel))],
      ),
    );
  }

  Future<void> _pickAppLanguage() async {
    final lang = LanguageScope.of(context, listen: false);
    final v = await _pick(
      context.l10n.settingsAppLanguage,
      lang.appLanguage,
      [('system', context.l10n.settingsLanguageSystem), for (final e in kLanguageNames.entries) (e.key, e.value)],
      'appLang',
    );
    if (v == null) return;
    lang.appLanguage = v;
    await widget.store.savePrefs({'appLanguage': v});
  }

  Future<void> _pickInkLanguage() async {
    final lang = LanguageScope.of(context, listen: false);
    final v = await _pick(
      context.l10n.settingsInkLanguage,
      lang.inkLanguage,
      [('app', context.l10n.settingsInkSameAsApp), for (final e in kLanguageNames.entries) (e.key, e.value)],
      'inkLang',
    );
    if (v == null) return;
    lang.inkLanguage = v;
    await widget.store.savePrefs({'inkLanguage': v});
  }

  Future<void> _license(String version) async {
    showLicensePage(
      context: context,
      applicationName: 'Vynote',
      applicationVersion: version,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Symbols.edit_note, size: 48, weight: 300, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = LanguageScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final appName = lang.appLanguage == 'system' ? l.settingsLanguageSystem : kLanguageNames[lang.appLanguage]!;
    final inkName = lang.inkLanguage == 'app' ? l.settingsInkSameAsApp : kLanguageNames[lang.inkLanguage]!;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle, key: const Key('settingsTitle'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _section(l.settingsSectionLanguage),
          ListTile(
            key: const Key('settingsAppLanguage'),
            leading: const Icon(Symbols.language, weight: 300),
            title: Text(l.settingsAppLanguage),
            subtitle: Text(appName),
            onTap: _pickAppLanguage,
          ),
          ListTile(
            key: const Key('settingsInkLanguage'),
            leading: const Icon(Symbols.draw, weight: 300),
            title: Text(l.settingsInkLanguage),
            subtitle: Text(inkName),
            onTap: _pickInkLanguage,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 20, 4),
            child: Text(l.settingsInkHelp, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
          _section(l.settingsSectionUpdates),
          SwitchListTile(
            key: const Key('autoUpdates'),
            secondary: const Icon(Symbols.update, weight: 300),
            title: Text(l.settingsAutoUpdates),
            value: widget.updates.auto,
            onChanged: (v) {
              setState(() => widget.updates.auto = v);
              widget.store.savePrefs(widget.updates.toJson());
            },
          ),
          ListTile(
            key: const Key('checkUpdates'),
            leading: const Icon(Symbols.system_update, weight: 300),
            title: Text(l.settingsCheckUpdates),
            onTap: () => unawaited(widget.onCheckUpdates()),
          ),
          _section(l.settingsSectionAbout),
          FutureBuilder<String>(
            future: _version,
            builder: (context, snap) => ListTile(
              leading: const Icon(Symbols.info, weight: 300),
              title: Text(l.settingsVersion),
              subtitle: Text(snap.data ?? '', key: const Key('settingsVersion')),
            ),
          ),
          ListTile(
            key: const Key('settingsSource'),
            leading: const Icon(Symbols.code, weight: 300),
            title: Text(l.settingsSource),
            subtitle: const Text(kSourceUrl),
            onTap: () => _open(kSourceUrl),
          ),
          FutureBuilder<String>(
            future: _version,
            builder: (context, snap) => ListTile(
              key: const Key('settingsLicense'),
              leading: const Icon(Symbols.balance, weight: 300),
              title: Text(l.settingsLicense),
              subtitle: Text(l.settingsLicenseValue),
              onTap: () => _license(snap.data ?? ''),
            ),
          ),
          ListTile(
            key: const Key('settingsPrivacy'),
            leading: const Icon(Symbols.privacy_tip, weight: 300),
            title: Text(l.settingsPrivacy),
            onTap: () => _open(kPrivacyUrl),
          ),
        ],
      ),
    );
  }
}
