# FlutterGameUi

> Scope: what the Flutter board shows each turn (step, named button, hand value, suggestions,
> ZapZap, felt, pile and deck, opponents), board motion and reduced motion, and the card
> model, play rules and card widgets.
> Related: [[FrontendFlutter]] · [[FlutterGameBoard]] · [[GameRules]]
> Updated: 2026-09-29

## Facts

### The turn reads itself (J1–J6, T1, T2 of the UX study, 2026-09-23)

In the existing look (`utils/app_theme.dart`); the strings use "tu", as the study's
mockups do. `test/game_turn_ux_test.dart` proves each item, one group per item.

- **The step indicator** (J1, `GameActionButtons`, `TurnStepChip`): on the player's turn
  two chips, ① Jouer → ② Piocher (`GAME_RULES.md`, Turn Flow), the current one amber, the
  other grey — checked (✓ Jouer) once played. Another player's turn shows "En attente de
  X" (`Key('turnBanner')`) instead.
- **One button that names the move** (J2): full width, keyed `play-cards` in the play step
  and `draw-card` in the draw step. It reads "Jouer 7♥", "Jouer la paire de 7", "Jouer le
  groupe de 7 (3 cartes)", "Jouer la suite (3 cartes)" (`CardL10n.playMoveLabel`, from
  `analyzePlay`), plain "Jouer" when nothing or a refused play is selected, then
  "Piocher" or "Prendre 7♥" (`cardShort`: the rank and `Suit.symbol`), amber in both steps —
  the step chips say which step it is. The refusal reason
  stays, under it.
- **The hand value in plain words** (J3, `GameHand`): "Ta main · 29 pts" — jokers at 0,
  what ZapZap is decided on —, a gauge towards "ZapZap à 5" (`zapZapProgress`: 5 / value,
  full at 5 or under), and "En fin de manche : n pts (joker 25)" only when the hand holds a
  joker (`hasJoker`) — a joker counts 25 at the end of the round for anyone without the
  lowest hand, counteracted or not (`GAME_RULES.md`), so the label does not tie it to a
  counteract.
- **Suggested plays** (J8, `HandSuggestions` in `lib/widgets/hand_suggestions.dart`,
  2026-09-24): above the cards in the play step, up to three chips — "Paire de 7 · −14",
  "Q♠ seule · −12", "Suite 4–6♥ avec joker · −10" (`CardL10n.suggestionLabel`) — the
  points each takes off the hand, jokers at 0. `suggestPlays` (`utils/rules.dart`) finds
  each rank held twice or more, the best run of each suit with the fewest jokers that fill
  its gaps (a joker ends a run of two, above it), and the single cards in neither; a joker
  alone or with one card is not offered. Each suggestion passes `isValidPlay`, the check
  the selection gets. A tap calls `GameProvider.selectCards`, which replaces the selection;
  it stays editable card by card, and the chip whose cards are exactly the selection is
  amber. The chips are one line that scrolls sideways, not a wrap, so the hand keeps its
  height on a phone; a label wider than the line wraps inside its chip. Hidden when the
  hand cannot be played (`GameHand.disabled`) and in the compact draw-step hand.
