#!/bin/bash
# Compara OpenNote con Samsung Notes en la tablet: abre un cuaderno de 34 hojas (misma densidad que perf.sh) en horizontal,
# y mientras el test mide FrameTiming (40 s) este script hace los swipes con adb (el test no scrollea solo).
# Basado en tool/perf.sh: compila la APK de prueba (com.apuntes.apuntes.test, "OpenNote Test"), mismas verificaciones de
# seguridad (nunca toca la app real ni sus datos). Deja build/perf/comparar.log y build/perf/perf.json.
#   HOJAS=34 tool/comparar.sh   -> otra cantidad de hojas
#   BACKUP=1 tool/comparar.sh   -> además baja un backup de los cuadernos reales a ~/apuntes_app_backup/
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")/.."
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=com.apuntes.apuntes
DATA=/sdcard/Android/data/$PKG/files/apuntes
APK=build/app/outputs/flutter-apk/app-profile.apk
HOJAS=${HOJAS:-34}
LOG=build/perf/comparar.log

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }
pss() { # TOTAL PSS (MB) de la app de prueba, "?" si no se pudo leer
  local kb
  kb=$(adb -s "$DEV" shell dumpsys meminfo "$PKG.test" 2>/dev/null | tr -d '\r' | awk '/TOTAL PSS:/{print $3; exit} /^ *TOTAL +[0-9]/{print $2; exit}')
  if [ -n "$kb" ]; then echo $((kb / 1024)); else echo "?"; fi
}

instalada || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en OpenNote (nunca encima de otra app, p. ej. Samsung Notes).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|com\.apuntes\.apuntes' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar ANTES (profile, con el benchmark como punto de entrada) y verificar el id del APK.
#    El build profile lleva el sufijo .test (android/app/build.gradle.kts), igual que debug: si el id fuera
#    com.apuntes.apuntes pisaría la app real, así que se verifica y, si no coincide, no se corre nada.
#    `flutter drive` no tiene --no-uninstall: se le pasa el APK ya compilado, así solo toca la app del APK.
mkdir -p build/perf
rm -f build/perf/perf.json "$LOG"
flutter build apk --profile --target=integration_test/perf_test.dart --dart-define=PERF_COMPARE="$HOJAS" >/dev/null
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
echo "Midiendo comparación ($HOJAS hojas, horizontal); la tablet queda ocupada un rato..."
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart \
  -d "$DEV" --use-application-binary="$APK" > "$LOG" 2>&1 &
DRIVE=$!

# 3) Esperar a que el test avise que está listo (si el drive termina antes, algo falló)
LISTO=0
while kill -0 "$DRIVE" 2>/dev/null; do
  if grep -q 'PERF LISTO_PARA_SWIPES' "$LOG" 2>/dev/null; then LISTO=1; break; fi
  sleep 1
done

if [ $LISTO = 1 ]; then
  sleep 2
  # Los swipes son toques reales: solo si al frente está la app de prueba (nunca otra app donde un dedo pueda dibujar).
  FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
  echo "$FOCO" | grep -q "$PKG\.test/" || { echo "ERROR: al frente no está OpenNote Test; no hago swipes."; echo "$FOCO"; LISTO=0; }
fi
if [ $LISTO = 1 ]; then
  PSS_ABIERTO=$(pss)
  # coordenadas de pantalla ya rotada (tablet horizontal, 2000x1200)
  for i in $(seq 15); do adb -s "$DEV" shell input swipe 1000 1000 1000 250 180; sleep 0.3; done # dedo hacia arriba: avanza
  for i in $(seq 15); do adb -s "$DEV" shell input swipe 1000 250 1000 1000 180; sleep 0.3; done # dedo hacia abajo: vuelve
  PSS_FINAL=$(pss)
  echo "PSS abierto $PSS_ABIERTO MB / tras desplazar $PSS_FINAL MB"
else
  echo "ERROR: el test terminó sin llegar a LISTO_PARA_SWIPES (ver $LOG)"
fi

wait "$DRIVE"
R=$?
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
echo "===== Resultados ($LOG, build/perf/perf.json) ====="
grep -o 'PERF .*' "$LOG" | awk '!seen[$0]++' || echo "(no hay líneas PERF)"
[ $FALLO = 0 ] || exit 2
[ $LISTO = 1 ] || exit 3
exit $R
