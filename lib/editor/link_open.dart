import 'package:url_launcher/url_launcher.dart';

/// Abre una web en el navegador. Es una variable para que los tests la reemplacen (no deben abrir el navegador).
Future<bool> Function(Uri) linkLauncher = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
