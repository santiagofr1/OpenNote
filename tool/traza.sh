#!/bin/bash
# Traza de la línea de tiempo en la tablet: genera un cuaderno de HOJAS hojas (50 por defecto), lo abre y hace el scroll
# "medio" de perf.sh envuelto en binding.traceAction. Mismas verificaciones de seguridad que tool/perf.sh
# (app real intacta, datos reales sin cambios, foco en el inicio u Vynote). Deja en build/perf/:
#   traza.timeline.json (traza cruda), traza.timeline_summary.json, perf.json y traza.log
# y al final corre tool/traza_resumen.py (qué hay en los frames > 16 ms).  HOJAS=100 tool/traza.sh  /  BACKUP=1 ...
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")/.."
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=io.github.santiagofr1.vynote
DATA=/sdcard/Android/data/$PKG/files/apuntes
APK=build/app/outputs/flutter-apk/app-profile.apk
HOJAS=${HOJAS:-50}

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

instalada || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en Vynote (nunca encima de otra app).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|com\.apuntes\.apuntes' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar ANTES (profile, con el benchmark como punto de entrada) y verificar el id del APK.
#    El build profile lleva el sufijo .test (android/app/build.gradle.kts), igual que debug: si el id fuera
#    io.github.santiagofr1.vynote pisaría la app real, así que se verifica y, si no coincide, no se corre nada.
#    `flutter drive` no tiene --no-uninstall: se le pasa el APK ya compilado, así solo toca la app del APK.
mkdir -p build/perf
rm -f build/perf/perf.json build/perf/traza.timeline.json build/perf/traza.timeline_summary.json
flutter build apk --profile --target=integration_test/perf_test.dart --dart-define=PERF_TRACE="$HOJAS" >/dev/null
AAPT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)aapt2
ID=$("$AAPT" dump badging "$APK" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
[ "$ID" = "$PKG.test" ] || { echo "ERROR: el APK de test es '$ID', no $PKG.test; no corro nada."; exit 1; }

ANTES=$(snapshot)
N_ANTES=$(echo "$ANTES" | grep -c '^-' || true)
echo "Datos reales antes: $N_ANTES archivos"

if [ "${BACKUP:-0}" = 1 ]; then
  B=~/apuntes_app_backup/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$B"
  adb -s "$DEV" pull "$DATA" "$B/" >/dev/null 2>&1 || echo "Aviso: algunos archivos no se pudieron bajar (p. ej. media/)"
  if [ -z "$(find "$B" -type f 2>/dev/null | head -1)" ]; then
    echo "ERROR: el backup quedó vacío ($B)"; exit 1
  fi
  echo "Backup: $B ($(find "$B" -type f | wc -l) archivos)"
fi

set +e
echo "Trazando scroll medio de un cuaderno de $HOJAS hojas; la tablet queda ocupada un rato..."
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart \
  -d "$DEV" --no-dds --use-application-binary="$APK" 2>&1 | tee build/perf/traza.log
R=${PIPESTATUS[0]}
set -e

FALLO=0
# adb puede fallar un instante cuando muere la app de prueba: se reintenta 3 veces (3 s entre intentos) antes de dar el error
OK_INST=0
for i in 1 2 3; do
  if instalada; then OK_INST=1; break; fi
  [ $i = 3 ] || sleep 3
done
if [ $OK_INST = 0 ]; then
  echo "ERROR: la app real ($PKG) DESAPARECIÓ"; FALLO=1
fi
DESPUES=$(snapshot)
N_DESPUES=$(echo "$DESPUES" | grep -c '^-' || true)
echo "Datos reales después: $N_DESPUES archivos"
if [ "$ANTES" != "$DESPUES" ]; then
  echo "ERROR: los datos de la app real cambiaron"
  diff <(echo "$ANTES") <(echo "$DESPUES") || true
  FALLO=1
fi
[ $FALLO = 0 ] && echo "OK: la app real y sus datos siguen intactos."
echo
echo "===== Traza (build/perf/traza.timeline.json, traza.timeline_summary.json) ====="
grep -o 'PERF .*' build/perf/traza.log | awk '!seen[$0]++' || true
if [ -f build/perf/traza.timeline.json ]; then
  python3 tool/traza_resumen.py build/perf/traza.timeline.json || true
else
  echo "(no se generó la traza)"
fi
[ $FALLO = 0 ] || exit 2
exit $R
