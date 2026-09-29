# FlutterGameBoard

> Scope: the Flutter game board (`GameProvider`, modes, errors, layouts), the end of a round and of
> the game, and the offline example game (`/tutorial`) with its first-opening offer.
> Related: [[FrontendFlutter]] · [[FlutterGameUi]] · [[FlutterParties]] · [[GameRules]] · [[Api]]
> Updated: 2026-09-29

## Facts

### The game board (`screens/game_screen.dart`, `providers/game_provider.dart`, `widgets/game_*.dart`)

Ported from the React client's `components/Game/{GameBoard,PlayerTable,TableArea,PlayerHand,ActionButtons,HandSizeSelector}.jsx`
(removed on 2026-09-29, [[Frontend]]); "React" below names that reference.

- **`GameProvider`**, built and disposed by the screen as the lobby's providers are:
  `GET /game/:id/state`, then the event stream filtered on `partyId` — `play`, `draw`,
  `selectHandSize`, `zapzap`, `roundStarted`, `gameFinished`, `partyStarted` and
  `playerForfeited` (a deleted account's seat, since #132) refetch without a spinner,
  `partyDeleted` sets `outcome` (`GameOutcome.closed`) and the screen goes back to the list.
  `playerReplaced` (the turn clock gave a late human's seat to a bot, § The turn clock)
  refetches too, unless its `replacedUserId` is the signed-in player: then `outcome` is
  `GameOutcome.ejected`, with no refetch — every game route answers them 403 `NOT_IN_PARTY`
  from then on —, and the screen shows « Tu as été retiré de la partie (temps dépassé) »
  (`gameEjectedMessage`, snack bar `gameEjected`, on the app's messenger, so it stays over
  the list) and goes back to the list. A 403 `NOT_IN_PARTY` answering a load or a move once
  a game has been shown (`isStarted`) is that same ejection with its event missed — the
  stream down, the app in the background — and ends the board the same way
  (`_isMissedEjection`, as React's `isNotInParty`); on a first load, or over the "not
  started yet" page, it stays an error. Nothing after an outcome moves the board.
  `partyStarted` is what takes a client that opened `/game/:id` before the owner started
  off the "not started yet" page and onto the table with no reload; that page also has a
  Retry (`Key('retry-game')`) for an event missed while the channel was down. No move's answer
  carries the new table, so every move refetches the state (`GameBoard.jsx` does the same).
  It derives the caller's seat from the user id (`myPlayerIndex`, `isMyTurn`), the card
  counts, the scores, the eliminated players, `orderedPlayers` (turn order from
  `startingPlayer`), the two hand values and `zapZapEligible`.
- **Nothing takes a drawn table away.** Three fields, not one: a refused **move** fills
  `actionError`, which the screen reads once (`consumeActionError`) and shows in a snack
  bar; a **refresh that fails while a table is on screen** fills `refreshError`, and the
  board stays under a banner with a Retry (`Key('gameStaleBanner')`), cleared by the next
  answer; only a **load with nothing to fall back on** fills `error` and draws the error
  page. Text comes from `ApiException.code` through `gameErrorText`
  (`widgets/game_error_text.dart`, `GameErrorCode` in the provider). A move refused with
  409 `GAME_STATE_CONFLICT` (it lost a race with another write, nothing played, [[Api]])
  reloads the table first (`load(showSpinner: false)`), then fills `actionError`: the snack
  bar reads « La table a changé entre-temps : réessaie. » (`errorGameStateConflict`) over
  the new table — unless that reload found the player ejected, which alone is shown. Any
  other refusal, other 409s included, is a snack bar with no reload. The React board sets
  one `error` for all three and draws an error page instead of the table
  (`GameBoard.jsx:220-235`) — including after a move that actually landed.
- **Loads are sequenced** (`_loadGeneration`, the guard of `services/sse_client.dart`):
  a move's refetch and the broadcast it triggers put two `GET /state` in flight a fraction
  of a second apart, and they can answer out of order. Only the newest answer is kept;
  an older one, good or bad, is dropped. Without it a bot party could leave the board a
  turn behind, every button disabled, with no event left to correct it.
- **One selection, in the provider**: the tapped ids in tap order, dropped whenever the
  hand changes. React keeps one in `PlayerHand` and another in `GameBoard`, and they drift
  apart. `invalidPlay` is `analyzePlay`'s code; the action bar shows its text and disables
  Play, and the board stays. The discard card is kept across a refresh that leaves the
  hand as it was, so `willTakeFromDiscard` checks it is still in `lastCardsPlayed`: a card
  gone from the pile is never posted, and Take falls back to Draw.
- **Modes**, from `gameState.currentAction`: `selectHandSize` shows
  `GameHandSizeSelector` (4-7, or 4-10 in Golden Score; it starts on the middle of the
  range, 5 or 7) to the starting player and a waiting card to everyone else, both under
  the `GamePlayerTable` and its scores (T3) in one scroll view; `play`/`draw` show the
  board; `finished` shows the end of the round (below).
- **Widgets take plain data**, as the lobby's do: `GamePlayerTable` (a `GameSeat` per
  line, below); `GameTableArea` (the `lastAction` message, the cards laid down this turn,
  the discard pile and the deck — both targets only in the draw step —, and the
  "reshuffled" banner for 2.5 s, timed in the widget's state); `GameHand` (the `CardFan`
  under the hand value); `GameActionButtons` (the step indicator, the one button naming
  the move, the refusal, and ZapZap). "The turn reads itself" ([[FlutterGameUi]]) has what each shows.
- **Back leads to `/parties`, not to the lobby**: `PartyLobbyProvider.load` sends a party
  that is `playing` straight back to `/game/:id`, so a back button pointing at the lobby is
  a flash and a full remount of the board, and no way out of the game. Every exit of the
  game — its back button, the body's back button, "back to the parties" at the end, a
  deleted party — calls `popOrGo(AppRoutes.parties)` (`utils/navigation.dart`), which
  replaces the game's browser entry by the list's (Back navigation, [[FlutterParties]]), so the
  browser's Back from the list never reopens the game.
  `test/game_screen_test.dart` (`leaving the board`) checks list → game → back: `/parties`,
  `canPop()` false, reported as `(replace)`.
- **Layouts**: under 800 px one column that fills the height — each section over its own
  scroll view, so a large system font shrinks a section instead of overflowing the column
  —, above it the players beside the felt. The phone column is a `CustomMultiChildLayout`
  (`widgets/phone_board_layout.dart`, `PhoneBoardLayout`): the moves take what they need
  at the bottom, the players up to 3/11 of the rest, the hand what it needs as long as the
  felt keeps 1/5 (`feltFloor`), and the felt is laid out at exactly the height left between
  the players and the hand — no empty band between felt and hand, and the felt's content
  centred in it (`GameTableArea` fills a tight height: `StackFit.passthrough`, then a
  `minHeight` under its scroll view). A `Column` of `Flexible`s left the unused share as an
  empty band and cut the felt in the draw step (production, 390x844, 2026-09-23); the
  earlier delegate still left ~100 px between felt and hand at 360x740. In the draw step
  the hand, which cannot be played then, keeps at most 1/5 of the height
  (`drawHandShare`) and scrolls, and the felt gets the rest. The hand is then read, not
  played (`GameHand.compact`): its value alone — no gauge, no Clear, a picked pile card
  is dropped by tapping it again — over one row of 48 px cards, and the felt's cards
  played this turn shrink to 49 px (`GameTableArea.drawPlayedWidth`): #64's two rows of
  big cards in 3/20 showed only a strip of rank (production, 360x740, 2026-09-24). The
  `lastAction` message is
  hidden then — it is this player's own play, which the "Posées" row shows. The
  felt scrolls *inside* its own edge (`Key('gameTableScroll')`), so its border, amber in
  the draw step, is never cut. `test/game_felt_layout_test.dart` proves it at 360x740 and
  390x844, text scales 1.0 and 1.5, with Roboto loaded from the SDK (the test font's square
  glyphs are twice as wide): the whole felt, the deck and the take hint show, except at
  360x740 at 1.5, where the players and the moves take half the height and the felt's
  content scrolls inside a whole edge. The wide board's felt is `Expanded` too, and lays
  the cards played this turn beside the pile and the deck, labels in line
  (`GameTableArea.playedBeside`), folding them above the pile when the felt is narrow: the
  hand and the moves left a 1366x768 window's felt too short for two rows of 84 px cards,
  which were cut by 67 px (52 at 1280x800; found evaluating the PWA, 2026-09-29).
  `test/game_felt_layout_test.dart` (`wide screen`) shows the whole felt, content and all,
  at 1366x768, 1280x800, 1920x1080 and 800x1280, in the play and the draw step. Checked in the PWA (2026-09-23, Chromium at
  390x844, the web build against a stand-in API in the draw step). `test/game_screen_test.dart`
  pumps every mode at 360x740 at text scales 1.0, 1.5 **and** 2.0 — not my turn with a two-line
  waiting banner, the tallest action bar (two-line banner over the invalid-play reason)
  and a Golden Score hand of 10 included — and the wide layout at every scale too; the
  suite's default 1100x3000 hides clipping.
- Checked against the local backend (then Node, 2026-09-23): a party of Vincent and two bots
  played through the web build in Chromium — hand size, play, take from the discard, draw,
  the bots' moves arriving over SSE, the end of the round and the next round. Known local
  limit: a round that ends does not advance on its own when bots are to act (the Node bot
  orchestrator had no `finished` branch), so the Next round button is what moves it on.
  The end of a round, Next round and the end of the game were checked the same way
  (2026-09-23): a game of Vincent and two bots played to its end over the local backend —
  a successful ZapZap with its standings and revealed hands, three rounds started from the
  client, an eliminated player's badge, and the winner banner with Back to games.

### The turn clock (`widgets/turn_countdown.dart`, `GAME_RULES.md` "Turn Time Limit")

- The rule, its enforcement and the `/state` fields are the backend's ([[GameRules]] § Turn
  time limit, [[Api]]). `GameState.turnClock` (`TurnClock`: `turnDeadline` and `serverTime`,
  both the server's Unix ms) is `null` when `turnTimeLimit` is 0 or either instant is
  missing — a game without a limit, one that started with a single human, a bot on turn,
  between two rounds.
- **The countdown sits on the line of the player to move** (`GameSeat.turnClock`, set by
  `GameScreen._seats` on the `currentTurn` seat only), so every player sees it, in every
  mode that shows the table: the hand-size choice included (the clock covers it), the phone
  board's folded table too (its one line is the player to move's). `TurnCountdown`
  (`countdownKey`): a timer icon and `m:ss`, amber, red from 10 s (`urgent`), a screen
  reader's label `gameTurnTimeLeft`. It stops at 0:00: the server ejects within its 1 s
  tick and the `playerReplaced` event redraws the table.
- **It never reads the device's clock**: it starts from `turnDeadline − serverTime` when
  the answer is drawn and subtracts a `Timer.periodic`'s `tick` (the whole seconds gone by,
  missed ticks counted, in the VM and in dart2js alike). A phone whose clock is minutes off
  still shows the server's time left. A new `TurnClock` (another answer: the next turn, or
  a refetch of the same one, whose `serverTime` differs) restarts it from its own figure;
  a rebuild with the same one does not.
