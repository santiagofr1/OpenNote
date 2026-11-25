#!/bin/bash
# Corre los tests de integración en la tablet sin tocar la app real.
# El build debug se instala como io.github.santiagofr1.vynote.test (otra app, otros datos),
# así que al desinstalarse al final no afecta a los cuadernos de Vynote.
# Antes y después se verifica que la app real y sus datos sigan iguales.
#   BACKUP=1 ./run_tests.sh   -> además baja un backup de los cuadernos reales a ~/apuntes_app_backup/
#   NOMBRE='texto' ./run_tests.sh   -> solo los casos cuyo nombre contiene ese texto
#   FILTRO='regex' ./run_tests.sh   -> solo los casos cuyo nombre encaja con la expresión regular
#   NUEVOS=1 ./run_tests.sh   -> solo los casos de las funciones de esta tanda (ver NUEVOS_RE más abajo)
#   DEV=emulator-5554 ./run_tests.sh -> en la tablet virtual (arrancala antes con tool/emulador.sh); sin DEV usa el primer
#                                     dispositivo de `adb devices`
# Muestra los pasos y una barra de avance; el log entero queda en test_tablet.log y al terminar avisa con una
# notificación en la PC (si hay notify-send).
set -e
# Casos de la tanda actual (fondos #31, plantillas #33, pegar imagen #32, selector de color) y los viejos que tocan lo mismo.
NUEVOS_RE='issue #3[1-9]\)|issue #23\)|favoritos: Cambiar|estilo de hoja|issue #41\)|issue #42\)|scroll rápido|resaltador sobre un PDF|índice: al cerrarlo'
[ "${NUEVOS:-0}" = 1 ] && FILTRO=${FILTRO:-$NUEVOS_RE}
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")"
LOG=test_tablet.log
paso() { echo "[$1/4] $2"; }
avisar() { command -v notify-send >/dev/null && notify-send -a Vynote "Tests en la tablet" "$1" 2>/dev/null || true; }
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
PKG=io.github.santiagofr1.vynote
DATA=/sdcard/Android/data/$PKG/files/apuntes

snapshot() { # lista de archivos (tamaño, fecha, ruta) de los cuadernos reales
  # Sin los archivos de estado de la sync: la tarea de fondo de la app real los toca cada 15 min aunque no se use.
  # Sin las líneas "total" (cuentan los bloques de la carpeta, incluidos los archivos de la sync que se ignoran).
  adb -s "$DEV" shell "ls -lAR $DATA 2>&1" | grep -v -E '^total [0-9]+\r?$' | grep -v -E ' (sync_state\.json|sync_crypto_cache\.json|sync\.(lock|fg|busy|bgchanged))\r?$' || true
}
instalada() { adb -s "$DEV" shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }

# en el emulador (tool/emulador.sh) no hay app real ni cuadernos que cuidar
EMU=0; case "$DEV" in emulator-*) EMU=1 ;; esac
instalada || [ $EMU = 1 ] || { echo "ERROR: la app real ($PKG) no está instalada; no corro nada."; exit 1; }

# 1) Solo si la tablet está en el inicio o en Vynote (nunca encima de otra app).
FOCO=$(adb -s "$DEV" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "$FOCO" | grep -qE 'launcher|io\.github\.santiagofr1\.vynote' || { echo "ERROR: la tablet está en otra app; no corro nada."; echo "$FOCO"; exit 1; }

# 2) Compilar antes: flutter decide qué app desinstalar ANTES de compilar, leyendo el APK que haya.
#    Sin APK previo usa el id del código (io.github.santiagofr1.vynote) y desinstalaría la app real.
paso 1 "Compilando la app de prueba (tarda unos minutos)…"
flutter build apk --debug >/dev/null
AAPT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)aapt2
ID=$("$AAPT" dump badging build/app/outputs/flutter-apk/app-debug.apk | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
[ "$ID" = "$PKG.test" ] || { echo "ERROR: el APK de test es '$ID', no $PKG.test; no corro nada."; exit 1; }

# Los tests están pensados con la tablet en horizontal: se fija mientras corren y al final se deja la rotación como estaba.
ROT_AUTO=$(adb -s "$DEV" shell settings get system accelerometer_rotation | tr -d '\r')
ROT_USER=$(adb -s "$DEV" shell settings get system user_rotation | tr -d '\r')
restaurar_rotacion() {
  adb -s "$DEV" shell settings put system user_rotation "$ROT_USER" >/dev/null 2>&1 || true
  adb -s "$DEV" shell settings put system accelerometer_rotation "$ROT_AUTO" >/dev/null 2>&1 || true
}
trap restaurar_rotacion EXIT
adb -s "$DEV" shell settings put system accelerometer_rotation 0
adb -s "$DEV" shell settings put system user_rotation 1
sleep 2

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

# cuántos casos van a correr (para la barra): los nombres de app_test.dart que entran en el filtro
TOTAL=$(python3 -I - "$NOMBRE" "$FILTRO" <<'EOF'
import re, sys
nombre, filtro = sys.argv[1], sys.argv[2]
src = open('integration_test/app_test.dart', encoding='utf-8').read()
casos = re.findall(r"testWidgets\(\s*'((?:[^'\\]|\\.)*)'", src)
casos = [c for c in casos if (not nombre or nombre in c) and (not filtro or re.search(filtro, c))]
print(len(casos))
EOF
)
paso 2 "Instalando y corriendo $TOTAL caso(s) en la tablet (el log entero va a $LOG)…"
set +e
flutter test integration_test/app_test.dart -d "$DEV" -r expanded --no-uninstall ${NOMBRE:+--plain-name "$NOMBRE"} ${FILTRO:+--name "$FILTRO"} 2>&1 \
  | python3 -I tool/progreso_tests.py "$LOG" "$TOTAL"
R=${PIPESTATUS[1]}
set -e
paso 3 "Verificando que la app real y tus cuadernos sigan intactos…"

FALLO=0
if [ $EMU = 0 ] && ! instalada; then
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
if [ $FALLO != 0 ]; then
  avisar "OJO: la app real o sus datos cambiaron"
  exit 2
fi
if [ "$R" = 0 ]; then
  paso 4 "Listo: todo verde"
  avisar "Todo verde ($TOTAL casos)"
else
  paso 4 "Listo: hay casos que fallaron (detalle arriba y en $LOG)"
  avisar "Fallaron casos: mirá la terminal o $LOG"
fi
exit $R
