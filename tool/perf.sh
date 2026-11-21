#!/bin/bash
# Mide en la tablet cómo anda la app con cuadernos grandes (50, 100, 200 y 400 hojas), sin tocar la app real.
# Corre integration_test/perf_test.dart en modo PROFILE (compilado como com.apuntes.apuntes.test, "OpenNote Test",
# con datos generados en una carpeta temporal). Mismas verificaciones de seguridad que run_tests.sh.
# Deja build/perf/perf.log (todo) y build/perf/perf.json (los números), y muestra al final las líneas "PERF ".
#   SIZES=100,200 tool/perf.sh   -> solo esos tamaños (por defecto 50,100,200,400; con 1 solo tamaño la memoria sale más limpia)
#   BACKUP=1 tool/perf.sh        -> además baja un backup de los cuadernos reales a ~/apuntes_app_backup/
# Tarda unos 15-25 minutos (compilar ~2 min, generar y medir los 4 tamaños el resto).
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")/.."
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=com.apuntes.apuntes
DATA=/sdcard/Android/data/$PKG/files/apuntes
APK=build/app/outputs/flutter-apk/app-profile.apk
SIZES=${SIZES:-50,100,200,400}

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

instalada || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en OpenNote (nunca encima de otra app, p. ej. Samsung Notes).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|com\.apuntes\.apuntes' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar ANTES (profile, con el benchmark como punto de entrada) y verificar el id del APK.
#    El build profile lleva el sufijo .test (android/app/build.gradle.kts), igual que debug: si el id fuera
#    com.apuntes.apuntes pisaría la app real, así que se verifica y, si no coincide, no se corre nada.
#    `flutter drive` no tiene --no-uninstall: se le pasa el APK ya compilado, así solo toca la app del APK.
mkdir -p build/perf
rm -f build/perf/perf.json
flutter build apk --profile --target=integration_test/perf_test.dart --dart-define=PERF_SIZES="$SIZES" >/dev/null
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
echo "Midiendo (tamaños: $SIZES); la tablet queda ocupada un buen rato..."
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart \
  -d "$DEV" --use-application-binary="$APK" 2>&1 | tee build/perf/perf.log
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
echo "===== Resultados (build/perf/perf.log, build/perf/perf.json) ====="
grep -o 'PERF .*' build/perf/perf.log | awk '!seen[$0]++' || echo "(no hay líneas PERF)"
[ $FALLO = 0 ] || exit 2
exit $R
