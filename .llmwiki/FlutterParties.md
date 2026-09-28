# FlutterParties

> Scope: the Flutter parties list, create-party form and lobby, back navigation, presence in the
> app bar, and the app-bar menu (rules sheet, confirmed sign-out, account deletion).
> Related: [[FrontendFlutter]] · [[FlutterRealtime]] · [[FlutterGameBoard]] · [[FlutterAuth]] · [[Api]]
> Updated: 2026-09-28

## Facts

### Parties, create-party and lobby

The React counterparts are `frontend/src/components/Party/{PartyList,CreateParty,PartyLobby,ConnectedPlayers}.jsx`.

- **Routes** (`router.dart`): `/parties` (the list), `/parties/new` (create — declared
  **before** `/parties/:id`, which would match it), `/parties/:id` (the lobby), `/game/:id`.
  `AppRoutes.partyPath(id)` and `AppRoutes.gamePath(id)` build the last two.
- **Back navigation**: a screen reached from another is `context.push`ed, never `go`ne
  to — `go` replaces the whole stack, and Android's system Back then leaves the app. The
  list pushes the form, the lobby and a game; the form's lobby and the lobby's game
  **replace** the screen they came from (`replaceWith`, `utils/navigation.dart`: a
  `pushReplacement` under `Router.neglect`, so the browser's history entry is replaced
  too), so Back from either — Android's or the browser's — returns to the list, not to a
  form whose party exists or a lobby that sends straight back to the game. A screen's own back button, and the lobby closing, call `popOrGo`
  (`utils/navigation.dart`): pop when something is below, else `go` to the list — a deep
  link or a reload of the PWA has nothing below. The history, the game details and the
  statistics follow the same rule ([[FlutterHistoryAdmin]]). go_router reports a pop, like a `go`, to the
  browser as a *new* history entry (`replace: false`), so the browser's Back would reopen
  the screen just left; `popOrGo` runs under `Router.neglect`, which replaces the entry
  instead. `test/party_screens_test.dart` (`back navigation`) and `test/app_bar_test.dart`
  drive the system Back (`handlePopRoute`); `test/deep_link_test.dart` (`a back button
  replaces the screen it leaves`) reads what each back button reports on
  `SystemChannels.navigation`: `/parties (replace)` from the form, the lobby, the history
  and the statistics, `/history (replace)` from the details opened by a link.
- **Screens own their provider**: each screen builds it in `initState` from the
  repositories it reads off the tree and disposes it, and draws with a `ListenableBuilder`;
  the widgets below take plain data. Only `ConnectedPlayersProvider` is app-wide.
