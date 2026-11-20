/// Versión de la app con formato `major.minor.patch` (por ejemplo 1.0.12).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);
  final int major, minor, patch;

  static final _re = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

  /// Acepta `1.0.12` y el tag `v1.0.12`. Devuelve null si no tiene ese formato exacto:
  /// sufijos como `-beta` o `+5`, partes de menos o de más, o texto cualquiera.
  static AppVersion? tryParse(String? s) {
    final m = s == null ? null : _re.firstMatch(s.trim());
    if (m == null) return null;
    final n = [for (var i = 1; i <= 3; i++) int.tryParse(m[i]!)];
    if (n.contains(null)) return null;
    return AppVersion(n[0]!, n[1]!, n[2]!);
  }

  @override
  int compareTo(AppVersion o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    return patch.compareTo(o.patch);
  }

  bool operator >(AppVersion o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(major, minor, patch);
  @override
  String toString() => '$major.$minor.$patch';
}
