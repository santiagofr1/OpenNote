#!/bin/bash
# Mide en la tablet cómo anda el lienzo infinito ancho (paneo, pellizco y escritura), sin tocar la app real.
# Corre integration_test/canvas_perf_test.dart en modo PROFILE (compilado como io.github.santiagofr1.vynote.test, "Vynote Test",
# con datos generados en una carpeta temporal). Los gestos (un dedo, dos dedos, lápiz) son reales, hechos con TestGesture.
# Deja build/perf/lienzo.log (todo) y build/perf/canvas.json (los números), y muestra al final las líneas "PERF ".
#   CANVAS_STROKES=4000 tool/perf_lienzo.sh   -> otro tamaño (por defecto 8000 trazos, ~300.000 puntos)
#   DEV=<serie> tool/perf_lienzo.sh           -> otra tablet (por defecto la primera de `adb devices`)
# Si la app real está instalada, se hacen las mismas verificaciones de datos que en perf.sh; si no, se saltean.
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")/.."
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=io.github.santiagofr1.vynote
DATA=/sdcard/Android/data/$PKG/files/apuntes
APK=build/app/outputs/flutter-apk/app-profile.apk
STROKES=${CANVAS_STROKES:-8000}

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" | grep -v -E '^total [0-9]+\r?$' | grep -v -E ' (sync_state\.json|sync_crypto_cache\.json|sync\.(lock|fg|busy|bgchanged))\r?$' || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

[ -n "$DEV" ] || { echo "ERROR: no hay ninguna tablet conectada."; exit 1; }
REAL=0
if instalada; then REAL=1; else echo "Nota: la app real ($PKG) no está instalada en $DEV; se saltea la verificación de sus datos."; fi

# 1) Solo si la tablet está en el inicio, en Vynote o en la app de prueba (nunca encima de otra app).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|io\.github\.santiagofr1\.vynote' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar ANTES (profile, con el benchmark como punto de entrada) y verificar el id del APK (debe ser el .test).
mkdir -p build/perf
rm -f build/perf/canvas.json
flutter build apk --profile --target=integration_test/canvas_perf_test.dart --dart-define=CANVAS_STROKES="$STROKES" >/dev/null
AAPT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)aapt2
ID=$("$AAPT" dump badging "$APK" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
[ "$ID" = "$PKG.test" ] || { echo "ERROR: el APK de test es '$ID', no $PKG.test; no corro nada."; exit 1; }

if [ $REAL = 1 ]; then
  ANTES=$(snapshot)
  echo "Datos reales antes: $(echo "$ANTES" | grep -c '^-' || true) archivos"
fi

set +e
echo "Midiendo el lienzo ($STROKES trazos); la tablet queda ocupada unos minutos..."
flutter drive --profile --driver=test_driver/perf_lienzo_driver.dart --target=integration_test/canvas_perf_test.dart \
  -d "$DEV" --use-application-binary="$APK" 2>&1 | tee build/perf/lienzo.log
R=${PIPESTATUS[0]}
set -e

FALLO=0
if [ $REAL = 1 ]; then
  # adb puede fallar un instante cuando muere la app de prueba: se reintenta 3 veces antes de dar el error
  OK_INST=0
  for i in 1 2 3; do
    if instalada; then OK_INST=1; break; fi
    [ $i = 3 ] || sleep 3
  done
  if [ $OK_INST = 0 ]; then echo "ERROR: la app real ($PKG) DESAPARECIÓ"; FALLO=1; fi
  DESPUES=$(snapshot)
  echo "Datos reales después: $(echo "$DESPUES" | grep -c '^-' || true) archivos"
  if [ "$ANTES" != "$DESPUES" ]; then
    echo "ERROR: los datos de la app real cambiaron"
    diff <(echo "$ANTES") <(echo "$DESPUES") || true
    FALLO=1
  fi
  [ $FALLO = 0 ] && echo "OK: la app real y sus datos siguen intactos."
fi
echo
echo "===== Resultados (build/perf/lienzo.log, build/perf/canvas.json) ====="
grep -o 'PERF .*' build/perf/lienzo.log | awk '!seen[$0]++' || echo "(no hay líneas PERF)"
[ $FALLO = 0 ] || exit 2
exit $R
