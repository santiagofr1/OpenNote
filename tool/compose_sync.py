#!/usr/bin/env python3
"""Arma docs/img/07_sync.png: la captura de la tablet (07a) a la izquierda y la de la ventana de PC (07b) a la derecha,
las dos a la misma altura, sobre fondo oscuro. Uso: python3 -I tool/compose_sync.py <07a.png> <07b.png> <salida.png>"""
import sys

from PIL import Image

BG = (13, 17, 23)  # #0d1117, el fondo de la 07_sync.png de siempre
MARGIN = 24        # margen exterior y separación entre las dos capturas
HEIGHT = 948       # alto total de la imagen


def fit(im, h):
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)


def main(a_path, b_path, out_path):
    h = HEIGHT - 2 * MARGIN
    a = fit(Image.open(a_path).convert('RGB'), h)
    b = fit(Image.open(b_path).convert('RGB'), h)
    canvas = Image.new('RGB', (3 * MARGIN + a.width + b.width, HEIGHT), BG)
    canvas.paste(a, (MARGIN, MARGIN))
    canvas.paste(b, (2 * MARGIN + a.width, MARGIN))
    canvas.save(out_path)
    print('Captura:', out_path, canvas.width, 'x', canvas.height)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
