#!/usr/bin/env python3
"""Genera el icono adaptativo de OpenNote (opciones A/B/C).

Uso:
  icon_tool.py svgs  <out_dir>            SVG fg/bg/mono de las 3 opciones
  icon_tool.py previews <out_dir>         hojas de preview + opciones.png
  icon_tool.py android <A|B|C> <res_dir>  recursos Android (vector + PNG legacy)
Requiere cairosvg (solo para previews/android).
"""
import math, os, sys

# ---- geometria ------------------------------------------------------------
def rot(pts, ang, tx, ty):
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(round(x * c - y * s + tx, 2), round(x * s + y * c + ty, 2)) for x, y in pts]

def poly(pts):
    return "M" + " L".join(f"{x} {y}" for x, y in pts) + " Z"

def nib_paths(tx, ty, ang):
    # pluma con la punta en (0,0) y el cuerpo hacia -y
    body = [(0, 0), (-3.5, -9), (-8, -19), (-8, -40), (8, -40), (8, -19), (3.5, -9)]
    slit = [(0, -3), (0, -17)]
    return poly(rot(body, ang, tx, ty)), "M" + " L".join(f"{x} {y}" for x, y in rot(slit, ang, tx, ty))

# ---- opciones -------------------------------------------------------------
INK = "#F2A93B"
def option_A():
    paper = "M35 24 H62 L77 39 V80 A4 4 0 0 1 73 84 H35 A4 4 0 0 1 31 80 V28 A4 4 0 0 1 35 24 Z"
    fold = "M62 24 V35 A4 4 0 0 0 66 39 H77 Z"
    ink = "M36 70 C45 52 52 80 61 61 S76 48 84 44"
    return dict(
        name="Hoja con trazo",
        bg=("#1F7A74", "#0F4C4A"),
        fg=[dict(d=paper, fill="#F8F5EC"), dict(d=fold, fill="#CFC8B4"),
            dict(d="M38 38 H54", stroke="#C9D3D0", sw=3, cap="round"),
            dict(d="M38 48 H66", stroke="#C9D3D0", sw=3, cap="round"),
            dict(d=ink, stroke=INK, sw=5.5, cap="round", join="round")],
        mono=[dict(d=paper.replace("Z", "") + "M62 24 V35 A4 4 0 0 0 66 39 H77", stroke="#000", sw=4, cap="round", join="round"),
              dict(d=ink, stroke="#000", sw=5.5, cap="round", join="round")])

def option_B():
    nb = "M32 24 H72 A4 4 0 0 1 76 28 V80 A4 4 0 0 1 72 84 H32 A4 4 0 0 1 28 80 V28 A4 4 0 0 1 32 24 Z"
    rings = [dict(d=f"M23 {y} H35", stroke="#F2A93B", sw=4.5, cap="round") for y in (34, 46, 58, 70)]
    body, slit = nib_paths(46, 80, 45)
    return dict(
        name="Cuaderno y pluma",
        bg=("#3F51B5", "#283593"),
        fg=[dict(d=nb, fill="#F4F6FF")] + rings + [
            dict(d="M46 36 H66", stroke="#C5CAE9", sw=3, cap="round"),
            dict(d="M46 46 H66", stroke="#C5CAE9", sw=3, cap="round"),
            dict(d=body, fill="#FFB74D", stroke="#283593", sw=2.2, join="round"),
            dict(d=slit, stroke="#283593", sw=1.8, cap="round")],
        mono=[dict(d=nb, stroke="#000", sw=4, join="round")] +
             [dict(d=f"M23 {y} H35", stroke="#000", sw=4.5, cap="round") for y in (34, 46, 58, 70)] +
             [dict(d=body, fill="#000", stroke="#000", sw=3, join="round")])

def option_C():
    # O y N con un solo trazo continuo
    d = ("M53 52 C53 43 48 36 40 36 C32 36 27 44 27 54 C27 64 32 72 40 72 "
         "C48 72 53 64 55 54 C56 48 58 42 60 36 L78 72 V36")
    return dict(
        name="O + N en un trazo",
        bg=("#D9603B", "#A8402A"),
        fg=[dict(d=d, stroke="#FFF3E0", sw=6.5, cap="round", join="round")],
        mono=[dict(d=d, stroke="#000", sw=6.5, cap="round", join="round")])

OPTIONS = {"A": option_A(), "B": option_B(), "C": option_C()}

