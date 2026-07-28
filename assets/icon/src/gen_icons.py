#!/usr/bin/env python3
"""Fuente del icono de la app (concepto "recibo verificado").

Genera los SVG y los rasteriza a los PNG de 1024x1024 que consume
flutter_launcher_icons. Tras ejecutarlo hay que regenerar los mipmaps:

    python3 assets/icon/src/gen_icons.py
    dart run flutter_launcher_icons

Requiere Google Chrome instalado (se usa en modo headless para rasterizar).
"""
import os
import subprocess

SRC = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(SRC)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

GREEN = "#10B981"
LIGHT = "#BAD6F2"
GRAD_FROM = "#2E8BEE"
GRAD_TO = "#1257A8"

# Radio de esquina del icono legacy (22.37% ~ squircle de Android/iOS)
CORNER = 229

# Recibo: esquinas superiores redondeadas y borde inferior dentado.
RECIBO = ("M 310 324 a 36 36 0 0 1 36 -36 h 258 a 36 36 0 0 1 36 36 V 688 "
          "L 585 730 L 530 688 L 475 730 L 420 688 L 365 730 L 310 688 Z")
BARRAS = [(356, 372, 238), (356, 442, 168), (356, 512, 114)]
SELLO = (648, 640)          # centro del sello verde
SELLO_R, ANILLO_R = 104, 119
CHECK = "M 598 640 L 634 676 L 702 604"
# Desplazamiento que centra el conjunto recibo+sello en el lienzo.
OFFSET = "translate(-26,-12)"


def _barras(fill):
    return "".join(
        f'<rect x="{x}" y="{y}" width="{w}" height="30" rx="15" fill="{fill}"/>'
        for x, y, w in BARRAS
    )


def arte_color():
    cx, cy = SELLO
    return f"""
    <g transform="{OFFSET}">
      <path d="{RECIBO}" fill="#FFFFFF"/>
      {_barras(LIGHT)}
      <circle cx="{cx}" cy="{cy}" r="{ANILLO_R}" fill="#FFFFFF"/>
      <circle cx="{cx}" cy="{cy}" r="{SELLO_R}" fill="{GREEN}"/>
      <path d="{CHECK}" fill="none" stroke="#FFFFFF" stroke-width="30"
            stroke-linecap="round" stroke-linejoin="round"/>
    </g>"""


def arte_monocromo():
    """Silueta blanca: el sistema la tiñe. Barras y check van calados."""
    cx, cy = SELLO
    return f"""
    <mask id="mono" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#FFF"/>
      {_barras("#000")}
      <circle cx="{cx}" cy="{cy}" r="{ANILLO_R}" fill="#000"/>
      <circle cx="{cx}" cy="{cy}" r="{SELLO_R}" fill="#FFF"/>
      <path d="{CHECK}" fill="none" stroke="#000" stroke-width="30"
            stroke-linecap="round" stroke-linejoin="round"/>
    </mask>
    <g transform="{OFFSET}" mask="url(#mono)">
      <path d="{RECIBO}" fill="#FFFFFF"/>
      <circle cx="{cx}" cy="{cy}" r="{SELLO_R}" fill="#FFFFFF"/>
    </g>"""


def svg(contenido):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 1024 1024"><defs>'
        f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{GRAD_FROM}"/>'
        f'<stop offset="1" stop-color="{GRAD_TO}"/></linearGradient>'
        f"</defs>{contenido}</svg>"
    )


FONDO_PLENO = '<rect width="1024" height="1024" fill="url(#bg)"/>'
FONDO_REDONDEADO = f'<rect width="1024" height="1024" rx="{CORNER}" fill="url(#bg)"/>'

# El arte cabe justo en la zona segura del icono adaptativo: su punto más lejano
# queda a 313px del centro, el radio de la keyline de 66dp sobre un lienzo de 1024.
# Pero flutter_launcher_icons envuelve las capas frontales en un <inset> del 16%
# por lado, así que ahí las agrandamos 1/0.68 para que el inset las devuelva al
# tamaño correcto. Si algún día ese inset desaparece, este factor sobra.
INSET = 0.16
ESCALA = 1 / (1 - 2 * INSET)


def agrandar(arte):
    return f'<g transform="translate(512,512) scale({ESCALA:.4f}) translate(-512,-512)">{arte}</g>'


ARCHIVOS = {
    "app_icon": FONDO_REDONDEADO + arte_color(),        # icono legacy (Android < 8)
    "app_icon_foreground": agrandar(arte_color()),      # capa frontal del adaptativo
    "app_icon_background": FONDO_PLENO,                 # capa de fondo del adaptativo
    "app_icon_monochrome": agrandar(arte_monocromo()),  # temáticos (Android 13+)
}

for nombre, contenido in ARCHIVOS.items():
    ruta_svg = f"{SRC}/{nombre}.svg"
    with open(ruta_svg, "w") as f:
        f.write(svg(contenido))
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
         "--force-device-scale-factor=1", "--window-size=1024,1024",
         "--default-background-color=00000000",
         f"--screenshot={OUT}/{nombre}.png", ruta_svg],
        check=True, capture_output=True,
    )
    print(f"✅ {nombre}.png")