- In the seat line the countdown is not flexible: the name gives way (ellipsis), and the
  countdown only scales down past 3/5 of the name's room — a 2.0 text scale on 360 px.
- Tests: `test/game_screen_test.dart` (`the turn clock`: another player's turn counting
  down on their line from a server time in 2001, red at 0:10, stopping at 0:00; my own in
  the hand-size choice and its label; none without a limit or on a bot's turn; each answer
  restarting it; 360×740 at 1.0, 1.5, 2.0 beside a long name — `ejected by the turn clock`:
  mine, the message and `/parties` with no refetch, in English too; mine with the event
  missed, from a refetch or a move answering `NOT_IN_PARTY`; a first load answering it
  still the error page; another player's, the seat showing the bot),
  `test/game_provider_test.dart` (the same, the "not started yet" page included, and a
  lost race: the reload, the conflict's `actionError`, another 409 with no reload, a race
  lost to one's own ejection), `test/models_test.dart`.

### The end of a round and of the game (`widgets/game_round_end.dart`)

The port of the React client's `components/Game/RoundEnd.jsx`, fed by its `GameBoard.jsx`.
`GameScreen._roundOver` builds it from `GameState` alone — never from the answer of
`zapzap`, whose `scores` were the round's own points on Rust before 2026-09-24 and are the running
totals since (API layer, [[FrontendFlutter]]). It is the `finished` mode of the board, not a route: the phase is
reached and left by `currentAction`, which every move and the other clients' `roundStarted`
change. A failed refresh leaves it on screen under the stale banner, as any other mode.

- **A player's round score** is `roundScores[index]`, else 0 for `lowestHandPlayerIndex`
  and `handPoints[index]` for everybody else, as React reads it. Players are laid out
  lowest round score first; ties keep turn order, which `List.sort` alone does not promise.
- **A table, not a card per player** (F1 of the UX study, 2026-09-23): one row per
  player — rank, name, the revealed hand (`allHands`) in miniature (22 px `PlayingCard`s
  that overlap as much as the column needs), `+` this round's points, the total —, under a
  header row; above a 1.2 text scale the miniature goes under the name. Four players and
  the button fit a 360x740 phone without scrolling, eight at a 1.0 text scale.
- **Markers**: a bolt for `zapZapCaller` and a crown for `lowestHandPlayerIndex`, icons with
  a tooltip and a semantic label so a row stays one line; "You" on the caller's own row,
  which is also tinted with an amber edge (`isMe`, from `myPlayerIndex`); Eliminated in
  words, not in colour alone. The rank column replaced the `#1` badge. **Eliminated** is
  `eliminatedPlayers` *or* a total above 100 (`GAME_RULES.md`): the Node backend filled the
  list, React only compares the total, and the client keeps both. A player who is out never
  gets the Lowest Hand badge, as in React: on the last round of a game the Node backend
  pointed `lowestHandPlayerIndex` at a seat it had already eliminated, hand empty.
- **The ZapZap banner** is green when the call held and red when it was counteracted, and
  then names who counteracted and spells the penalty out:
  `handValue + (activePlayers − 1) × 5`, where `activePlayers` are those whose total
  *before* the round (`total − roundScore`) was 100 or less. React counts the totals after
  it instead, so it charges a player who was eliminated by this very round. Under its
  title, one sentence says why (F2): held — "their hand was worth n points, the lowest at
  the table: X scores 0"; counteracted — "Counteracted by Y (a ≤ b): hand + penalty". `a`
  and `b` are the hand values the call was decided on, a Joker counting 0
  (`handValue(allHands[i])`, `utils/rules.dart`); `hand` is `handPoints`, where the backend
  counts it 25 — so a caller holding a Joker reads "(1 ≤ 1): 26 + 15".
- **The danger zone** (F3): under each row a bar of the total towards 100, amber, red above
  80 (`RoundEndScoreBar`), full once the player is out.
- **Totals climb** (F5): the total and its bar go from `total − roundScore` to `total` in
  400 ms (`TweenAnimationBuilder`), at once when `MediaQuery.disableAnimations` is set.
- **The way on is pinned** under the scrolling table (F4): Next round (`POST /nextRound`,
  disabled while a move is in flight) with "Round n+1: X picks the hand size" above it, or,
  once `gameFinished`, Back to games, the winner banner (`winner.username`, its final
  score) heading the page. X is the seat after this round's `startingPlayer`, skipping
  whoever is out (`GAME_RULES.md` "Subsequent Rounds").
- Every name is `Flexible` inside its `Row` and every figure a `FittedBox`: a `Row` that
  sizes itself to its children hands an unbounded width to its text, which then runs off a
  360 px phone at a 1.5 text scale. `test/game_round_end_test.dart` proves F1–F5 at 360x740
  at text scales 1.0, 1.5 and 2.0.
- Checked in the PWA (2026-09-23, Chromium at 360x740, the web build against a stand-in API
  answering a finished round): the held and the counteracted round as in the study's
  mockup.

### The example game (`/tutorial`, `screens/tutorial_screen.dart`, `providers/tutorial_game.dart`)

- **The real board, fed by a script** (2026-09-27): `TutorialScreen` lays out
  `GamePlayerTable`, `GameTableArea`, `GameHand` and `GameActionButtons` in
  `PhoneBoardLayout`, as the phone board does (centred, 520 px at most, on a wide screen),
  from a `TutorialGame` (a `ChangeNotifier` of its own) instead of `GameProvider`: no
  repository, no event stream, no HTTP call. It moves the state as the backend would — a
  play puts the cards laid down before it on the pile (`_layDown`), a draw takes the pile
  card picked or the deck's —, so the felt's motion (J9) runs as in a game: each action is
  notified on its own, the player's draw first (the card taken leaving down toward the hand),
  then Alex's turn after it, one move per `TutorialGame.opponentPause` (900 ms: his play,
  then his deck draw), the board meanwhile as after a draw in a game — not the draw step, the
  felt's message naming each move, nothing playable — under a `tutorialOpponentTurn` bubble.
- **The script** (`TutorialStep`): a fixed deal of six (K♠ 9♥ 9♣ 4♥ 5♥ joker, 40 points),
  8♠ flipped, 41 cards left in the deck (54 − 2×6 − 1), one opponent, "Alex" (not translated), who plays one card and draws after each
  of the player's draws. Intro → play K♠ alone → draw from the deck (2♦) → play the pair of 9
  → take A♣, Alex's card, from "À prendre ensuite" → play the run 4♥ 5♥ joker → draw from the
  deck (A♠) → call ZapZap at 4 (confirmed on the real sheet) → held, 0 points, Alex's seat
  scoring his hand (`opponentFinalHand`, 39 points) → the
  counteract penalty and elimination above 100 → Finish. Each step names its zone
  (`TutorialZone`: hand, felt, moves) and a `CoachBubble` sits over it, its tail pointing
  down at it; a step with no move (intro, held, end) carries Next or Finish.
- **One move per step**: `play`, `draw` and `zapZap` accept only the move the step asks for
  (`TutorialStep.play`, `take`, `draws`); anything else leaves the state as it was and
  shows the step's hint in the bubble (`tutorialHint`). Selecting cards is free: the action
  bar shows `analyzePlay`'s refusal for an invalid selection, as in a game.
- **Skip** (`tutorial-skip`, app bar) and Finish leave through `popOrGo('/')`: back to the
  screen below, or home — which a signed-in player is sent on from to the parties. The
  player's seat is named after the signed-in user, else `tutorialGuestName`.
- **Values**: `zapZapThreshold` (5, `utils/rules.dart`) and
  `GamePlayerTable.eliminationScore` (100) fill the strings' placeholders;
  `test/tutorial_test.dart` checks them against `GAME_RULES.md`. **A rule change updates the
  `tutorial*` strings too.**
- **The first opening** (`widgets/tutorial_offer.dart`): `ZapZapApp.tutorialOffer`, a
  `TutorialOfferStore`, puts `TutorialOffer` in `MaterialApp.builder`, above the navigator —
  a card over a `ModalBarrier`, not a dialog, decided once the session and the flag are read,
  and offered **only signed out and not on `/tutorial`** (nor the splash remembering it) — so
  never over a game, which needs a session. A signed-in user (every tester who had the app
  before it) or one opening on `/tutorial` gets no offer and the flag is set, so a later
  sign-out does not bring it up. A store that fails to read offers nothing; one that fails to
  write is logged, the answer still taken. The offer: « Apprendre
  avec une partie d'exemple ? », Commencer (`tutorial-offer-start`, pushes `/tutorial`) /
  Plus tard (`tutorial-offer-later`). Either answer sets `tutorialOffered` in
  `shared_preferences` (`PreferencesTutorialOfferStore`) and it is never offered again. The
  app stays the stack's first child whether the card shows or not, so the navigator keeps its
  state. `null` (the default, every other test) offers nothing; `main.dart` passes the
  device's store.
- **Reached from** the ⋮ menu (`menu-tutorial`) of every signed-in screen and a link under the
  login form (`login-tutorial`, disabled while a sign-in is in flight, as the register link
  is), both `push`ed: Back returns.
- `test/tutorial_test.dart`: the whole script played with no HTTP request; every step at
  360x740 in the ten languages (and German at 1.5) without overflow; a wrong move at the
  single, deck, take and ZapZap steps refused with its hint; Skip from each step back to the
  login screen; the values against `GAME_RULES.md`; the player's take, then Alex's play, then
  his draw reaching the felt one at a time (the card taken leaving down), the deck draw
  leaving down too; Alex's score after the held ZapZap; the deck's 41 cards and one per draw;
  the offer on a first opening, gone after Start or Later and a relaunch, none signed in or
  on `/tutorial` (flag set), none with a store that throws; the login link disabled while
  signing in; the menu of `/parties` and `/history` opening it.
- Checked in the PWA (2026-09-27, headless Chromium at 390x844, the web build served
  statically, no backend): the offer over the home screen, Commencer opening the intro with
  its bubble over the hand, a mixed selection refused by the action bar.

## Decisions & History

- **The end of a round is a table (2026-09-23, `feat/flutter-round-end-ux`).** The UX
  study (F1–F5) found a card per player, ~200 px each, showed three players of four and
  made comparing a matter of scrolling. A table row per player, the result in one sentence,
  the player's own row and a bar towards 100, the button pinned with who deals next, and
  totals that climb, all in the existing theme. The badges of the lowest hand and the
  caller became icons so a row stays one line.
- **The game board (2026-09-23, `feat/flutter-game-board`).** One `GameProvider` per party,
  built by the screen like the lobby's, rather than an app-wide one: a board's state is one
  party's and dies with the screen. A refused *move* is a snack bar and the board stays,
  while only a failed *load* replaces it — the React board replaces itself on any error at
  all, which loses the table on a stray 400. The selection lives in the provider alone, so
  the hand and the buttons cannot disagree the way `PlayerHand` and `GameBoard` do. The
  phone layout is `Flexible` sections over scroll views instead of fixed heights: it fits
  360x740 at a 1.5 text scale, which a fixed layout does not, and the tests pump both
  scales because the suite's default size hid two earlier clipping bugs. The end of a round
  was deliberately minimal here and became its own pull request.
  Review of #34 found the headline claim half true: a failed *refresh* still went
  through the same `error` field and took the table away after a move that had landed,
  and two loads in flight could answer out of order and put the board a turn behind.
  Hence three error fields and the generation guard, both above.
- **The end of a round (2026-09-23, `feat/flutter-round-end`).** A widget taking plain
  data (`GameRoundEnd`), not a route of its own: the round's end is a phase of the board,
  reached and left by `currentAction`, and a route would have to be pushed and popped by
  every event that changes it. The standings are read from `GameState` rather than from the
  `zapzap` answer, because the two backends disagreed on what that answer's scores mean; with Rust alone, a round another player ends reaches the board only as an event and a `/state` refetch, so `/state` stays the one path.
  `lowestHandPlayerIndex` decides the crown, where React looks for the first player who
  scored 0 and is still alive — the same thing until two players tie on 0 — but a player
  the round has just put out never keeps it: checked against the local backend, Node names
  an already-eliminated, empty-handed seat on the last round of a game. The counteract
  penalty is spelled out from the rule (`GAME_RULES.md`) with the players who were active
  *before* the round, which is what the backend charged; React's own arithmetic is wrong
  here (`wip/todo_nr/2026-09-22-react-utils-disagree-with-game-rules.md`). The three ARB
  keys the minimal state used (`gameRoundOverCaller`, `gameRoundScoreLabel`,
  `gameTotalScoreLabel`) were replaced rather than kept: "Manche 49" for a score read as a
  round number.
- **The example game runs on the board's widgets, not on a fake backend (2026-09-27,
  `feat/flutter-tutorial`).** The widgets take plain data, so a local `TutorialGame` feeds
  them directly; faking `/state` answers would have run the tutorial through the network
  layer it must stay out of, and tied it to `GameProvider`'s event handling. The offer sits
  in `MaterialApp.builder` so it shows over the screen a signed-out app opens on (home,
  login) without each screen knowing about it — signed out only, since a signed-in user may
  be on a game and already knows ZapZap; its store is injected and absent by
  default so the existing tests keep pumping the app without `shared_preferences`.