# ---- SVG ------------------------------------------------------------------
def attrs(e, color=None):
    a = [f'd="{e["d"]}"']
    fill, stroke = e.get("fill"), e.get("stroke")
    if color:
        fill = color if fill else None
        stroke = color if stroke else None
    a.append(f'fill="{fill}"' if fill else 'fill="none"')
    if stroke:
        a.append(f'stroke="{stroke}" stroke-width="{e["sw"]}"')
        if e.get("cap"): a.append(f'stroke-linecap="{e["cap"]}"')
        a.append(f'stroke-linejoin="{e.get("join", "round")}"')
    return " ".join(a)

def layer(elems, color=None):
    return "\n".join(f"  <path {attrs(e, color)}/>" for e in elems)

def bg_inner(o, gid):
    c1, c2 = o["bg"]
    return (f'  <defs><linearGradient id="{gid}" x1="0" y1="0" x2="108" y2="108" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>\n'
            f'  <rect width="108" height="108" fill="url(#{gid})"/>')

def wrap(inner, extra=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="432" height="432"{extra}>\n{inner}\n</svg>\n'

def write_svgs(out):
    os.makedirs(out, exist_ok=True)
    for k, o in OPTIONS.items():
        w = lambda n, s: open(f"{out}/{k}-{n}.svg", "w").write(s)
        w("foreground", wrap(layer(o["fg"])))
        w("background", wrap(bg_inner(o, "g")))
        w("monochrome", wrap(layer(o["mono"], "#000")))

# ---- previews -------------------------------------------------------------
def squircle(cx, cy, r, n=4.5, steps=120):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** (2 / n), c), cy + r * math.copysign(abs(s) ** (2 / n), s)))
    return poly([(round(x, 2), round(y, 2)) for x, y in pts])

SHAPES = {
    "circle": "M54 18 A36 36 0 1 1 54 90 A36 36 0 1 1 54 18 Z",
    "squircle": squircle(54, 54, 36),
    "rounded": "M34 18 H74 A16 16 0 0 1 90 34 V74 A16 16 0 0 1 74 90 H34 A16 16 0 0 1 18 74 V34 A16 16 0 0 1 34 18 Z",
}
_uid = [0]
def tile(x, y, size, o, shape, mode="color", themed=None):
    """Tile de `size` px mostrando el area visible (72 de 108) con mascara."""
    _uid[0] += 1
    u = _uid[0]
    if mode == "color":
        inner = bg_inner(o, f"g{u}") + "\n" + layer(o["fg"])
    else:
        bgc, fgc = themed
        inner = f'  <rect width="108" height="108" fill="{bgc}"/>\n' + layer(o["mono"], fgc)
    return (f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="18 18 72 72">'
            f'<defs><clipPath id="c{u}"><path d="{SHAPES[shape]}"/></clipPath></defs>'
            f'<g clip-path="url(#c{u})">{inner}</g></svg>')

def text(x, y, s, size=14, anchor="middle", fill="#444", weight="normal"):
    return (f'<text x="{x}" y="{y}" font-family="DejaVu Sans, sans-serif" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}">{s}</text>')

LIGHT = ("#DCE6EA", "#2E4A55")
DARK = ("#2A3238", "#B9D4E0")

def sheet_svg(k):
    o = OPTIONS[k]
    W, H = 3 * 192 + 4 * 24, 192 + 24 + 130 + 24 + 130 + 30
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">',
         f'<rect width="{W}" height="{H}" fill="#F3F3F1"/>',
         text(24, 34, f'{k} - {o["name"]}', 20, "start", "#222", "bold")]
    y0 = 52
    for i, s in enumerate(("circle", "squircle", "rounded")):
        x = 24 + i * (192 + 24)
        p.append(tile(x, y0, 192, o, s))
        p.append(text(x + 96, y0 + 192 + 18, s, 12))
    y1 = y0 + 192 + 40
    p.append(tile(24, y1, 48, o, "circle"))
    p.append(tile(24 + 72, y1, 48, o, "squircle"))
    p.append(tile(24 + 144, y1, 48, o, "rounded"))
    p.append(text(24, y1 + 68, "48 px", 12, "start"))
    y2 = y1 + 90
    for i, (nm, th) in enumerate((("tematizado claro", LIGHT), ("tematizado oscuro", DARK))):
        x = 24 + i * (192 + 24) * 1.5
        p.append(tile(x, y2, 120, o, "circle", "mono", th))
        p.append(tile(x + 132, y2, 120, o, "squircle", "mono", th))
        p.append(text(x, y2 + 138, nm, 12, "start"))
    p.append("</svg>")
    return "\n".join(p)

