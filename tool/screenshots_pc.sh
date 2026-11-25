#!/bin/bash
# Genera las capturas del README (docs/img/*.png) en la PC (Linux), sin la tablet: integration_test/screenshots_test.dart
# corre con `flutter test -d linux` simulando la pantalla de la tablet (1200 x 1928 px) y la fuente Roboto de Android.
#   tool/screenshots_pc.sh        -> contenido de ejemplo en español, en docs/img/
#   tool/screenshots_pc.sh en     -> contenido de ejemplo en inglés, en docs/img/en/ (la interfaz sigue en español)
# La captura 07_sync.png es una composición: la hoja de sincronización de la "tablet" (07a, del mismo test) a la izquierda
# y la ventana de la app de PC (07b, tool/screenshot_pc.sh, ventana X11 real) a la derecha, armada con tool/compose_sync.py.
# Los intermedios 07a/07b no quedan en el repo: se arman en un directorio temporal que se borra al terminar.
set -e
export PATH=~/flutter/bin:$PATH
cd "$(dirname "$0")/.."
L=${1:-es}
case "$L" in
  es) OUT=docs/img ;;
  en) OUT=docs/img/en ;;
  *) echo "Uso: $0 [es|en]"; exit 1 ;;
esac
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

flutter test integration_test/screenshots_test.dart -d linux \
  --dart-define=SHOT_LANG="$L" --dart-define=SHOT_OUT="$PWD/$OUT"
mv "$OUT/07a_sync_tablet.png" "$TMP/07a.png"

tool/screenshot_pc.sh "$TMP/07b.png" "$L"
python3 -I tool/compose_sync.py "$TMP/07a.png" "$TMP/07b.png" "$OUT/07_sync.png"

echo "Capturas en $OUT:"
ls -l "$OUT"/*.png
