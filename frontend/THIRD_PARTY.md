# Third-party assets

## Card faces — `public/elements.cardmeister.full.js`

The `cardmeister` web component by **Danny Engelman** (<https://cardmeister.github.io/>,
source <https://github.com/cardmeister/cardmeister.github.io>), vendored as a minified script;
it draws the 52 faces and the card back.

Licence: **The Unlicense** (public-domain dedication), <https://unlicense.org/>. The upstream
`README.md` states "**License:** Unlicense: This is free software released into the public
domain" and ends with the full Unlicense text; its `package.json` says `"license": "CC0"`,
another public-domain dedication. Neither asks for a notice, so none is shipped next to the
script. The court-card artwork derives from Adrian Kennard's CC0 card generator
(<https://www.me.uk/cards/>), as the upstream README records.

Version: byte-identical to upstream `elements.cardmeister.full.js` at commit
[`e2d53d14`](https://github.com/cardmeister/cardmeister.github.io/blob/e2d53d14db49b391215650cdb124a20065662c67/elements.cardmeister.full.js)
(2025-04-17; git blob `0803debd`); upstream carries no release tags and `package.json` says
`1.0.0`. Upstream has changed the file since (latest checked: `0ce99ba7`, 2026-04-12). There
is no npm package. The repository has no `LICENSE` file, so GitHub's API reports `license: null`;
the statements above are the evidence. Checked 2026-09-27.

## Jokers — `public/joker-red.svg`, `public/joker-black.svg`

"Joker red 02" and "Joker black 02" by **David Bellot**, from SVG-cards
(<http://svg-cards.sourceforge.net/>), via Wikimedia Commons:
<https://commons.wikimedia.org/wiki/File:Joker_red_02.svg> and
<https://commons.wikimedia.org/wiki/File:Joker_black_02.svg>.

Copyright (C) 2004 David Bellot. Licence: **GNU Lesser General Public License**, version 2.1
or (at your option) any later version, <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>.

Byte-identical to the Flutter client's `frontend-flutter/assets/cards/joker_red.svg` and
`joker_black.svg`: reframed into a 360 × 540 card, flattened and optimised with `svgo`. What
was changed, and how, is written down in `frontend-flutter/THIRD_PARTY.md`.
