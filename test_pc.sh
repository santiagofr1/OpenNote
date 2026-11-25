#!/bin/bash
# Corre en la PC todo lo que se puede probar sin la tablet: el análisis del código y los tests de test/.
# Al final deja un reporte con lo que falló (y nada de lo que pasó) en test_pc.log.
#   ./test_pc.sh                 -> análisis + todos los tests de test/
#   ./test_pc.sh test/editor     -> solo esa carpeta o archivo (lo que se pase va a `flutter test`)
#   NOMBRE='texto' ./test_pc.sh  -> solo los casos cuyo nombre contiene ese texto
#   SIN_ANALISIS=1 ./test_pc.sh  -> se saltea `flutter analyze`
# Sale con código 0 si está todo verde y 1 si algo falló.
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
python3 -I - "$JSON" <<'EOF' | tee -a "$REPORTE"
import json, sys
nombres, ok, mal, salteados = {}, 0, [], 0
for linea in open(sys.argv[1], encoding='utf-8'):
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
print(f"TESTS: {ok} pasaron, {len(mal)} fallaron, {salteados} salteados")
for n in mal:
    print(f"  FALLÓ: {n}")
EOF

if [ "$fallo" = 0 ]; then
  echo "RESULTADO: todo verde" | tee -a "$REPORTE"
else
  echo "RESULTADO: hay fallas (detalle arriba y en $REPORTE)" | tee -a "$REPORTE"
fi
exit $fallo
