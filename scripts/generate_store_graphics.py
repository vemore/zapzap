#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pillow>=10.0",
# ]
# ///
"""Draw the Play Store icon and feature graphic of ZapZap from committed sources.

    uv run --script scripts/generate_store_graphics.py           # write both PNGs
    uv run --script scripts/generate_store_graphics.py --check   # verify them, write nothing

Ported from countscore's scripts/generate_icons.py and generate_feature_graphic.py. Every
pixel comes from a committed file, so the graphics are reproducible:

- store_listing/assets/icon_512.png, 512x512 32-bit RGBA (what Play asks for): the launcher
  icon's vector, frontend-flutter/assets/icon/icon.svg, rasterised by rsvg-convert;
- store_listing/assets/feature_graphic.png, 1024x500 opaque RGB: the icon and the name on the
  app's slate, and a winning ZapZap hand — ace, two, two and a joker, 5 points — fanned on the
  board's felt. The faces are the app's own, frontend-flutter/assets/cards/; the colours are
  AppColors in frontend-flutter/lib/utils/app_theme.dart. No text but the name, so one
  graphic serves every locale.

Requires rsvg-convert (librsvg; Debian/Ubuntu: librsvg2-bin), and Roboto Black from the
Flutter SDK's material_fonts cache — the font the app renders in.
"""

from __future__ import annotations

import argparse
import io
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ICON_SIZE = 512
WIDTH, HEIGHT = 1024, 500
SUPERSAMPLE = 2

ICON_SVG = "frontend-flutter/assets/icon/icon.svg"
CARDS = "frontend-flutter/assets/cards"
ICON_OUT = "store_listing/assets/icon_512.png"
GRAPHIC_OUT = "store_listing/assets/feature_graphic.png"

# AppColors, frontend-flutter/lib/utils/app_theme.dart.
SLATE_900 = (0x0F, 0x17, 0x2A)
SLATE_800 = (0x1E, 0x29, 0x3B)
AMBER_400 = (0xFB, 0xBF, 0x24)
FELT_CENTER = (0x1C, 0x7A, 0x45)
FELT_EDGE = (0x0B, 0x3B, 0x1F)
RIM_LIGHT = (0x5B, 0x3A, 0x22)
RIM_DARK = (0x2B, 0x17, 0x0B)
RIM_INLAY = (0x8A, 0x6A, 0x3A)

TITLE = "ZapZap"
# The hand: 1 + 2 + 2 + 0 = 5 points, a ZapZap (GAME_RULES.md, ZapZap eligibility).
HAND = ("ace_of_spades", "2_of_hearts", "2_of_clubs", "joker_red")
BADGE = "5"


class GraphicError(Exception):
    """A refusal with a message meant for the person running the script."""


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def rasterise(svg: Path, width: int, height: int | None = None) -> Image.Image:
    """`svg` as RGBA at `width` (and `height`), by rsvg-convert."""
    if not shutil.which("rsvg-convert"):
        raise GraphicError("rsvg-convert not found (Debian/Ubuntu: apt install librsvg2-bin)")
    if not svg.is_file():
        raise GraphicError(f"missing {svg}")
    cmd = ["rsvg-convert", "-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    png = subprocess.run([*cmd, str(svg)], check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def font(size: int) -> ImageFont.FreeTypeFont:
    flutter = shutil.which("flutter")
    if flutter:
        path = (
            Path(os.path.realpath(flutter)).parent
            / "cache" / "artifacts" / "material_fonts" / "Roboto-Black.ttf"
        )
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    raise GraphicError("Roboto-Black.ttf not found in the Flutter SDK's material_fonts")


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))  # type: ignore[return-value]


def rounded(img: Image.Image, radius: int) -> Image.Image:
    img = img.convert("RGBA")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    img.putalpha(mask)
    return img


# ----------------------------------------------------------------- the icon


def draw_icon() -> Image.Image:
    return rasterise(repo_root() / ICON_SVG, ICON_SIZE, ICON_SIZE)


# ----------------------------------------------------------------- the feature graphic


def background(w: int, h: int) -> Image.Image:
    """Slate, lighter at the top left, as the app's surfaces over its background."""
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        draw.line([(0, y), (w, y)], fill=mix(SLATE_800, SLATE_900, y / (h - 1)))
    return img