def comparison_svg():
    cell, pad = 216, 30
    W, H = 3 * cell + 4 * pad, cell + 360
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">',
         f'<rect width="{W}" height="{H}" fill="#F3F3F1"/>']
    for i, k in enumerate("ABC"):
        o = OPTIONS[k]
        x = pad + i * (cell + pad)
        p.append(text(x + cell / 2, 44, k, 34, fill="#222", weight="bold"))
        p.append(tile(x, 64, cell, o, "squircle"))
        p.append(text(x + cell / 2, 64 + cell + 24, o["name"], 13))
        yy = 64 + cell + 44
        p.append(tile(x, yy, 48, o, "circle"))
        p.append(tile(x + 60, yy, 48, o, "squircle"))
        p.append(tile(x + 120, yy, 48, o, "rounded"))
        yy += 64
        p.append(tile(x, yy, 80, o, "circle", "mono", LIGHT))
        p.append(tile(x + 92, yy, 80, o, "circle", "mono", DARK))
    p.append("</svg>")
    return "\n".join(p)

def render(svg, path, scale=1):
    import cairosvg
    cairosvg.svg2png(bytestring=svg.encode(), write_to=path, scale=scale)

def write_previews(out):
    os.makedirs(out, exist_ok=True)
    for k in "ABC":
        render(sheet_svg(k), f"{out}/preview-{k}.png")
    render(comparison_svg(), f"{out}/opciones.png")

# ---- Android --------------------------------------------------------------
def vd_color(c):
    return c.upper().replace("#", "#FF") if len(c) == 7 else c

def vd_path(e, color=None):
    fill, stroke = e.get("fill"), e.get("stroke")
    if color:
        fill = color if fill else None
        stroke = color if stroke else None
    s = f'    <path android:pathData="{e["d"]}"'
    if fill: s += f'\n        android:fillColor="{vd_color(fill)}"'
    if stroke:
        s += (f'\n        android:strokeColor="{vd_color(stroke)}"\n        android:strokeWidth="{e["sw"]}"'
              f'\n        android:strokeLineCap="{e.get("cap", "butt")}"\n        android:strokeLineJoin="{e.get("join", "round")}"')
    return s + "/>"

VD_HEAD = ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
           '    xmlns:aapt="http://schemas.android.com/aapt"\n'
           '    android:width="108dp" android:height="108dp"\n'
           '    android:viewportWidth="108" android:viewportHeight="108">\n')

def write_android(k, res):
    o = OPTIONS[k]
    os.makedirs(f"{res}/drawable", exist_ok=True)
    os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
    def vd(name, body):
        open(f"{res}/drawable/{name}.xml", "w").write(VD_HEAD + body + "\n</vector>\n")
    vd("ic_launcher_foreground", "\n".join(vd_path(e) for e in o["fg"]))
    vd("ic_launcher_monochrome", "\n".join(vd_path(e, "#000000") for e in o["mono"]))
    c1, c2 = o["bg"]
    vd("ic_launcher_background",
       '    <path android:pathData="M0,0 H108 V108 H0 Z">\n      <aapt:attr name="android:fillColor">\n'
       f'        <gradient android:type="linear" android:startX="0" android:startY="0" android:endX="108" android:endY="108">\n'
       f'          <item android:offset="0" android:color="{vd_color(c1)}"/>\n'
       f'          <item android:offset="1" android:color="{vd_color(c2)}"/>\n'
       '        </gradient>\n      </aapt:attr>\n    </path>')
    open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n')
    # PNG legacy (API < 26): cuadrado redondeado con el area visible
    for dens, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = f"{res}/mipmap-{dens}"
        os.makedirs(d, exist_ok=True)
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}">'
               + tile(0, 0, px, o, "rounded") + "</svg>")
        render(svg, f"{d}/ic_launcher.png")

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["svgs"]: write_svgs(a[1])
    elif a[:1] == ["previews"]: write_previews(a[1])
    elif a[:1] == ["android"] and a[1] in OPTIONS: write_android(a[1], a[2])
    else: sys.exit(__doc__)
