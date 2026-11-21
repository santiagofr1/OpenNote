#!/usr/bin/env python3
"""Resume build/perf/*.timeline.json (traza Chrome de tool/traza.sh): para cada frame > 16 ms lista los eventos 'ON ...'
y los más largos que caen dentro (hilo de UI y hilo de raster por separado), y al final agrupa por nombre.
Uso: tool/traza_resumen.py [archivo.timeline.json ...] (por defecto build/perf/*.timeline.json)."""
import glob
import json
import sys
from collections import defaultdict

LIMITE_MS = 16.7
TOP = 25
FRAME_UI = ('Animator::BeginFrame', 'Frame')           # hilo de UI (build/layout/paint)
FRAME_RASTER = ('GPURasterizer::Draw', 'Rasterizer::DoDraw', 'Rasterizer::Draw')  # hilo de raster


def cargar(path):
    with open(path) as f:
        d = json.load(f)
    ev = d['traceEvents'] if isinstance(d, dict) else d
    return ev


def duraciones(ev):
    """Devuelve eventos [(nombre, ts_us, dur_us, tid, args)] juntando X, B/E y b/e (async, por id)."""
    out = []
    pila = defaultdict(list)  # (pid, tid) -> pila de B
    asy = {}                  # (cat, id, nombre) -> ts del b
    for e in sorted((e for e in ev if 'ts' in e), key=lambda e: e['ts']):
        ph, n = e.get('ph'), e.get('name', '')
        tid, pid = e.get('tid'), e.get('pid')
        if ph == 'X':
            out.append((n, e['ts'], e.get('dur', 0), tid, e.get('args') or {}))
        elif ph == 'B':
            pila[(pid, tid)].append(e)
        elif ph == 'E':
            p = pila[(pid, tid)]
            if p:
                b = p.pop()
                out.append((b.get('name', n), b['ts'], e['ts'] - b['ts'], tid, b.get('args') or {}))
        elif ph == 'b':
            asy[(e.get('cat'), str(e.get('id')), n)] = e
        elif ph == 'e':
            b = asy.pop((e.get('cat'), str(e.get('id')), n), None)
            if b:
                out.append((n, b['ts'], e['ts'] - b['ts'], 'async', b.get('args') or {}))
    return out


def frames(evs, nombres):
    return sorted((ts, ts + d) for n, ts, d, _, _ in evs if n in nombres and d > 0)


def dentro(evs, t0, t1, tids, solo_on):
    r = []
    for n, ts, d, tid, a in evs:
        if ts >= t0 and ts + d <= t1 and (tids is None or tid in tids) and d > 0:
            if n in FRAME_UI or n in FRAME_RASTER:
                continue
            if solo_on == n.startswith('ON '):
                r.append((n, d, a))
    return r


def tids_de(evs, nombres):
    return {tid for n, _, _, tid, _ in evs if n in nombres}


def main():
    paths = sys.argv[1:] or sorted(glob.glob('build/perf/*.timeline.json'))
    if not paths:
        print('No hay build/perf/*.timeline.json')
        return 1
    for path in paths:
        evs = duraciones(cargar(path))
        # los frames se buscan por nombre; si no está el primero se prueba el siguiente
        nom_ui = next((n for n in FRAME_UI if any(e[0] == n for e in evs)), None)
        nom_ra = next((n for n in FRAME_RASTER if any(e[0] == n for e in evs)), None)
        print(f'== {path}: {len(evs)} eventos; frames UI por "{nom_ui}", raster por "{nom_ra}"')
        if not nom_ui and not nom_ra:
            print('   no encontré eventos de frame (Animator::BeginFrame / GPURasterizer::Draw)')
            nombres = sorted({e[0] for e in evs if e[0].startswith('ON ')})
            print('   eventos ON presentes:', ', '.join(nombres) or '(ninguno)')
            continue
        tids_ui = tids_de(evs, {nom_ui}) if nom_ui else set()
        tids_ra = tids_de(evs, {nom_ra}) if nom_ra else set()
        fui = frames(evs, {nom_ui}) if nom_ui else []
        fra = frames(evs, {nom_ra}) if nom_ra else []
        lentos = [('UI', a, b) for a, b in fui if (b - a) / 1000 > LIMITE_MS] + \
                 [('RASTER', a, b) for a, b in fra if (b - a) / 1000 > LIMITE_MS]
        lentos.sort(key=lambda x: x[1])
        print(f'   frames UI {len(fui)} ({sum(1 for x in lentos if x[0] == "UI")} > {LIMITE_MS} ms), '
              f'raster {len(fra)} ({sum(1 for x in lentos if x[0] == "RASTER")} > {LIMITE_MS} ms)')
        # agrupado: nombre -> [veces, total_us, peor_us]
        grupo = defaultdict(lambda: [0, 0, 0])
        t_ini = lentos[0][1] if lentos else 0
        mostrados = 0
        for hilo, a, b in lentos:
            tids = tids_ui if hilo == 'UI' else tids_ra
            ons = dentro(evs, a, b, tids if hilo == 'UI' else None, True)
            otros = sorted(dentro(evs, a, b, tids, False), key=lambda x: -x[1])[:3]
            # los ON async (tareas) pueden caer en cualquier hilo: se cuentan si se solapan
            ons += [(n, d, x) for n, ts, d, tid, x in evs
                    if tid == 'async' and n.startswith('ON ') and ts < b and ts + d > a and hilo == 'UI']
            for n, d, _ in ons + otros:
                g = grupo[(hilo, n)]
                g[0] += 1
                g[1] += d
                g[2] = max(g[2], d)
            if mostrados < 40:
                mostrados += 1
                partes = [f'{n} {d / 1000:.1f}' for n, d, _ in sorted(ons, key=lambda x: -x[1])[:6]]
                partes += [f'({n} {d / 1000:.1f})' for n, d, _ in otros]
                print(f'   {hilo:6} +{(a - t_ini) / 1e6:6.2f}s {(b - a) / 1000:5.1f} ms | ' + '; '.join(partes))
        if len(lentos) > 40:
            print(f'   ... {len(lentos) - 40} frames lentos más (solo se listan 40; el agrupado cuenta todos)')
        print(f'\n   Por evento en frames lentos (top {TOP}, por tiempo total; ms) [entre paréntesis: no son ON]:')
        print(f'   {"hilo":6} {"veces":>5} {"total":>8} {"peor":>7}  evento')
        for (hilo, n), (c, tot, peor) in sorted(grupo.items(), key=lambda kv: -kv[1][1])[:TOP]:
            print(f'   {hilo:6} {c:5d} {tot / 1000:8.1f} {peor / 1000:7.1f}  {n}')
        todos = defaultdict(lambda: [0, 0])
        for n, _, d, _, _ in evs:
            if n.startswith('ON '):
                todos[n][0] += 1
                todos[n][1] += d
        print('\n   Todos los eventos ON de la corrida (veces, total ms):')
        for n, (c, tot) in sorted(todos.items(), key=lambda kv: -kv[1][1])[:TOP]:
            print(f'   {c:6d} {tot / 1000:9.1f}  {n}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
