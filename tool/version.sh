#!/bin/bash
# Versión de la próxima release: MAYOR.MENOR sale de `version:` en pubspec.yaml y el PARCHE es el siguiente al de la
# tag vMAYOR.MENOR.* más alta (0 si todavía no hay ninguna). La usa el workflow de release; se puede correr a mano.
#   tool/version.sh   -> imprime, por ejemplo, 1.1.3
# Reglas (ver docs/RELEASES.md): PARCHE = solo arreglos; MENOR = al menos una función nueva o cambio visible (se sube a
# mano en pubspec.yaml al mergear a main); MAYOR = se rompe la compatibilidad de los cuadernos o de la sync.
set -e
cd "$(dirname "$0")/.."
BASE=$(sed -n 's/^version: *\([0-9]\+\.[0-9]\+\)\..*/\1/p' pubspec.yaml)
[ -n "$BASE" ] || { echo "ERROR: no encontré 'version: MAYOR.MENOR.PARCHE' en pubspec.yaml" >&2; exit 1; }
LAST=$(git tag -l "v$BASE.*" | sed "s/^v$BASE\.//" | grep -E '^[0-9]+$' | sort -n | tail -1)
echo "$BASE.$(( ${LAST:--1} + 1 ))"
