#!/bin/bash
# Corre en la PC todo lo que se puede probar sin la tablet: el análisis del código y los tests de test/.
# Al final deja un reporte con lo que falló (y nada de lo que pasó) en test_pc.log.
#   ./test_pc.sh                 -> análisis + todos los tests de test/
#   ./test_pc.sh test/editor     -> solo esa carpeta o archivo (lo que se pase va a `flutter test`)
#   NOMBRE='texto' ./test_pc.sh  -> solo los casos cuyo nombre contiene ese texto
#   SIN_ANALISIS=1 ./test_pc.sh  -> se saltea `flutter analyze`
#   INTEGRACION=1 ./test_pc.sh   -> además corre integration_test/app_test.dart y layout_sizes_test.dart en la app de
#                                   Linux, simulando la pantalla de la tablet (tardan ~20-25 min); respeta NOMBRE=.
#                                   Lo que necesita lápiz real, ML Kit o la sync en segundo plano sigue pidiendo la tablet.
# Sale con código 0 si está todo verde y 1 si algo falló.
source "$(dirname "$0")/tool/sin_ventana.sh"  # la app de Linux de INTEGRACION=1 corre en una pantalla virtual
export PATH=~/flutter/bin:$PATH
cd "$(dirname "$0")"
REPORTE=test_pc.log
JSON=$(mktemp --suffix=.json)
trap 'rm -f "$JSON"' EXIT
: > "$REPORTE"
fallo=0

echo "== Vynote: tests en la PC ($(date '+%Y-%m-%d %H:%M')) ==" | tee -a "$REPORTE"

# ---- análisis: errores y avisos (los `info` de deprecated_member_use son de siempre y no cuentan) ----
if [ "${SIN_ANALISIS:-0}" != 1 ]; then
  echo "-- flutter analyze" | tee -a "$REPORTE"
  problemas=$(flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | grep -E '^\s*(error|warning) •')
  if [ -n "$problemas" ]; then
    echo "$problemas" | tee -a "$REPORTE"
    echo "ANÁLISIS: $(echo "$problemas" | wc -l) problema(s)" | tee -a "$REPORTE"
    fallo=1
  else
    echo "ANÁLISIS: sin errores ni avisos" | tee -a "$REPORTE"
  fi
fi

# ---- tests: solo se muestran los que fallan ----
echo "-- flutter test ${*:-test}" | tee -a "$REPORTE"
args=(--reporter failures-only --file-reporter "json:$JSON")
[ -n "$NOMBRE" ] && args+=(--plain-name "$NOMBRE")
flutter test "${args[@]}" "${@:-test}" 2>&1 | tee -a "$REPORTE"
[ "${PIPESTATUS[0]}" != 0 ] && fallo=1

# ---- resumen: cuántos pasaron y la lista de los que fallaron ----
resumen() { # $1 = etiqueta, $2 = json
python3 -I - "$1" "$2" <<'EOF' | tee -a "$REPORTE"
import json, sys
etiqueta = sys.argv[1]
nombres, ok, mal, salteados = {}, 0, [], 0
for linea in open(sys.argv[2], encoding='utf-8'):
    try:
        e = json.loads(linea)
    except ValueError:
        continue
    if e.get('type') == 'testStart':
        nombres[e['test']['id']] = e['test']['name']
    elif e.get('type') == 'testDone' and not e.get('hidden'):
        if e.get('skipped'):
            salteados += 1
        elif e.get('result') == 'success':
            ok += 1
        else:
            mal.append(nombres.get(e['testID'], '?'))
print(f"{etiqueta}: {ok} pasaron, {len(mal)} fallaron, {salteados} salteados")
for n in mal:
    print(f"  FALLÓ: {n}")
EOF
}
resumen TESTS "$JSON"

# ---- integración en la PC (opcional): la app de Linux con la pantalla de la tablet simulada ----
if [ "${INTEGRACION:-0}" = 1 ]; then
  for t in app_test layout_sizes_test; do
    echo "-- flutter test integration_test/$t.dart -d linux" | tee -a "$REPORTE"
    JSON_I=$(mktemp --suffix=.json)
    iargs=(--reporter failures-only --file-reporter "json:$JSON_I")
    [ -n "$NOMBRE" ] && iargs+=(--plain-name "$NOMBRE")
    flutter test "${iargs[@]}" "integration_test/$t.dart" -d linux 2>&1 | grep -av '^ERROR' | tee -a "$REPORTE"
    [ "${PIPESTATUS[0]}" != 0 ] && fallo=1
    resumen "INTEGRACIÓN $t" "$JSON_I"
    rm -f "$JSON_I"
  done
fi

if [ "$fallo" = 0 ]; then
  echo "RESULTADO: todo verde" | tee -a "$REPORTE"
else
  echo "RESULTADO: hay fallas (detalle arriba y en $REPORTE)" | tee -a "$REPORTE"
fi
exit $fallo
