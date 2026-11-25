#!/usr/bin/env bash
# Compila la app de Linux y arma dist/vynote_<VERSION>_amd64.deb.
# Uso: tool/build_deb.sh VERSION   (ej. tool/build_deb.sh 1.0.42)
# SKIP_BUILD=1 reutiliza build/linux/x64/release/bundle ya compilado.
set -euo pipefail

VERSION="${1:?Uso: tool/build_deb.sh VERSION}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

APP_ID="io.github.santiagofr1.vynote"
bundle="build/linux/x64/release/bundle"
pkg="dist/pkg"
out="dist/vynote_${VERSION}_amd64.deb"

if [ -z "${SKIP_BUILD:-}" ]; then
  defines=()
  [ -f google_config.json ] && defines+=(--dart-define-from-file=google_config.json)
  flutter build linux --release --build-name="$VERSION" "${defines[@]}"
fi
[ -x "$bundle/vynote" ] || { echo "No está $bundle/vynote" >&2; exit 1; }

rm -rf "$pkg"
install -d "$pkg/DEBIAN" "$pkg/opt/vynote" "$pkg/usr/bin" "$pkg/usr/share/applications"
cp -a "$bundle/." "$pkg/opt/vynote/"
ln -s /opt/vynote/vynote "$pkg/usr/bin/vynote"

cat > "$pkg/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vynote
Comment=Cuadernos de apuntes a mano
Exec=vynote
Icon=$APP_ID
Terminal=false
Categories=Office;
StartupWMClass=$APP_ID
EOF

# Íconos: el de 512 px que genera tool/icon_from_png.py, reescalado.
src=docs/img/icon.png
for s in 48 64 128 256 512; do
  d="$pkg/usr/share/icons/hicolor/${s}x${s}/apps"
  install -d "$d"
  python3 - "$src" "$s" "$d/$APP_ID.png" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGBA").resize((int(sys.argv[2]),) * 2, Image.LANCZOS).save(sys.argv[3])
PY
done

# Dependencias reales: sonames del binario y las .so del bundle que no vienen en el bundle.
bundled=$(cd "$bundle" && find . -name '*.so*' -printf '%f\n')
deps=$(
  for f in "$bundle/vynote" "$bundle"/lib/*.so; do
    LD_LIBRARY_PATH="$bundle/lib" ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'
  done | sort -u | while read -r lib; do
    grep -qxF "$(basename "$lib")" <<<"$bundled" && continue
    dpkg -S "$(readlink -f "$lib")" 2>/dev/null | head -1 | cut -d: -f1 | cut -d' ' -f1
  done | sort -u
)
echo "Dependencias detectadas: $(echo $deps)" >&2

# Dependencias directas (readelf NEEDED del binario y las .so del bundle, mapeadas con dpkg -S en Ubuntu
# 24.04). Las t64 de 24.04 llevan alternativa con el nombre viejo. libjvm.so (de libdartjni, paquete jni) NO
# se pide: solo hace falta si algún código usa JNI, que en Linux no pasa. libegl1 y libgles2 no salen de ldd porque
# el engine de Flutter las abre con dlopen; sin ellas la app se cae al arrancar (probado en Ubuntu 24.04 limpio).
# dbus-send (dbus-bin) lo usa SecretService para ver si hay llavero antes de tocar libsecret.
depends="libc6, libgcc-s1, libstdc++6, zlib1g, libgtk-3-0t64 | libgtk-3-0, libgdk-pixbuf-2.0-0, \
libglib2.0-0t64 | libglib2.0-0, libatk1.0-0t64 | libatk1.0-0, libcairo2, libcairo-gobject2, libepoxy0, \
libfontconfig1, libharfbuzz0b, libpango-1.0-0, libpangocairo-1.0-0, libwayland-client0, libwayland-egl1, \
libsecret-1-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, libegl1, libgles2, dbus-bin | dbus"
size=$(du -sk "$pkg" | cut -f1)

cat > "$pkg/DEBIAN/control" <<EOF
Package: vynote
Version: $VERSION
Section: editors
Priority: optional
Architecture: amd64
Maintainer: santiagofr1 <noreply@github.com>
Installed-Size: $size
Depends: $depends
Replaces: opennote
Conflicts: opennote
Provides: opennote
Homepage: https://github.com/santiagofr1/Vynote
Description: Cuadernos de apuntes a mano con lápiz
 Vynote es una app de apuntes manuscritos con cuadernos, hojas y PDF,
 sincronización opcional con Google Drive.
EOF

find "$pkg" -type d -exec chmod 755 {} +
find "$pkg/usr/share" -type f -exec chmod 644 {} +
dpkg-deb --root-owner-group --build "$pkg" "$out" >/dev/null
echo "$out"