def felt(w: int, h: int) -> Image.Image:
    """The board: a wooden rim, its inlay, and the radial green felt, as RGBA."""
    s = SUPERSAMPLE
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([0, 0, w - 1, h - 1], fill=(*RIM_DARK, 255))
    draw.ellipse([4 * s, 4 * s, w - 1 - 4 * s, h - 1 - 4 * s], fill=(*RIM_LIGHT, 255))
    inset = 14 * s
    draw.ellipse([inset, inset, w - 1 - inset, h - 1 - inset], fill=(*RIM_INLAY, 255))
    inner = inset + 3 * s
    fw, fh = w - 2 * inner, h - 2 * inner
    cloth = Image.new("RGB", (fw, fh))
    cdraw = ImageDraw.Draw(cloth)
    steps = 60
    for i in range(steps):
        t = i / (steps - 1)
        box = [round(fw / 2 * t), round(fh / 2 * t), round(fw - fw / 2 * t), round(fh - fh / 2 * t)]
        if box[2] <= box[0] or box[3] <= box[1]:
            break
        cdraw.ellipse(box, fill=mix(FELT_EDGE, FELT_CENTER, math.sqrt(t)))
    mask = Image.new("L", (fw, fh), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, fw - 1, fh - 1], fill=255)
    img.paste(cloth, (inner, inner), mask)
    return img


def card(name: str, width: int) -> Image.Image:
    face = rasterise(repo_root() / CARDS / f"{name}.svg", width, round(width * 1.5))
    shadow = Image.new("RGBA", (face.width + 40, face.height + 40), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [20, 26, 20 + face.width, 26 + face.height], round(width * 0.08), fill=(0, 0, 0, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    shadow.alpha_composite(face, (20, 20))
    return shadow


def draw_graphic() -> Image.Image:
    s = SUPERSAMPLE
    w, h = WIDTH * s, HEIGHT * s
    img = background(w, h).convert("RGBA")

    # Right: the felt, bleeding off the right and bottom edges, and the hand fanned on it.
    board = felt(620 * s, 520 * s)
    img.alpha_composite(board, (470 * s, 40 * s))
    cx, cy = 755 * s, 560 * s  # the fan's pivot, below the cards
    radius = 330 * s
    angles = (-24, -8, 8, 24)
    for name, angle in zip(HAND, angles):
        face = card(name, 150 * s).rotate(-angle, resample=Image.BICUBIC, expand=True)
        rad = math.radians(angle)
        x = cx + radius * math.sin(rad) - face.width / 2
        y = cy - radius * math.cos(rad) - face.height / 2
        img.alpha_composite(face, (round(x), round(y)))

    # The hand's value, the ZapZap threshold: an amber disc with "5".
    draw = ImageDraw.Draw(img)
    bx, by, br = 895 * s, 108 * s, 44 * s
    draw.ellipse([bx - br, by - br, bx + br, by + br], fill=(*AMBER_400, 255),
                 outline=(*SLATE_900, 255), width=5 * s)
    draw.text((bx, by + 2 * s), BADGE, font=font(58 * s), fill=SLATE_900, anchor="mm")

    # Left: the icon over the name, centred in the safe area.
    icon_size = 150 * s
    icon = rounded(rasterise(repo_root() / ICON_SVG, icon_size, icon_size), round(icon_size * 0.22))
    left_cx = 260 * s
    img.alpha_composite(icon, (left_cx - icon_size // 2, 95 * s))
    draw.text((left_cx, 330 * s), TITLE, font=font(104 * s), fill=AMBER_400, anchor="mm")

    return img.resize((WIDTH, HEIGHT), Image.LANCZOS).convert("RGB")


# ----------------------------------------------------------------- commands


def check() -> list[str]:
    """What Play would refuse in the committed PNGs (a size, an alpha channel)."""
    problems = []
    for rel, size, modes in (
        (ICON_OUT, (ICON_SIZE, ICON_SIZE), ("RGBA",)),
        (GRAPHIC_OUT, (WIDTH, HEIGHT), ("RGB",)),
    ):
        path = repo_root() / rel
        if not path.is_file():
            problems.append(f"{rel} is missing")
            continue
        with Image.open(path) as im:
            if im.size != size:
                problems.append(f"{rel} is {im.width}x{im.height}, expected {size[0]}x{size[1]}")
            if im.mode not in modes:
                problems.append(f"{rel} is {im.mode}, expected {' or '.join(modes)}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Draw the Play Store icon and feature graphic.")
    parser.add_argument("--check", action="store_true", help="verify the committed PNGs only")
    args = parser.parse_args(argv)
    if args.check:
        problems = check()
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        print(f"check: {len(problems)} problem(s)")
        return 1 if problems else 0
    try:
        outputs = ((ICON_OUT, draw_icon()), (GRAPHIC_OUT, draw_graphic()))
    except (GraphicError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    for rel, img in outputs:
        out = repo_root() / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out, format="PNG", optimize=True)
        print(f"wrote {rel} ({img.width}x{img.height} {img.mode}, {out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
