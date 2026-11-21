#!/bin/bash
# Corre los tests de integración en la tablet sin tocar la app real.
# El build debug se instala como com.apuntes.apuntes.test (otra app, otros datos),
# así que al desinstalarse al final no afecta a los cuadernos de OpenNote.
# Antes y después se verifica que la app real y sus datos sigan iguales.
#   BACKUP=1 ./run_tests.sh   -> además baja un backup de los cuadernos reales a ~/apuntes_app_backup/
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")"
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=com.apuntes.apuntes
DATA=/sdcard/Android/data/$PKG/files/apuntes

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  # Sin los archivos de estado de la sync: la tarea de fondo de la app real los toca cada 15 min aunque no se use.
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" | grep -v -E ' (sync_state\.json|sync_crypto_cache\.json|sync\.(lock|fg|busy|bgchanged))\r?$' || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

instalada || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en OpenNote (nunca encima de otra app, p. ej. Samsung Notes).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|com\.apuntes\.apuntes' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar antes: flutter decide qué app desinstalar ANTES de compilar, leyendo el APK que haya.
#    Sin APK previo usa el id del código (com.apuntes.apuntes) y desinstalaría la app real.
flutter build apk --debug >/dev/null
AAPT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)aapt2
ID=$("$AAPT" dump badging build/app/outputs/flutter-apk/app-debug.apk | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
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
flutter test integration_test/app_test.dart -d "$DEV" -r expanded --no-uninstall ${NOMBRE:+--plain-name "$NOMBRE"}
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
[ $FALLO = 0 ] || exit 2
exit $R
