# Third-party assets

## Card faces — `assets/cards/<rank>_of_<suit>.svg` (52 files)

"English pattern" playing cards by **Dmitry Fomin**, from Wikimedia Commons
(<https://commons.wikimedia.org/wiki/Category:SVG_English_pattern_playing_cards>), e.g.
<https://commons.wikimedia.org/wiki/File:English_pattern_ace_of_spades.svg>.

Licence: **CC0 1.0 Universal** (public domain dedication),
<https://creativecommons.org/publicdomain/zero/1.0/>. No attribution is required; it is
given here as a courtesy.

Downloaded 2026-09-22 (byte sizes checked against Commons), renamed from
`English_pattern_<rank>_of_<suit>.svg` to `<rank>_of_<suit>.svg`, and optimised with
`npx svgo@3` (default preset: Inkscape metadata dropped, paths rounded; 2.3 MB → 1.2 MB).
Rendered side by side with `rsvg-convert`, the optimised faces differ from the originals by
under 0.4 % of pixels, all on anti-aliased edges.

## Jokers — `assets/cards/joker_red.svg`, `joker_black.svg`

"Joker red 02" and "Joker black 02" by **David Bellot**, from SVG-cards
(<http://svg-cards.sourceforge.net/>), via Wikimedia Commons:
<https://commons.wikimedia.org/wiki/File:Joker_red_02.svg> and
<https://commons.wikimedia.org/wiki/File:Joker_black_02.svg>.

Copyright (C) 2004 David Bellot. Licence: **GNU Lesser General Public License**, version 2.1
or (at your option) any later version, <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>.
The SVG files here are the modified work in its source form; the originals are at the
Commons URLs above.

Downloaded 2026-09-23 (61 589 and 29 523 bytes) and modified:

- **Reframed** into the faces' frame: the originals' own 167 × 243 outline is removed, the
  artwork is scaled by 2.1 and centred in a `viewBox="0 0 360 540"` drawn with the faces'
  card outline (white rounded rectangle, `rx` 29.944, black 1 px stroke). Red and black get
  the same frame and the same scale. `preserveAspectRatio="none"` makes a browser `<img>`
  stretch it into the card box as `flutter_svg`'s `BoxFit.fill` does.
- **Flattened** for `flutter_svg`: the red original's `<use>` references (the jester and the
  four suit marks) are replaced by copies of what they point to, and three `<use>` bound to a
  mistyped xlink namespace, which render nothing, are dropped; Inkscape and Illustrator
  metadata and comments are removed.
- **Optimised** with `npx svgo@3` (default preset, `removeViewBox` off, `floatPrecision` 2):
  red 61 589 → 31 565 bytes, black 29 523 → 24 510 bytes. Rendered with `rsvg-convert`
  at 720 px wide, the result differs from the reframed-but-unoptimised file on under
  0.02 % of pixels.

Nothing else is changed: colours, drawing and the "JOKER" indices are the originals'. The
same two files are shipped by the React client as `frontend/public/joker-red.svg` and
`joker-black.svg` (`frontend/THIRD_PARTY.md`).
