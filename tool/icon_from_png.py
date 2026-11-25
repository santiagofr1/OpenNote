#!/usr/bin/env python3
"""Genera todos los íconos de Vynote a partir del PNG del logo (tool/icon/vynote.png).

El PNG trae la V blanca sobre un cuadrado redondeado violeta (con un halo alrededor). Se separa en dos capas:
  - fondo: el degradé violeta, ajustado con un polinomio de grado 2 sobre los píxeles del fondo (queda liso y se
    puede estirar a todo el lienzo del ícono adaptativo);
  - frente: la V, con alfa sacado de cuánto se acerca cada píxel al blanco respecto del fondo.

Salidas:
  - Android: ícono adaptativo (fondo, frente y monocromo en mipmap-*/) y el ícono viejo ic_launcher.png;
  - Windows: windows/runner/resources/app_icon.ico;
  - docs/img/icon.png (512 px, para el README).
El .deb de Linux toma docs/img/icon.png (ver tool/build_deb.sh).

Uso: tool/icon_from_png.py [png]   (requiere numpy y Pillow)
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android/app/src/main/res')
DPIS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
V_SCALE_ADAPTIVE = 0.47  # ancho de la V sobre el lienzo de 108 dp (lo visible en un círculo son 72 dp)


def feats(x, y):
    return np.stack([np.ones_like(x), x, y, x * x, y * y, x * y], -1)


def split(path):
    a = np.asarray(Image.open(path).convert('RGBA')).astype(float)
    rgb, al = a[..., :3], a[..., 3]
    sat = rgb.max(-1) - rgb.min(-1)
    ys, xs = np.where((al >= 250) & (sat > 90))  # fondo: opaco y saturado (la V es casi blanca)
    coefs = [np.linalg.lstsq(feats(xs.astype(float), ys.astype(float)), rgb[ys, xs, c], rcond=None)[0] for c in range(3)]
    yy, xx = np.mgrid[0:al.shape[0], 0:al.shape[1]].astype(float)
    bg = np.stack([np.clip(feats(xx, yy) @ c, 0, 255) for c in coefs], -1)
    d = 255 - bg
    t = ((rgb - bg) * d).sum(-1) / np.maximum((d * d).sum(-1), 1)
    t = np.clip((t - 0.08) / 0.84, 0, 1)
    t[al < 250] = 0
    fg = Image.fromarray(np.dstack([rgb, t * 255]).clip(0, 255).astype(np.uint8))
    sq = np.where(al >= 250)
    square = (sq[1].min(), sq[0].min(), sq[1].max() + 1, sq[0].max() + 1)  # el cuadrado violeta, sin el halo
    return fg, coefs, square


def gradient(coefs, square, size):
    """El degradé del fondo en un lienzo de size x size que cubre el cuadrado violeta."""
    x0, y0, x1, y1 = square
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    sx, sy = x0 + (xx + 0.5) / size * (x1 - x0), y0 + (yy + 0.5) / size * (y1 - y0)
    img = np.stack([np.clip(feats(sx, sy) @ c, 0, 255) for c in coefs] + [np.full((size, size), 255.0)], -1)
    return Image.fromarray(img.astype(np.uint8))


def place_v(fg, square, size, v_frac):
    """La V centrada como en el original, con ancho v_frac * size, en un lienzo transparente."""
    x0, y0, x1, y1 = square
    v = fg.crop(fg.getbbox())
    vb = fg.getbbox()
    s = v_frac * size / v.width
    v = v.resize((max(1, round(v.width * s)), max(1, round(v.height * s))), Image.LANCZOS)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2  # el desplazamiento de la V respecto del centro se conserva
    ox = size / 2 + (vb[0] - cx) * s
    oy = size / 2 + (vb[1] - cy) * s
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(v, (round(ox), round(oy)))
    return out


def rounded(img, radius_frac):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius_frac * img.width, fill=255)
    out = img.copy()
    out.putalpha(m)
    return out


def full_icon(fg, coefs, square, size):
    """El ícono entero (cuadrado redondeado con la V), con la proporción del original."""
    big = size * 4
    x0, y0, x1, y1 = square
    v_frac = (fg.getbbox()[2] - fg.getbbox()[0]) / (x1 - x0)
    img = gradient(coefs, square, big)
    img.alpha_composite(place_v(fg, square, big, v_frac))
    return rounded(img, 0.22).resize((size, size), Image.LANCZOS)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'tool/icon/vynote.png')
    fg, coefs, square = split(src)
    for dpi, k in DPIS.items():
        d = os.path.join(RES, f'mipmap-{dpi}')
        os.makedirs(d, exist_ok=True)
        n = round(108 * k)
        gradient(coefs, square, n).save(os.path.join(d, 'ic_launcher_background.png'))
        front = place_v(fg, square, n * 4, V_SCALE_ADAPTIVE).resize((n, n), Image.LANCZOS)
        front.save(os.path.join(d, 'ic_launcher_foreground.png'))
        mono = Image.new('RGBA', (n, n), (255, 255, 255, 0))
        mono.putalpha(front.getchannel('A'))
        mono.save(os.path.join(d, 'ic_launcher_monochrome.png'))
        # ícono viejo (Android < 8): 48 dp con 2 dp de margen
        n48, pad = round(48 * k), round(2 * k)
        legacy = Image.new('RGBA', (n48, n48), (0, 0, 0, 0))
        legacy.alpha_composite(full_icon(fg, coefs, square, n48 - 2 * pad), (pad, pad))
        legacy.save(os.path.join(d, 'ic_launcher.png'))
    # el .deb escala el de xxxhdpi hasta 256 px: se deja uno de 512 sin margen en docs/img
    icon512 = full_icon(fg, coefs, square, 512)
    icon512.save(os.path.join(ROOT, 'docs/img/icon.png'))
    ico = full_icon(fg, coefs, square, 256)
    ico.save(os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('Íconos generados desde', src)


if __name__ == '__main__':
    main()
