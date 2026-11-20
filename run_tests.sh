#!/bin/bash
# Corre los tests en la tablet SIN perder los cuadernos:
# flutter test desinstala la app al terminar (y Android borra sus datos),
# así que antes se hace backup y después se reinstala y se restaura.
set -e
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")"
DEV=${DEV:-$(adb devices | awk 'NR==2{print $1}')}
D=/sdcard/Android/data/com.apuntes.apuntes/files
B=~/apuntes_app_backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$B"
adb -s "$DEV" pull "$D/apuntes" "$B/" >/dev/null 2>&1 && echo "Backup: $B" || echo "Sin datos para respaldar"

set +e
flutter test integration_test/app_test.dart -d "$DEV" -r expanded
R=$?
set -e

echo "Reinstalando la app y restaurando cuadernos..."
flutter build apk --release >/dev/null && adb -s "$DEV" install -r build/app/outputs/flutter-apk/app-release.apk >/dev/null
if [ -d "$B/apuntes" ]; then
  adb -s "$DEV" shell mkdir -p "$D"
  adb -s "$DEV" push "$B/apuntes" "$D/" >/dev/null
  adb -s "$DEV" shell "find $D/apuntes -type d -exec chmod 777 {} \; ; find $D/apuntes -type f -exec chmod 666 {} \;"
  echo "Restaurado."
fi
exit $R
