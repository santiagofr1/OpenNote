#!/bin/bash
# Tablet virtual para correr los tests sin la tablet de verdad: un emulador de Android 16 igual a la Galaxy Tab S6 Lite
# (1200 x 2000 a 240 dpi), en horizontal y con la letra del sistema al 110 %, como se usa la tablet real.
# Corre sin ventana. Necesita KVM (/dev/kvm) y no puede correr al mismo tiempo que una VM de VirtualBox.
#   tool/emulador.sh            -> crea la tablet virtual si no existe, la arranca y espera a que esté lista
#   tool/emulador.sh parar      -> la apaga
#   GPU=host tool/emulador.sh   -> dibuja con la placa de video (mucho más rápido si hay una; por defecto, por software)
#   DEV=emulator-5554 ./run_tests.sh   -> el test completo en el emulador (ver lo que imprime al terminar)
# Para la presión del lápiz real y la latencia sigue haciendo falta la tablet.
set -e
export JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk ANDROID_AVD_HOME=~/.android/avd
SDK=$ANDROID_HOME
PATH=$SDK/platform-tools:$SDK/emulator:$SDK/cmdline-tools/latest/bin:$PATH
AVD=vynote_tablet
IMG="system-images;android-36;google_apis;x86_64"
SERIAL=emulator-5554

if [ "${1:-}" = parar ]; then
  adb -s $SERIAL emu kill 2>/dev/null || true
  echo "Emulador apagado."
  exit 0
fi

[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "ERROR: no hay acceso a /dev/kvm (¿falta cargar kvm_amd o estar en el grupo kvm?)"; exit 1; }
if pgrep -f 'VBoxHeadless|VirtualBoxVM' >/dev/null; then
  echo "ERROR: hay una VM de VirtualBox corriendo; el emulador y VirtualBox no pueden andar a la vez."
  exit 1
fi

if ! emulator -list-avds | grep -qx $AVD; then
  echo "Creando la tablet virtual $AVD…"
  echo no | avdmanager create avd -n $AVD -k "$IMG" -d "pixel_tablet" --force >/dev/null
  CFG=$ANDROID_AVD_HOME/$AVD.avd/config.ini
  sed -i '/^hw.lcd.width\|^hw.lcd.height\|^hw.lcd.density\|^hw.ramSize\|^hw.initialOrientation\|^hw.keyboard\|^disk.dataPartition.size/d' "$CFG"
  cat >>"$CFG" <<EOF
hw.lcd.width=1200
hw.lcd.height=2000
hw.lcd.density=240
hw.ramSize=3072
hw.initialOrientation=landscape
hw.keyboard=yes
disk.dataPartition.size=6G
EOF
fi

if adb devices | grep -q "^$SERIAL"; then
  echo "El emulador ya está corriendo ($SERIAL)."
else
  echo "Arrancando el emulador (sin ventana)…"
  nohup emulator -avd $AVD -no-window -no-audio -no-boot-anim -no-snapshot-save -gpu "${GPU:-swiftshader_indirect}" \
    >/tmp/vynote_emulador.log 2>&1 &
fi

adb -s $SERIAL wait-for-device
for _ in $(seq 1 180); do
  [ "$(adb -s $SERIAL shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
[ "$(adb -s $SERIAL shell getprop sys.boot_completed | tr -d '\r')" = 1 ] || { echo "ERROR: el emulador no terminó de arrancar (ver /tmp/vynote_emulador.log)"; exit 1; }

# como la tablet real: horizontal fijo y letra al 110 % (las animaciones se dejan: Flutter las respeta como accesibilidad)
adb -s $SERIAL shell settings put system accelerometer_rotation 0
adb -s $SERIAL shell settings put system user_rotation 1
adb -s $SERIAL shell settings put system font_scale 1.1
adb -s $SERIAL shell input keyevent 82 >/dev/null 2>&1 || true # desbloquear
echo "Listo: $SERIAL ($(adb -s $SERIAL shell wm size | tr -d '\r' | tail -1), $(adb -s $SERIAL shell wm density | tr -d '\r' | tail -1))"
