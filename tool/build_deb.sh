#!/usr/bin/env bash
# Compila la app de Linux y arma dist/opennote_<VERSION>_amd64.deb.
# Uso: tool/build_deb.sh VERSION   (ej. tool/build_deb.sh 1.0.42)
# SKIP_BUILD=1 reutiliza build/linux/x64/release/bundle ya compilado.
set -euo pipefail

VERSION="${1:?Uso: tool/build_deb.sh VERSION}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

APP_ID="io.github.santiagofr1.opennote"
bundle="build/linux/x64/release/bundle"
pkg="dist/pkg"
out="dist/opennote_${VERSION}_amd64.deb"

if [ -z "${SKIP_BUILD:-}" ]; then
  defines=()
  [ -f google_config.json ] && defines+=(--dart-define-from-file=google_config.json)
  flutter build linux --release --build-name="$VERSION" "${defines[@]}"
fi
[ -x "$bundle/opennote" ] || { echo "No está $bundle/opennote" >&2; exit 1; }

rm -rf "$pkg"
install -d "$pkg/DEBIAN" "$pkg/opt/opennote" "$pkg/usr/bin" "$pkg/usr/share/applications"
cp -a "$bundle/." "$pkg/opt/opennote/"
ln -s /opt/opennote/opennote "$pkg/usr/bin/opennote"

cat > "$pkg/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenNote
Comment=Cuadernos de apuntes a mano
Exec=opennote
Icon=$APP_ID
Terminal=false
Categories=Office;
StartupWMClass=$APP_ID
EOF

# Íconos: el más grande de los mipmap de Android, reescalado.
src=android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
for s in 48 64 128 192; do
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
  for f in "$bundle/opennote" "$bundle"/lib/*.so; do
    LD_LIBRARY_PATH="$bundle/lib" ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'
  done | sort -u | while read -r lib; do
    grep -qxF "$(basename "$lib")" <<<"$bundled" && continue
    dpkg -S "$(readlink -f "$lib")" 2>/dev/null | head -1 | cut -d: -f1 | cut -d' ' -f1
  done | sort -u
)
echo "Dependencias detectadas: $(echo $deps)" >&2

# Dependencias directas (readelf NEEDED del binario y las .so del bundle, mapeadas con dpkg -S en Ubuntu
# 24.04). Las t64 de 24.04 llevan alternativa con el nombre viejo. libjvm.so (de libdartjni, paquete jni) NO
# se pide: solo hace falta si algún código usa JNI, que en Linux no pasa.
depends="libc6, libgcc-s1, libstdc++6, zlib1g, libgtk-3-0t64 | libgtk-3-0, libgdk-pixbuf-2.0-0, \
libglib2.0-0t64 | libglib2.0-0, libatk1.0-0t64 | libatk1.0-0, libcairo2, libcairo-gobject2, libepoxy0, \
libfontconfig1, libharfbuzz0b, libpango-1.0-0, libpangocairo-1.0-0, libwayland-client0, libwayland-egl1, \
libsecret-1-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0"
size=$(du -sk "$pkg" | cut -f1)

cat > "$pkg/DEBIAN/control" <<EOF
Package: opennote
Version: $VERSION
Section: editors
Priority: optional
Architecture: amd64
Maintainer: santiagofr1 <noreply@github.com>
Installed-Size: $size
Depends: $depends
Homepage: https://github.com/santiagofr1/OpenNote
Description: Cuadernos de apuntes a mano con lápiz
 OpenNote es una app de apuntes manuscritos con cuadernos, hojas y PDF,
 sincronización opcional con Google Drive.
EOF

find "$pkg" -type d -exec chmod 755 {} +
find "$pkg/usr/share" -type f -exec chmod 644 {} +
dpkg-deb --root-owner-group --build "$pkg" "$out" >/dev/null
echo "$out"
