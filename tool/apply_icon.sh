#!/usr/bin/env bash
# Aplica una opcion del icono (A|B|C) a android/app/src/main/res.
# Uso: tool/apply_icon.sh <A|B|C> [res_dir]
# Requiere python3 con cairosvg; si no esta, crea un venv temporal.
set -euo pipefail
opt="${1:?uso: $0 <A|B|C> [res_dir]}"
root="$(cd "$(dirname "$0")/.." && pwd)"
res="${2:-$root/android/app/src/main/res}"
py=python3
if ! python3 -c 'import cairosvg' 2>/dev/null; then
  venv="${TMPDIR:-/tmp}/opennote-icon-venv"
  [ -x "$venv/bin/python" ] || { python3 -m venv "$venv"; "$venv/bin/pip" -q install cairosvg; }
  py="$venv/bin/python"
fi
"$py" "$root/tool/icon_tool.py" android "$opt" "$res"
echo "Icono $opt aplicado en $res"