- **`PartyListProvider`** (`providers/party_provider.dart`): `GET /party`, pull-to-refresh
  (`load(showSpinner: false)`), and `join` — which answers `true` on `ALREADY_IN_PARTY`
  too, because React navigates to the lobby on it (`PartyList.jsx:37-39`). **The event
  stream keeps the list current** (React waits for a reload): `playerJoined`, `playerLeft`,
  `partyStarted`, `partyDeleted` and `gameFinished` (`refreshingActions`), about any party,
  reload it without a spinner `refreshDelay` (1 s) after the last one, so a burst of bot
  joins is one `GET /party`; a game move reloads nothing. Only the newest load's answer is
  kept (`_loadGeneration`, as in the lobby), so a pull and an event answering out of order
  never show the older list. Dispose cancels the pending reload and the subscription. No
  event announces a party being created: a new one appears with the next event about any
  party, or on pull-to-refresh. **The screen has two sections** (`screens/parties_screen.dart`):
  "My games" (`myParties`: the caller's, `isMember` — a running game first, then the
  lobbies, then the finished ones, each in the backend's order) and "Available games"
  (`openParties`, the heading `partiesHeading`). **A card is two lines**
  (`widgets/party_card.dart`): the name and a badge, then "seats · status · you host" and
  one button. A running game of mine has an amber border, an "In progress" badge and the
  only filled button, Resume; my lobby is green-bordered, Joined, with an outlined Lobby;
  someone else's party has an outlined Join (disabled when full, playing or finished).
  There is **no "your turn" badge**: `GET /party` does not say whose turn it
  is. While the first answer is on its way the list shows three skeleton cards; an empty
  "Available games" ends on an invitation (create yours — `push`es `/parties/new` —, or
  pull down to refresh), worded "no game available" when I have none either. The list
  ends with `PartiesScreen.fabClearance` (88 px) so the amber Create button never covers
  the last card's button. A row without
  `maxPlayers` (or with 0) falls back to `settings.playerCount`, then to 5
  (`defaultPartyPlayers`, `models/party.dart`), as React does — not "2 / 0" and Full. A
  failed load shows its error banner alone, not the "no party yet" empty state under it. The cards are laid out
  as rows of one to three (`_cards`, by width), not as a `SliverGrid`: a grid tile's height
  is decided before the card is laid out, and any fixed one overflows at a large system
  font size.
- **`CreatePartyProvider`** (`providers/create_party_provider.dart`): the form — the seat
  count (3–8, clamped), the visibility, the name. **No human or bot per seat** (since
  2026-09-28): the creator takes seat 0, the others are filled in the lobby, by players or
  by the host's bots; a line under the settings says so (`create-seats-hint`,
  `createPartySeatsHint`). **The time per turn** (`turn-time-limit`, items
  `turn-time-limit-<s>`): « Sans limite » (the default), 30 s, 1 min, 2 min
  (`turnTimeLimits`; `TurnTimerL10n.turnTimeLimitText`, `utils/turn_timer.dart`), offered
  on every form — creation does not know who will be human — with a helper saying the
  clock counts only when two humans or more start the game and a late player is replaced by
  a bot (`GAME_RULES.md` "Turn Time Limit"). `POST /party` sends `{name, visibility,
  settings: {playerCount, turnTimeLimit}, botIds: []}` and the form never calls `GET /bots`.
  The name is 3 to 50 characters once trimmed (`partyNameMinLength`/`MaxLength`), as the
  backend requires: Create stays active, and a name
  too short shows its reason once the field was edited and left or Create tapped
  (`FieldTouch`), and sends nothing; longer cannot be typed.
