#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pillow>=10.0",
# ]
# ///
"""Compose the Play Store phone screenshots from the raw captures, one set per store locale.

    uv run --script scripts/compose_store_screenshots.py --raw <dir>                # every locale
    uv run --script scripts/compose_store_screenshots.py --raw <dir> --locale fr-FR # one locale
    uv run --script scripts/compose_store_screenshots.py --check                    # verify only

Ported from countscore's scripts/compose_screenshots.py. scripts/capture_store_screenshots.sh
runs it; the raw captures are that script's (<raw>/<locale>/<stem>.png, 1170x2532 from the
Flutter web build, so no system bar to crop) and are not committed: the capture is automated,
so a new set is one command away.

Captions: store_listing/<locale>/screenshot_captions.txt, one `<stem>: <caption>` line per
capture, `#` for a comment, `|` to force the line break.

Output: store_listing/<locale>/screenshots/phone/<stem>.png, 1080x1920 opaque RGB — the caption
in a band above the screen, on a gradient of the app's slate (frontend-flutter/lib/utils/
app_theme.dart), the caption in its amber. The directory holds exactly the composed set: a PNG
there with no raw capture of that name is removed on compose.

Font: Roboto Bold from the Flutter SDK's material_fonts cache (the font the app renders in);
--font overrides it.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 1080, 1920
LISTING_ROOT = "store_listing"
CAPTIONS_FILE = "screenshot_captions.txt"
OUT_DIR = Path("screenshots") / "phone"

# The app's colours, frontend-flutter/lib/utils/app_theme.dart (AppColors).
SLATE_900 = (0x0F, 0x17, 0x2A)  # the background
SLATE_800 = (0x1E, 0x29, 0x3B)  # the surfaces
AMBER_400 = (0xFB, 0xBF, 0x24)  # the primary
BACKGROUND, BACKGROUND_BOTTOM = SLATE_800, SLATE_900
SHADOW = (0x02, 0x06, 0x17)
FRAME = (0x47, 0x55, 0x69)  # slate-600, the outline: the dark screen's edge on the dark ground
BAND_HEIGHT = 340
SIDE_MARGIN = 72
BOTTOM_MARGIN = 64
SCREEN_RADIUS = 40
MAX_FONT_SIZE = 84
MIN_FONT_SIZE = 48
MAX_LINES = 2
LINE_SPACING = 1.18
CLAUSE_END = (",", "?", ":", "!", ";", "—")
BREAK = "|"
FONT_NAME = "Roboto-Bold.ttf"


class ComposeError(Exception):
    """A refusal with a message meant for the person running the script."""


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def listing_locales(root: Path) -> list[str]:
    base = root / LISTING_ROOT
    return sorted(
        d.name
        for d in base.iterdir()
        if d.is_dir() and d.name != "assets" and (d / "title.txt").is_file()
    )


def read_captions(path: Path, stems: list[str]) -> dict[str, str]:
    """`<stem>: <caption>` per line; every capture needs exactly one caption."""
    captions: dict[str, str] = {}
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        stem, sep, caption = line.partition(":")
        stem, caption = stem.strip(), caption.strip()
        if not sep or not caption:
            raise ComposeError(f"{path}:{n}: expected `<capture stem>: <caption>`")
        if stem not in stems:
            raise ComposeError(f"{path}:{n}: no raw capture named {stem}.png")
        if stem in captions:
            raise ComposeError(f"{path}:{n}: a second caption for {stem}")
        captions[stem] = caption
    missing = [s for s in stems if s not in captions]
    if missing:
        raise ComposeError(f"{path}: no caption for {', '.join(missing)}")
    return captions


def find_font(override: str | None = None) -> Path:
    if override:
        path = Path(override).expanduser()
        if not path.is_file():
            raise ComposeError(f"--font {override}: no such file")
        return path
    flutter = shutil.which("flutter")
    if flutter:
        fonts = Path(os.path.realpath(flutter)).parent / "cache" / "artifacts" / "material_fonts"
        if (fonts / FONT_NAME).is_file():
            return fonts / FONT_NAME
    for d in ("/usr/share/fonts", "~/.local/share/fonts"):
        base = Path(d).expanduser()
        hit = next(base.rglob(FONT_NAME), None) if base.is_dir() else None
        if hit:
            return hit
    raise ComposeError(f"{FONT_NAME} not found in the Flutter SDK's material_fonts; pass --font")


def wrap(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for token in text.split(" "):
        candidate = f"{current} {token}" if current else token
        if font.getlength(candidate) <= max_width or not current:
            current = candidate
        else:
            lines.append(current)
            current = token
    if current:
        lines.append(current)
    return lines


def balance(lines: list[str], text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    """Where to break two lines: after a clause if one fits, else at the most even split."""
    if len(lines) != 2:
        return lines
    tokens = text.split(" ")
    best, best_width, best_clause = lines, max(font.getlength(line) for line in lines), False
    for i in range(1, len(tokens)):
        a, b = " ".join(tokens[:i]), " ".join(tokens[i:])
        width = max(font.getlength(a), font.getlength(b))
        if width > max_width:
            continue
        clause = a.rstrip().endswith(CLAUSE_END)
        if (clause and not best_clause) or (clause == best_clause and width < best_width):
            best, best_width, best_clause = [a, b], width, clause
    return best


def fit_caption(text: str, font_path: Path) -> tuple[ImageFont.FreeTypeFont, list[str]]:
    max_width = WIDTH - 2 * SIDE_MARGIN
    forced = [part.strip() for part in text.split(BREAK)] if BREAK in text else None
    for size in range(MAX_FONT_SIZE, MIN_FONT_SIZE - 1, -2):
        font = ImageFont.truetype(str(font_path), size)
        if forced:
            if len(forced) <= MAX_LINES and all(font.getlength(p) <= max_width for p in forced):
                return font, forced
            continue
        lines = wrap(text, font, max_width)
        if len(lines) <= MAX_LINES and all(font.getlength(line) <= max_width for line in lines):
            return font, balance(lines, text, font, max_width)
    raise ComposeError(f"caption too long for {MAX_LINES} lines at {MIN_FONT_SIZE}px: {text!r}")


def gradient() -> Image.Image:
    column = Image.new("RGB", (1, HEIGHT))
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        column.putpixel(
            (0, y), tuple(round(a + (b - a) * t) for a, b in zip(BACKGROUND, BACKGROUND_BOTTOM))
        )
    return column.resize((WIDTH, HEIGHT))


def compose(raw: Image.Image, caption: str, font_path: Path) -> Image.Image:
    """One 1080x1920 opaque RGB store screenshot."""
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)

    font, lines = fit_caption(caption, font_path)
    line_height = round(font.size * LINE_SPACING)
    y = (BAND_HEIGHT - line_height * len(lines)) // 2 + round(font.size * 0.1)
    for line in lines:
        draw.text((WIDTH // 2, y + line_height // 2), line, font=font, fill=AMBER_400, anchor="mm")
        y += line_height

    screen = raw.convert("RGB")
    avail_h = HEIGHT - BAND_HEIGHT - BOTTOM_MARGIN
    scale = min(avail_h / screen.height, (WIDTH - 2 * SIDE_MARGIN) / screen.width)
    size = (round(screen.width * scale), round(screen.height * scale))
    screen = screen.resize(size, Image.LANCZOS)
    x, top = (WIDTH - size[0]) // 2, BAND_HEIGHT

    shadow = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, top + 12, x + size[0], top + size[1] + 12), SCREEN_RADIUS, fill=150
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas = Image.composite(Image.new("RGB", (WIDTH, HEIGHT), SHADOW), canvas, shadow)

    # A hairline of the outline colour around the screen, so its dark edge reads.
    ImageDraw.Draw(canvas).rounded_rectangle(
        (x - 3, top - 3, x + size[0] + 2, top + size[1] + 2), SCREEN_RADIUS + 3, fill=FRAME
    )
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), SCREEN_RADIUS, fill=255)
    canvas.paste(screen, (x, top), mask)
    return canvas


def check_image(path: Path) -> str | None:
    with Image.open(path) as im:
        if im.size != (WIDTH, HEIGHT):
            return f"{path}: {im.size[0]}x{im.size[1]}, expected {WIDTH}x{HEIGHT}"
        if im.mode != "RGB":
            return f"{path}: mode {im.mode}, expected RGB (no alpha)"
    return None


def compose_locale(root: Path, raw_root: Path, locale: str, font: str | None) -> list[Path]:
    shots = sorted((raw_root / locale).glob("*.png"))
    if not shots:
        raise ComposeError(f"{locale}: no raw capture in {raw_root / locale}")
    captions = read_captions(root / LISTING_ROOT / locale / CAPTIONS_FILE, [s.stem for s in shots])
    font_path = find_font(font)
    out_dir = root / LISTING_ROOT / locale / OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for shot in shots:
        with Image.open(shot) as raw:
            image = compose(raw, captions[shot.stem], font_path)
        target = out_dir / shot.name
        image.save(target, "PNG", optimize=True)
        written.append(target)
    for stale in sorted(set(out_dir.glob("*.png")) - set(written)):
        stale.unlink()
        print(f"{locale}: removed {stale.relative_to(root)} (no raw capture)")
    print(f"{locale}: {len(written)} screenshots -> {out_dir.relative_to(root)} ({font_path.name})")
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--raw", type=Path, help="the raw captures, <raw>/<locale>/<stem>.png")
    parser.add_argument("--locale", action="append", help="a store locale (repeatable)")
    parser.add_argument("--font", help="a font file instead of Roboto Bold")
    parser.add_argument("--check", action="store_true", help="verify the composed sets only")
    args = parser.parse_args(argv)
    root = repo_root()
    try:
        known = listing_locales(root)
        locales = args.locale or known
        unknown = [loc for loc in locales if loc not in known]
        if unknown:
            raise ComposeError(f"not a store locale: {', '.join(unknown)} (known: {', '.join(known)})")
        if args.check:
            problems = []
            for locale in locales:
                shots = sorted((root / LISTING_ROOT / locale / OUT_DIR).glob("*.png"))
                if not 2 <= len(shots) <= 8:
                    problems.append(f"{locale}: {len(shots)} screenshots, Play takes 2 to 8")
                problems += [p for p in map(check_image, shots) if p]
            for p in problems:
                print(p, file=sys.stderr)
            print(f"check: {len(locales)} locale(s), {len(problems)} problem(s)")
            return 1 if problems else 0
        if not args.raw:
            raise ComposeError("--raw <dir> is required to compose")
        for locale in locales:
            compose_locale(root, args.raw, locale, args.font)
    except ComposeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
