#!/bin/bash
# Captura la ventana de la app de PC (Linux) para el README: corre integration_test/screenshots_pc_test.dart
# (biblioteca de ejemplo en una carpeta temporal, sincronización de mentira), espera `PCSHOT READY` y guarda la
# ventana X11 en el PNG que se le pase (por defecto docs/img/07b_sync_pc.png). Hace falta xwininfo y python3-gi.
set -e
export PATH=~/flutter/bin:$PATH
cd "$(dirname "$0")/.."
OUT=${1:-docs/img/07b_sync_pc.png}
LOG=$(mktemp)
GDK_BACKEND=x11 flutter test integration_test/screenshots_pc_test.dart -d linux >"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -f "$LOG"' EXIT
for _ in $(seq 1 600); do
  grep -q 'PCSHOT READY' "$LOG" && break
  kill -0 $PID 2>/dev/null || { cat "$LOG"; echo "ERROR: el test terminó antes de estar listo"; exit 1; }
  sleep 1
done
grep -q 'PCSHOT READY' "$LOG" || { cat "$LOG"; echo "ERROR: no apareció PCSHOT READY"; exit 1; }
sleep 1
# la ventana interna "OpenNote" (no la de mutter-x11-frames)
WID=$(xwininfo -root -tree | grep '"OpenNote"' | grep -v 'mutter' | head -1 | awk '{print $1}')
[ -n "$WID" ] || { echo "ERROR: no encontré la ventana de OpenNote"; exit 1; }
GDK_BACKEND=x11 python3 - "$WID" "$OUT" <<'EOF'
import sys, gi
gi.require_version('Gdk', '3.0'); gi.require_version('GdkX11', '3.0')
from gi.repository import Gdk, GdkX11
wid, out = int(sys.argv[1], 16), sys.argv[2]
disp = Gdk.Display.get_default()
win = GdkX11.X11Window.foreign_new_for_display(disp, wid)
pb = Gdk.pixbuf_get_from_window(win, 0, 0, win.get_width(), win.get_height())
pb.savev(out, 'png', [], [])
print('Captura:', out, win.get_width(), 'x', win.get_height())
EOF
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true
