"""Génère les icônes de la PWA Limpid à partir des tokens du design system.

Les couleurs ne sont pas écrites ici : elles sont lues dans
``packages/limpid_design_system/tokens.json``, qui est la source de vérité
(la même que ``docs/DESIGN_SYSTEM.md`` §2.2 et les constantes Dart).

    python apps/limpid_app/tool/generate_icons.py

Le marque est le « L. » des maquettes : un L en ``fgDefault`` et un point en
``accent``, le seul accent de la marque.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# La console Windows est en cp1252 : sans cela, la flèche du journal
# d'exécution fait échouer le script.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

APP_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = APP_DIR.parent.parent
TOKENS_PATH = REPO_DIR / "packages" / "limpid_design_system" / "tokens.json"
WEB_DIR = APP_DIR / "web"
ICONS_DIR = WEB_DIR / "icons"

# Georgia est la serif la plus proche de Fraunces (la police d'affichage du
# design system) parmi les polices livrées avec Windows.
FONT_REGULAR = Path("C:/Windows/Fonts/georgia.ttf")
FONT_BOLD = Path("C:/Windows/Fonts/georgiab.ttf")

# Les icônes installables sur un écran d'accueil : nom du fichier et taille.
STANDARD_ICONS = ((192, "Icon-192.png"), (512, "Icon-512.png"))
# Les icônes « maskable » : le système découpe la forme, le marque doit tenir
# dans la zone sûre centrale.
MASKABLE_ICONS = ((192, "Icon-maskable-192.png"), (512, "Icon-maskable-512.png"))
FAVICON_SIZE = 64


def load_theme() -> tuple[str, str, str]:
    """Retourne (fond, couleur du L, couleur du point) du thème papier."""
    tokens = json.loads(TOKENS_PATH.read_text(encoding="utf-8"))
    paper = tokens["colors"]["paper"]
    return paper["bgCanvas"], paper["fgDefault"], paper["accent"]


def draw_mark(
    size: int,
    font_size: int,
    background: str,
    letter_color: str,
    dot_color: str,
    corner_radius: int = 0,
) -> Image.Image:
    """Dessine le marque « L. » centré sur un fond uni."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if corner_radius > 0:
        draw.rounded_rectangle(
            (0, 0, size - 1, size - 1),
            radius=corner_radius,
            fill=background,
        )
    else:
        draw.rectangle((0, 0, size - 1, size - 1), fill=background)

    font = ImageFont.truetype(str(FONT_REGULAR), font_size)

    # Le « L. » est composé sur un calque séparé pour pouvoir colorier le L et
    # le point différemment, puis collage au centre exact de l'image.
    layer = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    layer_draw = ImageDraw.Draw(layer)

    letter_width = layer_draw.textlength("L", font=font)
    layer_draw.text((0, 0), "L", font=font, fill=letter_color, anchor="la")
    layer_draw.text(
        (letter_width, 0),
        ".",
        font=font,
        fill=dot_color,
        anchor="la",
    )

    box = layer.getbbox()
    if box is None:
        raise RuntimeError("The mark could not be drawn.")
    mark = layer.crop(box)

    offset = ((size - mark.width) // 2, (size - mark.height) // 2)
    image.alpha_composite(mark, offset)
    return image


def save_png(image: Image.Image, path: Path) -> None:
    """Enregistre l'image en PNG 8 bits, optimisée pour le web."""
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path, "PNG", optimize=True)
    print(f"→ {path.relative_to(REPO_DIR)}")


def main() -> None:
    background, letter_color, dot_color = load_theme()

    for size, name in STANDARD_ICONS:
        save_png(
            draw_mark(
                size,
                int(size * 0.46),
                background,
                letter_color,
                dot_color,
            ),
            ICONS_DIR / name,
        )

    for size, name in MASKABLE_ICONS:
        # La zone sûre d'une icône maskable est le cercle central de 80 % :
        # le marque ne doit pas dépasser 50 % de la largeur.
        save_png(
            draw_mark(
                size,
                int(size * 0.30),
                background,
                letter_color,
                dot_color,
            ),
            ICONS_DIR / name,
        )

    save_png(
        draw_mark(
            FAVICON_SIZE,
            int(FAVICON_SIZE * 0.56),
            background,
            letter_color,
            dot_color,
            corner_radius=12,
        ),
        WEB_DIR / "favicon.png",
    )


if __name__ == "__main__":
    main()