- **Motion that explains** (J9, `lib/utils/motion.dart`, 2026-09-25): a card that comes
  onto the felt glides in (`GameTableArea`, `Motion.glide` 350 ms, `easeOutCubic`, fading in
  over the first half) from 1.5 card heights away (`GameTableArea.glideDistance`) — up from
  the hand when the last move was this player's (`playedByMe`, `lastAction.playerIndex ==
  myPlayerIndex`), down from the players otherwise, so a bot that played and drew between
  two refreshes still shows its cards arriving on the pile. "Comes onto" is the set
  `cardsPlayed ∪ lastCardsPlayed` against the previous build, and the first table drawn
  does not glide. **Cards moving on the felt** (2026-09-27): at the next play the cards
  under "Posées" become the pile ("À prendre ensuite", the backend moves `cards_played` to
  `last_cards_played`, `zapzap-rust/src/domain/services/game_service.rs`), and they slide
  from the one row to the other in 300 ms (`Motion.shift`, `easeInOutCubic`), taking the
  pile's card size (`GameTableArea.slideKey`); the rest of the old pile, gone to the
  discard, fades out where it lay (`Motion.leave` 350 ms, `GameTableArea.leavingKey`). A
  card a draw took from the pile (`lastAction.source == 'played'`, `cardId`) moves on
  1.5 card heights toward its taker — down to the hand for this player, up to the players
  otherwise, as the glide — fading out over its last 60 %; a deck draw sends a card back
  off the deck the same way (`GameTableArea.deckLeavingKey`), once per action (type,
  player, timestamp). Only a `play` or a `draw` moves cards so: a new round lays a new
  table. Each card and the deck's top card sit in a `_FeltSlot`, a render box that keeps
  itself in a map by card id; `didUpdateWidget` reads where each lay before the new felt
  is laid out, the slide is worked out at paint time from where the card lies now (its
  `applyPaintTransform` follows it, so `getRect` sees the card mid-way), and the cards
  leaving are images in the felt's `Stack` (`Clip.none`: they go past the rim).
  The card a draw brings into the hand — exactly one card more, none gone; a deal, a play or
  a reorder is not a draw — carries a "Nouveau" badge (`gameCardNew`,
  `CardFan.freshBadgeKey`) for 2 s (`Motion.freshCard`), painted above every card of the
  fan at the card's top-left, popping in over 200 ms. `CardFan` is stateful for it and
  keyed in `GameHand` (`Key('handFan')`): the lines around it come and go at the draw. A
  selected card rises in 150 ms (`Motion.lift`, `AnimatedPositioned`) and takes its edge in
  200 ms (`Motion.select`). **Under `MediaQuery.disableAnimations` every one of these is
  off**: durations are zero, nothing glides, slides or leaves, and the badge is drawn still — it is
  information, so it stays its 2 s. The end of a round's climbing totals (F5, [[FlutterGameBoard]]) did
  so already. Material's own transitions (ink, route) are not the board's and are left as
  the framework draws them. `test/game_motion_test.dart` checks the badge and its 2 s, the
  glide from below and from above, the slide from "Posées" to the pile (at the start, mid-way
  and landed), the rest of the pile fading in place, the card taken from the pile leaving
  down (this player) or up (another), the card back off the deck once per draw, and, under
  reduced motion, that none of these runs (no frame scheduled) and that the board settles in
  one pump after a play and a draw (`pumpAndSettle()` returns 1), with no glide and a still
  badge. Checked in the PWA (2026-09-25, headless Chromium at 390x844 against the local Rust
  backend, a CDP screencast): a Q♣ played rises semi-transparent from the hand's side onto
  the "Played" row ~350 ms after the move, and the drawn 10♦ carries "New" (the page was
  in English) until 2 s later. The felt's moves checked the same way (2026-09-27, 390x844,
  the PWA as Vincent against the local Rust backend with Thibaut driven through the API and
  MediumBot1, a CDP screencast): at the next player's play the 9♥ under "Posées" slides
  down-left onto "À prendre ensuite" over ~300 ms, the new card gliding in from above; the
  K♠ Vincent took from the pile moves down toward the hand and fades; the 9♥ the bot took
  rises toward the players and fades; a card back leaves the deck upward when Thibaut
  draws.
- **ZapZap with its risk** (J4): always shown; disabled, it says why — "main 29, il faut 5
  ou moins", or "au début de ton tour" outside the player's play step. A tap opens a
  bottom sheet (`widgets/game_zapzap_sheet.dart`, `confirmZapZap`) that states the
  counteract: the hand at 25 per joker + `counteractPenalty(activePlayers)` =
  (active players − 1) × 5 (`utils/rules.dart`), active players being those not in
  `eliminatedPlayers` (`GameProvider.activePlayerCount`), and in Golden Score that being
  counteracted loses the game. `ZapZapRisk.eligible` is the provider's `zapZapEligible`, so
  the button's reason and its enabled state come from one source. Only Confirm posts `/zapzap`; Cancel or a dismissal posts
  nothing.
- **The casino felt** (`GameTableArea`, `lib/widgets/felt_painter.dart`, 2026-09-24): a
  6 px dark wood rim (`Key('feltRim')`, `GameTableArea.rimWidth`, a linear gradient
  `rimLight` → `rimDark` and a drop shadow) around the felt (`Key('gameTable')`): a
  `RadialGradient` `feltCenter` → `feltEdge`, lit at the centre and dark at the edges, and
  under the cards a `FeltPainter` — short fibres from a fixed seed (the same felt on every
  frame), the ZapZap bolt and name as a faint watermark, the rim's shadow blurred along the
  inside of the edge. No image asset. The texture paints *inside* the felt's border, so the
  edge — a 1 px `rimInlay` line, amber and 2 px in the draw step — lies on the rim's inner
  lip, over everything; in the draw step the rim also glows amber. The content sits behind a
  `RepaintBoundary`, so a scroll of the felt does not repaint the texture. The rim takes
  6 px a side the plain felt did not: the felt's padding went from 8 to 6 × 4
  (`GameTableArea.feltPadding`) and two 4 px gaps to 2, so the draw step still fits
  390x844 at text scale 1.5. `test/game_felt_test.dart`.
- **The discard pile and the deck** (J5, `GameTableArea.step`, `TableStep`): the pile is
  labelled "À prendre ensuite" and shown plain, as the deck is, while the player plays; in the
  draw step the felt takes an amber edge, says "Touche une carte pour la prendre, ou la
  pioche", the pile's cards and the deck take a playable card's light edge, the card the draw will take (`takeCard`, the one the button names —
  never a pick the pile no longer holds) adds "Prendre 7♥ ajoute 7 points à ta main", or for
  a joker "0 point pour ZapZap, mais 25 en fin de manche si ta main n'est pas la plus
  basse", and the deck (`Key('draw-deck')`, moved from the hand onto the felt) is a target
  of its own — `GameProvider.draw(fromDeck: true)` draws from the deck even with a discard
  card picked, and keeps that pick if the draw is refused. The deck is a `CardBack` as wide
  as the pile's cards (`cardWidth`), labelled "Pioche N" above it in the pile label's style,
  both labels and both top cards in line (the `Wrap` aligns its runs' tops); under it, the
  edges of two cards offset 2 px right and down (`CardSizes.deckLayerStep`) — one at 10
  cards or fewer, none at 1 —, inside the deck's own box (`test/game_felt_test.dart`).
- **The card taken from the discard pile** (`GameTableArea`, `lastAction` `draw` with
  `source: 'played'` and a `cardId`): it lay face up for everyone, so the message names it
  — "Alice a pris dans la défausse : 7 de Cœur" (`gameActionTookDiscardCard`, `cardName`)
  — and a 24 px `PlayingCard` (`Key('tableMessageCard')`,
  `GameTableArea.takenCardWidth`) follows it. A deck draw never names its card, even when
  the server were to send one (the Node backend did; Rust does not, and sends `cardId` for a
  discard take — `test_state_last_action_of_select_play_and_draw` in
  `zapzap-rust/tests/api_tests.rs`); a discard take without `cardId` keeps "a pris une carte
  de la défausse". `test/game_table_message_test.dart`.
- **The hand-size choice** (T1, T2, `GameHandSizeSelector`): 58 × 50 buttons (≥ 48 dp)
  instead of chips, a line on what the choice changes ("Moins de cartes, ZapZap plus
  vite ; plus de cartes, plus de combinaisons"), and "Distribuer N cartes". T3: it sits
  under the players and their scores instead of replacing the board, since who is close
  to 100 is what the choice is made on.
- **Compact opponents** (J6, `GamePlayerTable`): one line per player in turn order from the
  round's starting player (`orderedPlayers`), each a small card back and the count
  instead of a row of backs, a bar of the total towards 100 (red above 80, full once out)
  and the total; the player to move on an amber edge, and their turn's countdown when the
  game runs a clock (`TurnCountdown`, [[FlutterGameBoard]] § The turn clock). Every line has the same height
  (`GamePlayerTable.rowHeight`, from the text scale), whatever it holds — a "Toi" badge,
  a card back, a countdown or "Éliminé".
- **The folded table** (`GamePlayerTable.onToggle`): on the phone board the table shows
  one line, the player to move's (the first in turn order when nobody is,
  `GamePlayerTable.foldedSeat`), and a chevron at its end (`toggleKey`, labelled "Voir tous
  les joueurs" / "Ne montrer que le joueur qui joue") unfolds every line and folds them
  back. The folded line follows the turn. `GameScreen` holds the choice
  (`_playersExpanded`, folded at the start) for as long as the game is open. The height
  the other lines free goes to the felt: `PhoneBoardLayout` gives the felt whatever the
  players leave, so it needed no change. At 5–8 players a line each took the phone's
  felt height (2026-09-24). The wide board, where the players sit beside the felt, and the
  hand-size choice, made on the scores (T3), keep every line.
  `test/game_player_table_test.dart` checks the fold, the turn, the labels in fr and en,
  and at 390x844 a folded table one line tall with the felt right under it, two lines
  taller than unfolded.

### Cards and play rules

- Ids as the backend's (`GameRules`): 0-51 = suit `id ~/ 13` (spades, hearts, clubs,
  diamonds) × rank `id % 13 + 1` (Ace 1 .. King 13); 52 red joker, 53 black joker
  (`lib/models/card.dart`). Value = rank; joker 0, or 25 with `penalty: true`.
- `analyzePlay(List<int>)` (`lib/utils/rules.dart`), ported from the removed React client's
  `utils/validation.js` and checked against `GAME_RULES.md`: a single card; a
  same-rank group ≥ 2, jokers wild, all-joker groups valid (as the backend); a one-suit
  sequence ≥ 3, jokers filling gaps or extending an end, Ace low only, no K-A wrap, at most
  13 cards. It returns a `PlayType` and, when refused, a `PlayError` code that the UI turns
  into text with `playErrorMessage` — no message in `rules.dart`.
- **A repeated id** (`[c, c]`) is refused (`PlayError.duplicateCard`), as the Rust backend
  refuses it since 2026-09-24 ([[GameRules]]); the React client accepted it.
- `isZapZapEligible`: hand ≤ 5 with jokers 0. Final scoring is not ported (the backend
  computes it); `counteractPenalty(activePlayers)` is, only to warn before a call (above).
- Widgets: `PlayingCard` (height = width × 1.4, radius 5 % of width ≥ 2; a face always
  keeps its colours — no `ColorFiltered`, no `Opacity`: the grey of 2026-09 turned most of the
  table grey, and a half-transparent card let the felt show through. What can be done with
  a card shows on its edge, drawn in front of the face, in three looks (`CardLook`,
  `PlayingCard.look`, `edgeFor`, `shadowFor`): plain — cannot be played, a drop shadow;
  playable — takes a tap, a 1.5 px `amber200` edge and a soft glow; selected — a 3 px
  `amber400` edge and a strong glow. Under the mouse, a card that takes a tap shows the
  click cursor and glows as a selected one, its edge unchanged (`_PointerTarget`,
  2026-09-29). No tap when disabled; a localised semantics label
  whose `onTap` is the card's tap — none when disabled, so a screen reader selects a card
  as a finger does);
  `CardBack` (sizes `xxs` 16 … `lg` 80 px, as `CardBack.jsx`, or any `width`; a painted red
  lattice, no asset); `CardFan` (the hand — no longer the arc of `CardFan.jsx`: cards a quarter of the
  width wide, 76 to 96 px, overlapping left to right with a step of ¾ of a card, never
  less than 48 px of each left visible; a hand that cannot keep 48 px on one row goes onto
  balanced rows — 7 cards at 360 px are 4 + 3 —, each row drawn over the lower half of the
  one above; a row bows 4 px down at its ends; a selected card rises 20 px (in 150 ms,
  at once under reduced motion) and keeps its place in the paint order, so its neighbours stay as easy to tap; `CardFan.layoutFor(n,
  width)` gives each card's rect and its visible part; `CardFan.itemKey(i)`; `compact`, the
  hand in the draw step on a phone: one straight row of opaque cards at most 48 px wide, no
  lift; the card a draw brings in is badged "Nouveau" for 2 s, J9 above). The sizes are
  tokens, `CardSizes` in `utils/app_theme.dart`: hand 76–96, 48 visible, compact 48, the
  felt's cards 70 px on a phone and 84 on a wide board (the deck too), the
  cards played this turn 49 on a phone in the draw step, lift 20, edges 1.5 (playable) and
  3 (selected), the deck's layers 2.
- Faces: `frontend-flutter/assets/cards/<rank>_of_<suit>.svg` — the CC0 "English pattern"
  deck by Dmitry Fomin (Wikimedia Commons) — and `joker_red.svg` / `joker_black.svg`, David
  Bellot's LGPL SVG-cards jokers reframed into the faces' `0 0 360 540` frame (same outline,
  same scale for both, no `<use>`, `<text>` or `<style>`); rendered with `flutter_svg`,
  stretched into the width × 1.4 box (`BoxFit.fill`). Licence and the changes made: `frontend-flutter/THIRD_PARTY.md`. The 54 files
  weigh 1.32 MB after `svgo` (the jokers 31.6 and 24.5 KB); the twelve court cards are
  1.15 MB of it. `test/card_widgets_test.dart` pins the jokers' frame and pumps them beside a
  face at 38 and 80 px.

## Decisions & History

- **The game felt is a casino table (2026-09-24, `feat/flutter-casino-felt`).** Next to
  the enlarged cards the plain green gradient looked dull. Painted rather than an image:
  no asset to ship in the PWA and the APK, and the felt scales to any size. The amber edge
  of the draw step stays the felt's own border, drawn over the texture and against the dark
  rim, rather than moving onto the rim: the tests that prove the edge is never cut keep
  their meaning. The padding given back keeps the draw step whole at 390x844, text x1.5.
- **The turn reads itself (2026-09-23, `feat/flutter-turn-ux`).** The UX study found three
  buttons of equal weight lighting up in turn, a hand header of two numbers of which one
  counts, a ZapZap that went off without a word of its risk, and rows of card backs that
  had to be counted. One named primary button per step rather than three: the step
  indicator says which step it is, so the button can say what it does. The deck moved from
  the hand to the felt, beside the pile, so the draw step has one place to look. The new
  strings say "tu", as the mockups the user approved; the rest of the app still says
  "vous" until the whole app moved to "tu" the same day (the entry in [[FlutterI18n]]). `gameHandValues`, `gameZapZapEligible`, `gameTurnPlay`,
  `gameTurnDraw`, `gamePlayButton`, `gamePlayButtonCount`, `gameTakeButton`,
  `gameTableDiscardLabel` and `gameSeatCards` lost their callers and were dropped. Absorbed:
  the player-list entry of 2026-09-22 (one equal-height line per player, turn order from
  the round's first player).
- **Card faces from SVG assets (2026-09-22).** React draws faces with the `cardmeister` web
  component, which Flutter cannot use; the CC0 English-pattern deck was picked over drawing
  faces in code. `analyzePlay` returns codes, not React's English `reason` strings, so the
  UI localises them.
- **Bellot jokers (2026-09-23, `feat/joker-artwork`).** The home-made 80 × 112 clown
  jokers clashed with the English-pattern faces; the user picked David Bellot's Wikimedia
  jokers. They are bundled, never hot-linked, so the PWA works offline; the red original's
  `<use>` references are inlined because `flutter_svg` support for them is the part least
  worth betting on. At 38 px the "JOKER" index is unreadable, as the faces' indices are, but
  the red jester silhouette tells a joker from any face.
- **Bigger cards, and the game's exits replace their browser entry (2026-09-24,
  `feat/flutter-bigger-cards`).** At 360x740 the hand's cards were 50 px wide and each
  showed 18 px to the next one: a tap hit the neighbour, and the ranks were hard to read;
  the felt's were 45 px. The user asked for cards larger than the first proposal (64–72
  px): the hand's are now 76–96 px (82 at 360x740), the felt's 70/84. The arc went: with
  rotated cards the part a finger can reach is a skewed sliver, and at these sizes seven
  cards do not fit in one arc on a phone — two flat, overlapping rows keep 48 px of every
  card reachable, which a test taps. A selected card stays in the paint order rather than
  on top, as React draws it: on top, it covered 32 of the 48 px of the next card. The felt
  now fills the height between players and hand, so the ~100 px empty band under it went
  and its cards got the room; in the draw step the hand yields to it (3/20) and the
  duplicate "X a posé N cartes" line is dropped, which keeps the whole draw step in view
  at 360x740 and 390x844 at 1.0. The game's exits called `leaveFor`, `popOrGo` under
  `Router.neglect` (since folded into `popOrGo`): `popOrGo` alone would still have pushed a
  browser entry — checked by the reported route information, which a
  pop sends with `replace: false`. Before/after renders at 360x740 are described in the
  pull request.
- **Board motion goes through one switch (2026-09-25, feat/flutter-play-motion).** Every
  animation of the board reads its duration from `Motion.of`, so reduced motion is one
  test away rather than a check per widget; only `game_round_end.dart` read
  `disableAnimations` before. The glide is a slide into place on the felt, not a flight
  from the card's spot in the hand: the hand and the felt are separate sections and the
  move lands through a refetch, so a flight would need the hand's rects kept across two
  states and an overlay; the direction (from below for this player, from above for the
  others) carries the same meaning for far less. The drawn card is found by diffing the
  hand, not from the draw's answer: the table others' events bring is the same path, and a
  deck draw's `cardDrawn` is not otherwise used. The badge stays under reduced motion,
  drawn still — it says which card is new, which a player who turned animations off needs
  as much.
- **Cards that stay on the felt slide; cards that leave it go toward their taker
  (2026-09-27, feat/flutter-card-animations).** The Posées → À prendre ensuite move had
  been left still, and a card taken vanished, so a player did not see which cards became
  takeable nor who took what. The slide goes further than the glide's reasoning above only
  where it costs nothing new: both rows are in the one felt widget, so the card's rect
  before the refresh is kept by the felt itself (a render box per card, read in
  `didUpdateWidget` before relayout) and the slide is worked out at paint time — no state
  kept across sections, no `Overlay`. A card leaving for a hand still does not fly to that
  hand or seat: that would need the rects of another section; it moves toward it, down for
  this player and up for the others, as the glide comes from there, and fades. The deal at
  a round start is left for a later entry.
