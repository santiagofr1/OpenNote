#!/bin/bash
# Genera las capturas del README (docs/img/*.png) en la tablet, sin tocar la app real.
# Corre integration_test/screenshots_test.dart con el build debug (io.github.santiagofr1.vynote.test, "Vynote Test"),
# con datos de ejemplo en una carpeta temporal. Mismas verificaciones de seguridad que run_tests.sh.
#   BACKUP=1 tool/screenshots.sh   -> además baja un backup de los cuadernos reales a ~/apuntes_app_backup/
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")/.."
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=io.github.santiagofr1.vynote
DATA=/sdcard/Android/data/$PKG/files/apuntes
APK=build/app/outputs/flutter-apk/app-debug.apk

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

instalada || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en Vynote (nunca encima de otra app).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|com\.apuntes\.apuntes' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar ANTES (con el test como punto de entrada) y verificar el id del APK.
#    `flutter drive` no tiene --no-uninstall: se le pasa el APK ya compilado (--use-application-binary), así nunca
#    decide por su cuenta qué app instalar/desinstalar: solo toca la del APK, que es io.github.santiagofr1.vynote.test.
flutter build apk --debug --target=integration_test/screenshots_test.dart >/dev/null
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
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart \
  -d "$DEV" --use-application-binary="$APK"
R=$?
set -e

FALLO=0
if ! instalada; then
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
echo "Capturas:"
ls -l docs/img/*.png 2>/dev/null || echo "(no se generó ninguna)"
[ $FALLO = 0 ] || exit 2
exit $R
