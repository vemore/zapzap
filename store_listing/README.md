# ZapZap — Google Play store listing

The committed source of truth for what the Play Store page of `com.zapzap.app` shows, in
French (`fr-FR`, the default language) and English (`en-US`). Ported from countscore's
`store_listing/`. A field edited in the Play Console and not here is lost the next time these
files are uploaded.

## Layout

```
store_listing/
├── <play-locale>/                  # fr-FR, en-US
│   ├── title.txt                   # the app name on the store, 30 characters max
│   ├── short_description.txt       # 80 characters max
│   ├── full_description.txt        # 4000 characters max, plain text
│   ├── screenshot_captions.txt     # one caption per capture, `<stem>: <caption>`, `|` breaks the line
│   ├── screenshots/phone/          # 01_login … 07_stats, 1080×1920 RGB (generated, committed)
│   └── feature_graphic.png         # optional: this locale's own, instead of assets/'s
├── assets/
│   ├── icon_512.png                # 512×512 RGBA, from frontend-flutter/assets/icon/icon.svg
│   └── feature_graphic.png         # 1024×500 RGB, every locale's (no text but the name)
└── README.md                       # this file
```

The texts carry no final newline. The French speaks to the player with "tu", as the app does
([`.llmwiki/FrontendFlutter.md`](../.llmwiki/FrontendFlutter.md) § Localisation), and says
nothing the app does not do: rules from [`GAME_RULES.md`](../GAME_RULES.md), features from the
Flutter client.

## Play's limits, and what checks them

| What | Limit | Checked by |
|---|---|---|
| Title | 30 characters | `frontend-flutter/test/store_listing_test.dart` |
| Short description | 80 characters | same |
| Full description | 4000 characters, plain text | same (no HTML, no Markdown) |
| Phone screenshots | 2 to 8 per locale; PNG or JPEG; each side 320–3840 px; 16:9 or 9:16; no alpha | same (9:16 exactly, 1080×1920 here) |
| Icon | 512×512, 32-bit PNG (alpha allowed), ≤ 1 MB | same (the size and the alpha; the weight, 8 KB, by eye) |
| Feature graphic | 1024×500, PNG or JPEG, no alpha | same |

Characters are counted as Unicode code points. The test runs in `flutter test` and in the
CI `flutter` job, which `scripts/ci_scope.sh` selects for any change here.

## Regenerate

From the repository root. None of it runs in CI; commit what it writes.

**The icon and the feature graphic** — `rsvg-convert` (`librsvg2-bin`) and the Flutter SDK
(for Roboto) needed:

```bash
uv run --script scripts/generate_store_graphics.py          # both PNGs
uv run --script scripts/generate_store_graphics.py --check  # sizes and modes only
```

The feature graphic draws the icon, the name, and a 5-point hand (ace, two, two, joker —
a ZapZap) from `frontend-flutter/assets/cards/` on the board's felt, in the colours of
`frontend-flutter/lib/utils/app_theme.dart`.

**The phone screenshots** — the Rust backend built (`cd zapzap-rust && cargo build
--locked`), `flutter`, Node with the root `package.json`'s Playwright (or the main
checkout's `node_modules`), and `uv`:

```bash
scripts/capture_store_screenshots.sh              # fr-FR and en-US
scripts/capture_store_screenshots.sh en-US        # one locale
```

For each locale it seeds a throwaway database (`zapzap-backend seed --demo`: the bots and the
fictional demo users, password `demo123`), starts the backend on `:9971` (never production),
builds the Flutter web client against it and serves it under `/app/` on `:8871`, plays two
games and part of a third through the API, and screenshots seven screens in headless
Chromium at a 390×844 phone viewport, 3 device pixels, with the browser in the locale's
language. `scripts/compose_store_screenshots.py` then sets each capture under its caption,
on the app's slate, into `<locale>/screenshots/phone/`. The deal is random: each run shows
other cards and scores. `STORE_API_PORT`, `STORE_WEB_PORT`, `STORE_WEB_BUILD` (reuse a web
build) and `STORE_RAW_DIR` (keep the raw captures) are in the script's header.

The web build has no Google client id, so the login screen shows no Google button (the
Android app and production do).

A changed caption only needs the composer, over raw captures kept with `STORE_RAW_DIR`:
`uv run --script scripts/compose_store_screenshots.py --raw <dir>`.

## Upload

This is the layout `scripts/play_publish.py` (the `chore/release-android` pull request)
reads: the three texts, `screenshots/phone/*.png` (8 at most), and the feature graphic of the
locale, else `assets/feature_graphic.png`. By hand, the Play Console's Store presence › Main
store listing takes the same files, per language.
