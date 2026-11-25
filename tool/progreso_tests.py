#!/usr/bin/env python3
"""Lee la salida de `flutter test -r expanded` por la entrada estándar y muestra el avance en una sola línea.

Uso (lo llama run_tests.sh):
    flutter test ... -r expanded | python3 -I tool/progreso_tests.py LOG TOTAL

Todo lo que llega se guarda tal cual en LOG. En la terminal se ve una barra con cuántos casos van (de TOTAL), cuántos
pasaron y fallaron, y el caso que está corriendo. Al final imprime el resumen y el error de cada caso que falló.
Sale con 0 si no falló ninguno y 1 si falló alguno, si quedaron casos sin terminar o si corrieron menos de TOTAL.
"""
import re
import shutil
import sys
import time

LINEA = re.compile(r'^\d+:\d+ \+(\d+)(?: ~(\d+))?(?: -(\d+))?: (.*)$')


def main():
    log_path, total = sys.argv[1], max(1, int(sys.argv[2]))
    tty = sys.stdout.isatty()
    ok = mal = salteados = 0
    actual = 'preparando la app de prueba en la tablet…'
    fallados = []  # nombres, en orden
    errores = {}  # nombre -> líneas del error
    bloque = None  # error que se está leyendo
    inicio = time.time()
    ultimo = 0.0

    def barra(forzar=False):
        nonlocal ultimo
        if not tty or (not forzar and time.time() - ultimo < .2):
            return
        ultimo = time.time()
        hechos = ok + mal + salteados
        ancho = 24
        lleno = min(ancho, round(ancho * hechos / total))
        seg = int(time.time() - inicio)
        texto = (f'[{"#" * lleno}{"-" * (ancho - lleno)}] {hechos}/{total}  bien {ok}  mal {mal}'
                 f'  {seg // 60:02d}:{seg % 60:02d}  ⟶ {actual}')
        cols = shutil.get_terminal_size((120, 20)).columns
        sys.stdout.write('\r\033[K' + texto[:cols - 1])
        sys.stdout.flush()

    with open(log_path, 'w', encoding='utf-8') as log:
        for crudo in sys.stdin:
            log.write(crudo)
            log.flush()
            linea = crudo.rstrip('\n')
            if linea.startswith('══╡ EXCEPTION CAUGHT'):
                bloque = [linea]
                continue
            if bloque is not None:
                bloque.append(linea)
                if linea.startswith('═════'):
                    m = re.search(r'The test description was:\n\s*(.+)', '\n'.join(bloque))
                    if m:
                        errores.setdefault(m.group(1).strip(), bloque)
                    bloque = None
                continue
            m = LINEA.match(linea)
            if not m:
                continue
            ok, salteados, mal = int(m.group(1)), int(m.group(2) or 0), int(m.group(3) or 0)
            nombre = m.group(4)
            if nombre.endswith(' [E]'):
                n = nombre[:-4]
                if n not in fallados:
                    fallados.append(n)
            elif not nombre.startswith('(') and not nombre.startswith('loading ') and 'tests passed' not in nombre \
                    and 'tests failed' not in nombre:
                actual = nombre
            barra()
    barra(forzar=True)
    if tty:
        sys.stdout.write('\n')

    # "did not complete" (se cortó la conexión con la app) marca [E] pero no suma al contador de fallas
    mal = max(mal, len(fallados))
    print(f'TESTS: {ok} pasaron, {mal} fallaron, {salteados} salteados (de {total} esperados)')
    for n in fallados:
        print(f'\nFALLÓ: {n}')
        for l in (errores.get(n) or [])[1:16]:
            print('    ' + l)
    if ok + mal == 0:
        print('No llegó a correr ningún caso: mirá el log.')
        return 1
    if ok + mal + salteados < total:
        print(f'\nOJO: corrieron {ok + mal + salteados} de {total} casos (¿se cortó la conexión con la tablet?).')
        return 1
    return 1 if mal else 0


if __name__ == '__main__':
    sys.exit(main())