- **`playerForfeited` joined the reload list (2026-09-27, `fix/flutter-player-forfeited`).**
  #132 made a deleted account forfeit its seat in a game in progress and broadcast
  `gameUpdate`/`playerForfeited`; `_onEvent` did not reload on it, so a Flutter player whose
  turn the forfeit handed over saw nothing until the next event or a manual refresh
  (`GameBoard.jsx` already handled it). #132 stayed out of `frontend-flutter/` because
  another agent was working there at the time.
- **The turn clock on the board (2026-09-28, `feat/turn-timer-flutter`).** #162 gave the
  backend a per-turn limit that ejects a late human. The countdown went on the seat line of
  the player to move rather than in the action bar (only the player on turn sees that) or
  in a banner of its own (height the phone board does not have): every player sees who is
  running out, in every mode, the folded phone table included. It counts from the answer's
  own two server instants with a periodic timer's `tick`, never `DateTime.now()` against
  the deadline, so a device clock minutes off changes nothing, and the tests set the server
  time in 2001 to prove it. An ejection of this player leaves the board at once, with no
  refetch — the backend answers 403 `NOT_IN_PARTY` from then on, and a refetch would only
  put the error page up behind the snack bar. The French message is the entry's, in the
  "tu" voice: « Tu as été retiré », not « Vous avez été retiré » (`test/l10n_test.dart`).
  A move that races the ejection answers 409 `GAME_STATE_CONFLICT`, then shown as a
  refusal in a snack bar (until `fix/client-game-errors`, below).
- **A lost race reloads, a missed ejection ends the board (2026-09-28,
  `fix/client-game-errors`).** A 409 `GAME_STATE_CONFLICT` means the table on screen is
  stale; it used to be a plain refusal, the SSE event of the write that won being the only
  reload. Now the move reloads, then says so in the snack bar — a snack bar, not the stale
  banner, since the table is fresh once reloaded. The reload comes before the message so
  that a race lost to one's own ejection ends on the ejection alone. A 403 `NOT_IN_PARTY`
  after a game was shown is taken for the ejection, as React has done since #164: a
  player cannot leave a game under way, so the turn clock is the only way to lose the
  seat. "Shown" means `isStarted`, not a snapshot: the "not started yet" page is a
  waiting party, which a player can leave from another device. The code stays in
  `GameErrorCode`, not `ApiErrorCode`: the backend sends it, and only the board reads it.
