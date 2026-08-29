#!/usr/bin/env python3
"""Fuente del icono de la app (símbolo de marca del Design System 4:
"las dos mitades que cierran un cuadro", `foundations/logo.html` variante A).

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

GRAD_FROM = "#5B4CA8"
GRAD_TO = "#5B4CA8"

# Radio de esquina del icono legacy (22.37% ~ squircle de Android/iOS)
CORNER = 229

# Símbolo: dos trazos en L que giran 180° entre sí, tomados tal cual de
# `assets/logo.svg` (viewBox 24x24, centrado en 12,12). Se escala y se
# recentra en el lienzo de 1024x1024 dejando margen (el arte original ocupa
# ~62% del viewBox, demasiado para el icono adaptativo una vez agrandado en
# `agrandar()` para compensar el <inset> de flutter_launcher_icons).
TRAZO_A = "M15.5 4.5H7A2.5 2.5 0 0 0 4.5 7v8.5"
TRAZO_B = "M8.5 19.5H17A2.5 2.5 0 0 0 19.5 17V8.5"
ESCALA_SIMBOLO = 30
CENTRO_SIMBOLO = 512 - 12 * ESCALA_SIMBOLO


def _simbolo(color):
    return (
        f'<g transform="translate({CENTRO_SIMBOLO:.4f},{CENTRO_SIMBOLO:.4f}) '
        f'scale({ESCALA_SIMBOLO:.4f})">'
        f'<path d="{TRAZO_A}" fill="none" stroke="{color}" stroke-width="2.5" '
        f'stroke-linecap="round"/>'
        f'<path d="{TRAZO_B}" fill="none" stroke="{color}" stroke-width="2.5" '
        f'stroke-linecap="round"/>'
        f'</g>'
    )


def arte_color():
    return _simbolo("#FFFFFF")


def arte_monocromo():
    """Silueta blanca: el sistema la tiñe."""
    return _simbolo("#FFFFFF")


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