- **`PartyLobbyProvider`** (`providers/party_provider.dart`): `GET /party/:id`, then the
  event stream filtered on `partyId` — `playerJoined`/`playerLeft` reload the seats without
  a spinner, `partyStarted` and `partyDeleted` set `outcome` (`LobbyOutcome.started` /
  `.closed`) and the screen navigates to `/game/:id` or `/parties`. A party already
  `playing` when it loads sets `started` too, so returning to it goes straight to the game.
  `isOwner` comes from the answer, as it is; `canStart` needs the owner and 3
  players; `canAddBots` the owner, a waiting party and a free seat (`freeSeats`). The
  host's bots: `loadBots` (`GET /bots`, a failure only empties the menu), `availableBots`
  (a difficulty's bots not at the table), `addBot` (the first of them, `POST
  /party/:id/bots`, then a reload without waiting for the event) and `fillAndStart`
  (`POST /party/:id/fill-and-start {difficulty}`, then `outcome = started`; a refusal —
  409 `NOT_ENOUGH_BOTS`, `errorNotEnoughBots` — stays in the lobby). Only on a tap: nothing
  fills or starts after a delay. `botDifficulties` (the six the add-bot menu offers) and
  `fillDifficulties` (`easy`, `medium`, `hard`) are in `models/bot.dart`; `canDelete` is the owner **or** the only human at the table
  (`PartyLobby.jsx:140-144`). Delete asks first, in an `AlertDialog`. Its loads are
  sequenced as the board's are (`_loadGeneration`, [[FlutterGameBoard]]): two players joining a moment
  apart start two reloads, and an older answer arriving last is dropped.
  The hand size is only shown when the party carries one (Rust answers before 2026-09-24):
  the starting player picks it each round (`GAME_RULES.md`), so React's "Hand Size: 7" is
  wrong.
- **The lobby screen** (`screens/party_lobby_screen.dart`, S1–S4 of the UX study) opens on
  the invite code (`party.inviteCode`), 26 px mono amber with a
  Copy button (clipboard, then a snack bar); then the settings as one `Wrap` of chips
  (`InfoChip`, `widgets/player_seat_tile.dart`): seats, the time per turn when one is set
  (`lobby-turn-timer`, « 30 s par tour »; none when off), "you host", the
  status (no hand size: the starting player picks it each round, `GAME_RULES.md`). A seat (`PlayerSeatTile`) shows a green "online" dot for a human the session
  knows is connected — the signed-in player, or one in `ConnectedPlayersProvider`, which
  holds five at most, so no dot means "not known", never "offline" —, a bot's level as an
  amber chip, the owner's crown. A free seat (`EmptySeatTile`) is text, the first one
  pointing at the invite code; for the host it also carries « Ajouter un bot »
  (`empty-seat-<n>-add-bot`) at its right edge, a menu of the six levels (`add-bot-<level>`,
  one whose bots all sit here disabled, `lobbyAddBotUnavailable`). Under the seats, for the
  host while a seat is free: « Compléter avec des bots et commencer » (`fill-and-start`),
  a dialog (`fill-dialog`) with Facile / Moyen / Difficile (`fill-level-<level>`, Moyen
  picked) and Commencer (`fill-confirm`), which leads to the game. It sits in the list, not
  pinned with Start: at a 2.0 text scale on 360×740 a fourth pinned button left the seats
  161 px. Under the list, pinned: the reason Start is or is not active (players missing,
  "can start", or "the host can start" for a guest), Start named with the player count,
  then Leave. **Delete is in the ⋮ menu** (`AppBarMenuAction`, key `delete-party`), no
  longer a red button next to Leave; it still confirms.
- **`ConnectedPlayersProvider`** (`providers/connected_players_provider.dart`), app-wide
  and lazy: `GET /players/connected` on sign-in (kept to five, as the events are), **again
  on every (re)connection of the event stream** (it follows `SseProvider.connected` through
  a `ChangeNotifierProxyProvider2` in `appProviders`), then `userConnected` (prepended, five
  at most) and `userDisconnected`; no event says a player moved to a party or a game. The sign-in fetch usually answers
  before the backend has registered our stream — a lone player then saw 0 —, and what
  happened while the stream was down never arrives; the reload on connection covers both.
  An answer overtaken by a later load is dropped (`_loadGeneration`). Until the first
  answer or event (`loaded`), and after a failed one, the app bar shows `–` rather than a
  count: "0" would claim nobody is online (`test/party_provider_test.dart`). The app bar (`widgets/zapzap_app_bar.dart`) holds it, the connection
  indicator and the ⋮ menu — icons only, so it fits a phone, which the React header does
  not. No sign-out icon in the bar: on the game screen, beside the back arrow, testers took
  it for "leave the table" (2026-09-27).
- **The app-bar menu** (`widgets/zapzap_app_bar.dart`, key `app-bar-menu`) leads to the
  history (`menu-history`) and the statistics (`menu-stats`), with `context.push` so the
  Android system Back button returns to the screen below. A menu rather than one icon
  each: there is no URL bar on Android, and more icons would not fit a 360 px bar at a
  large system font. An admin session also gets `menu-admin` (`AuthProvider.isAdmin`, read
  when the menu opens), leading to `/admin`. A screen may add its
  own entries below a divider (`ZapZapAppBar.actions`, `AppBarMenuAction`): the lobby's
  Delete. Between the destinations and those, on every signed-in screen, the game board
  included: **Règles / Rules** (`menu-rules`), which opens `widgets/rules_sheet.dart`
  (`showRulesSheet`, `RulesSheet`, key `rules-sheet`) — a modal bottom sheet over the
  current screen, at 60 % of its height (dragged up to 90 %), so the table stays in sight;
  a short summary of `GAME_RULES.md` in the `rules*` ARB strings (goal, the round, card
  values, the turn, the time per turn, valid plays, ZapZap at 5 points or less, the counteract penalty,
  elimination above 100 points, the Golden Score): **a rule change updates those strings
  too**. The entries that open something over the screen rather than lead to a route are
  ids in `_NavigationMenu`'s `overlays` map (`rules`, `logout`, `delete-account`); a new
  one is one id, one map entry, one `_item`. Under Rules, **Tutoriel / Tutorial**
  (`menu-tutorial`) pushes `/tutorial` (The example game, [[FlutterGameBoard]]). Last, below another divider:
  **Se déconnecter / Sign out** (`menu-logout`), which asks first (`confirmLogout`,
  `logout-dialog`: « Se déconnecter ? », `logout-cancel` keeps the session and the screen,
  `logout-confirm` calls `AuthProvider.logout`, Google signed out too), then, in red,
  **Supprimer mon compte / Delete my account** (`menu-delete-account`), which opens
  `widgets/delete_account_dialog.dart` (`delete-account-dialog`): the warning (irreversible;
  finished games stay in the others' history as « Joueur supprimé »), then a password field
  (`delete-account-password`, `delete-account-confirm` enabled once it is filled) — or, for a
  Google account (`User.isGoogleUser`, stored with the session), a "Confirmer avec Google"
  button (`delete-account-google`; Google's own button on the web) whose fresh ID token is
  sent as `credential`, the login screen's way. Google that does not get ready (script
  blocked, no route to Google, no client id) is given up on as the login screen does it
  (`GoogleSignInSection.watchReady`, `readyTimeout`, shared per service): the button gives
  way to a notice (`delete-account-google-unavailable`: try later, or ask by e-mail).
  Refusals stay in the dialog
  (`delete-account-error`, `deleteAccountErrorText`): 403 `INVALID_PASSWORD` (and 400
  `MISSING_CONFIRMATION`) → wrong password, 403 `GOOGLE_AUTH_FAILED`, 409 `ACTIVE_PARTY`
  (leave or finish your games first), 409 `LAST_ADMIN`. None is a 401, so none signs out.
- **Error text** comes from `partyErrorText` (`widgets/error_banner.dart`), mapping
  `ApiException.code` (`PARTY_NOT_FOUND`, `PARTY_FULL`, `PARTY_STARTED`,
  `PARTY_ALREADY_PLAYING`, `NOT_OWNER`, `NOT_AUTHORIZED`, `NOT_IN_PARTY`, no answer) to
  ARB strings;
  `PartyErrorCode` (`providers/party_provider.dart`) names the party codes.

## Decisions & History

- **Parties, create and lobby (2026-09-22, `feat/flutter-lobby`).** Each screen owns its
  provider instead of a global one, because the lobby's state is one party's and dies with
  the screen; presence is the exception, being app-wide, and is the only new entry in
  `appProviders`. Navigation out of the lobby goes through one `outcome` field rather than
  callbacks per action, so a button here and an event from another client leave the same
  way. `/game/:id` gets a placeholder screen rather than no route at all, so a started
  party has somewhere to land before the board exists. The app bar deliberately carries no
  History, Stats or Admin entry yet: those routes do not exist, and a dead link is worse
  than a missing one.
- **App-bar menu rather than icons, and no Admin entry (2026-09-23,
  `feat/flutter-app-bar-links`).** The history and statistics routes exist since #33, so
  the app bar leads to them; a `PopupMenuButton` rather than two more `IconButton`s
  because the bar already carries the presence count, the connection indicator and
  sign-out, and 360 px at a 1.5 text scale leaves no room. `context.push`, not `go`: the
  screen stays on top of the parties list, so the Android system Back button returns to
  it. `/admin` still has only the router guard of #29, so an Admin entry would land on the
  not-found screen — it waits for the admin screen
  (`wip/todo_nr/2026-09-22-flutter-admin.md`), and a test kept the menu free of it. The
  admin screen came on 2026-09-24 (`feat/flutter-admin-users`): admins get the Admin entry
  since, and the test checks it leads to `/admin`.
- **Back navigation: `push`, and `popOrGo` (2026-09-23, `fix/flutter-back-navigation`).**
  Every screen but the app-bar menu's destinations was reached with `go`, so Android's
  system Back left the app from the form, the lobby, the history, the details and the
  statistics, and one tap on the history's statistics shortcut threw away the stack the
  menu had built. The shortcuts went with the hand-rolled app bars: `ZapZapAppBar`'s menu
  already leads to both. The form's lobby and the lobby's game replace their screen rather
  than stack on it. Absorbed in the same change: the `maxPlayers` fallback, the 3-50 name,
  `NOT_IN_PARTY`, the sequenced lobby loads, the presence count before `loaded`, the
  12-hour English clock, the bot filter reset, and red over green in the rounds table.
  `authErrorNetwork`/`authErrorGeneric` duplicated `errorNetwork`/`errorGeneric` word for
  word, and `backToParties`/`backToHistory` lost their callers to `BackButton`: all four
  keys were dropped.
- **Pushed screens own the URL (2026-09-23, `fix/flutter-pushed-route-urls`).** After
  `push` replaced `go`, the address bar stayed on `/app/parties` under the form, a lobby
  or a game, so a reload dropped the user on the list and a lobby could not be shared.
  go_router advises against `optionURLReflectsImperativeAPIs` because a pushed route's
  path is not always a deep link; here every route is top-level and loads itself from its
  path parameters, so it is. `pushReplacement` alone still added a browser history entry,
  and the browser's Back returned to the replaced form: `Router.neglect` makes it replace
  the entry instead. Checked on a web build behind `frontend-flutter/nginx.conf` against a
  local Node backend on a fresh database: list, form (`/app/parties/new`), lobby
  (`/app/parties/<id>`, history length unchanged), reload on the lobby, Back to the list,
  Back out of the app.
- **Every back button replaces the browser's entry (2026-09-24,
  `fix/flutter-back-replaces-history`).** Only the game's exits used `leaveFor`; the form,
  the lobby, the history, the statistics and the details still popped with a plain
  `popOrGo`, which go_router reports as a new browser entry, so after list → history →
  back the browser's Back reopened the history. `leaveFor` was folded into `popOrGo`.
  Absorbed in the same change: seven ARB keys without a caller since the compact party
  card and the lobby's chips (`partyContinueButton`, `partyReturnToLobbyButton`,
  `partyInProgressButton`, `lobbySettingsTitle`, `lobbyMaxPlayers`, `lobbyHandSize`,
  `lobbyStartButton`) were dropped.
- **The lobby shows its invite code and hides Delete (2026-09-24, `feat/flutter-lobby-ux`).**
  The UX study (S1–S4) found the invite code — the only way into a private party — never
  on screen, a 120 px settings card, seats that did not say who was there, and three
  full-width buttons with a red Delete a thumb away from Leave. The mockup's "add a bot"
  on a free seat was dropped at refinement: no backend route seats a bot in an existing
  party (wip `2026-09-23-add-bot-to-waiting-party`). The party's name left the body: the
  app bar carries it. Checked on a web build against a local Node backend on a fresh
  database at 360×740.
- **The parties list puts my games first (2026-09-24, `feat/flutter-parties-ux`).** The UX
  study (P1–P4) found "Continue" and "Join" with the same amber button on the same ~160 px
  card, a running game lost in the list, a Create button over the last Join, and an empty
  list with nothing to do. The study's "your turn" badge was dropped at refinement: the
  list does not carry the current player, and one state call per running party was not
  worth it (`wip/todo_nr/2026-09-23-party-list-current-turn.md`), so the badge says "In
  progress". The second section keeps the "Available games" heading rather than the
  mockup's "Open games": the auth tests land on that text, and the meaning is the same.
  The player count is an icon rather than the word, so the line fits beside the button on
  a phone; the P1–P4 tests load Roboto, as the felt test does, because the test font's
  square glyphs wrap every compact line.
- **The host fills the table with bots (2026-09-28, `feat/lobby-fill-with-bots`).** Few
  players are online at once, and a seat left "human" at creation waited for someone who
  might never come: the host could only wait or delete. The per-seat human/bot selectors
  left the form (`widgets/player_slot_selector.dart` deleted, its `botDifficultyLabel` moved
  to `player_seat_tile.dart`; eight `createPartySlot*`/`createPartySummary` keys dropped,
  `createPartySlotBotUnavailable` became `lobbyAddBotUnavailable`), and the lobby gained
  what the 2026-09-24 study had dropped for want of a route: « Ajouter un bot » per free
  seat, and one fill-and-start for all ([[Api]]). A menu of the six levels per seat, like
  the old selector, but only three levels in the fill dialog, as asked; its fallback to
  the next level is the backend's. The end-to-end test (`integration_test/play_round_test.dart`)
  seats one bot by hand and fills the last seat.
- **The time per turn at creation (2026-09-28, `feat/turn-timer-flutter`).** Offered on
  every form, not only with two human seats as first decided: since the lobby fills seats
  with bots, creation no longer knows who will be human (user decision, 2026-09-28), and the
  backend enforces the limit only when two humans or more start. A dropdown like the seat
  count rather than four chips: it keeps the form one field per setting, and its helper
  line carries the condition. 60 s reads « 1 min », as `GAME_RULES.md` names it. The rules
  sheet's section sits after "Ton tour", the rule it limits. `PartySettings` no longer
  reads nor sends `roundTimeLimit` (#162 made the backend ignore it).
