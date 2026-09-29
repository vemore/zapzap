# FlutterHistoryAdmin

> Scope: the Flutter history, game details and statistics screens, and the admin screen (users,
> parties, statistics tabs).
> Related: [[FrontendFlutter]] · [[FlutterParties]] · [[Api]]
> Updated: 2026-09-29

## Facts

### History and statistics

The port of the React client's `components/History/GameHistory.jsx`, `GameDetails.jsx` and
`components/Stats/Statistics.jsx` (removed on 2026-09-29, [[Frontend]]; "React" below names
that reference). Three routes, all behind the session:
`/history`, `/history/:partyId` (`AppRoutes.gameDetails(partyId)`) and `/stats`.

- **A deleted player** is shown « Joueur supprimé » / "Deleted player" (`playerName`,
  `utils/player_name.dart`): the backend moves a deleted account's finished games to a
  stand-in user whose **id** starts with `deleted-` (its username is `deleted-<uuid>`, never
  shown). Read from the id, not the username, which anyone could pick. Applied to the
  history list's winner, the details' winner card, standings and round-table columns; the
  leaderboard needs none (the backend leaves stand-ins out of it).

- **`AsyncSection<T>`** (`widgets/async_section.dart`) is the one loading/failed/empty shell:
  a `FutureBuilder` plus a retry button and an `isEmpty` test. A section holds **one** read,
  so the statistics screen's three reads stand or fall on their own — a failing leaderboard
  leaves the personal figures and the bots. Its `errorMessage` is a function of the
  exception, never the backend's text: the game details map `ApiErrorCode.notFound` to
  "this game cannot be found" and everything else to a generic failure.
- **`startRead(future)`** (same file) returns the future after `ignore()`. An `AsyncSection`
  subscribes only on the next build, so a read that fails before that frame would be an
  unhandled zone error (and a red widget test). Every screen starts its reads through it.
- **History** (`screens/history_screen.dart`): a `SegmentedButton` over `HistoryTab.mine`
  (`GET /history`) and `.public` (`GET /history/public`), each row a `HistoryGameTile`
  (`widgets/history_game_tile.dart`) that opens the details — `push`ed, so Back returns
  to the list. The three screens carry `ZapZapAppBar` (presence, connection, the menu)
  with a back button that pops (`popOrGo`: to the list, or the history for the details,
  when opened by a link); the statistics are reached from the history through the menu,
  and Back unwinds them one at a time. The tile shows the winner with their score and the
  number of rounds.
- **My result first (H1–H3 of the UX study, `feat/flutter-history-ux`).** On My games each
  `HistoryGameTile` opens on a `PlacementBadge` ("1er"/"4e", amber when I won) and shows
  my score beside the winner's. The backend sends `userPlacement`/`userScore` on
  `GET /history`; an entry without them shows no badge (`winnerUserId` is not read as a
  place). The public tab shows no place. The list opens on `HistorySummary`
  (`widgets/history_summary.dart`): games and wins from `GET /stats/me` (the whole record,
  not the page of entries), the best place (1 as soon as the record holds a win, else the
  best `userPlacement` of the page), `—` for what is not known; tapping it `push`es
  `/stats`. My games has its own empty state, `HistoryInvite` ("your next finished games
  will show up here", a link that `push`es `/parties/new`), also at the end of a list
  shorter than `HistoryScreen.inviteBelow` (3); the public tab keeps `AsyncSection`'s
  empty message. Ordinals go through `placementLabel`: the ARB `plural` has no `=3`, so
  `historyPlacement` is a `select` on first/second/third/other.
  `test/fixtures/history_list.json` carries both fields (Vincent, 3rd, 122).
- **Game details** (`screens/game_details_screen.dart`): the summary (winner banner,
  players, rounds, end date, visibility), `HistoryStandings` (finishing order, `RankBadge`
  gold/silver/bronze, ZapZap record, final score) and `HistoryRoundsTable` — a `DataTable`
  in a horizontal scroll view, one row per round and one column per player in standings
  order, each cell the round's points over the running total plus the markers (bolt green
  or red for a ZapZap that held or not, a crown for the lowest hand, a cross for an
  elimination; the points are red when counteracted, else green on the lowest hand —
  red first, because a caller tied for the lowest hand is counteracted all the same
  (`GAME_RULES.md`, Tie Handling), and the local database has such rows; React has it the
  other way), with the legend under it. The app bar takes the game's name once the read lands.
- **Statistics** (`screens/stats_screen.dart`): `StatsPersonal` (`GET /stats/me`: two
  `HeroStat`s — wins / games, the average score — then `StatLine`s for the win rate, the
  best score and the rounds, then the ZapZap block: a bar of successful over called and,
  with no call yet, the rule of when one may call — St1, St2 of the UX study),
  `StatsLeaderboard` (`GET /stats/leaderboard?minGames=1&limit=20`, React's own query) and
  `StatsBots` (`GET /stats/bots`) — totals, a `ChoiceChip` per difficulty found in the
  answer, a card per difficulty with its strategy, and the per-bot breakdown once one is
  picked; a reload that no longer carries the picked difficulty falls back to all of
  them. From a content width of 880 px (`StatsScreen.twoColumnsFrom`) the leaderboard
  stands in a column of its own on the right, the personal figures over the bots on the
  left: twenty rows are as tall as the other two sections together.
  `difficultyStyle` (`widgets/stats_bots.dart`) holds the eight known difficulties'
  name, strategy and colour and falls back to the raw name, so a new bot kind shows rather
  than breaks.
- **My row in the leaderboard**: `LeaderboardRow.isCurrentUser` from
  `AuthProvider.user?.id`, as React compared it against its own `useAuth()` user
  (`Statistics.jsx`).
- **Formats** (`utils/date_format.dart`): dates through `intl` in
  `Localizations.localeOf(context)` (React hard-codes `fr-FR`) — the models already turned
  the backend's Unix seconds into UTC `DateTime`, so only `toLocal()` is left; the clock
  is the locale's (`add_jm`: `14:26` in French, `2:26 PM` in English); percentages
  `(v*100).toStringAsFixed(1)`, as React; `Formats.number` for a score or an average
  (`134`, not `134.0`; `12.5`); `—` for a missing value.
- Shared presentation lives in `widgets/stats_common.dart`: `SectionCard`, `StatTile`,
  `StatTileGrid` (2 columns under 640 px, 4 above), `HeroStat`, `StatLine`, `RankBadge`, `GoldenScoreChip`,
  `MiniStat` and `StatsColors` — the green/red/purple/cyan accents of the React screens,
  kept out of `utils/app_theme.dart` because they belong to these screens only.
- **Every text beside another in a `Row` is `Flexible`**: a name, a figure or a label that
  is unconstrained overflows on a 360 px phone as soon as the system font is large — the
  standings' ZapZap record, the tiles' facts, the legend items, the leaderboard's win-rate
  column and the personal ZapZap header. In `SectionCard` the trailing badge is `Flexible`
  too, and `GoldenScoreChip` ellipsizes: with `Expanded` on the title alone the badge takes
  what it asks for, squeezes the title into a column of single letters and is clipped
  anyway. `test/history_screens_test.dart` and `test/stats_screen_test.dart` each end on a
  `phone width` group at 360×740, at text scale 1, 1.5 and 2.0, scrolling to every card so
  it really lays out; an overflow is a layout error, which fails the test. At 2.0 the
  standings score is `Flexible` beside the name (alone it took the whole row), the rounds
  table's rows have no maximum height (`dataRowMaxHeight: double.infinity`, a fixed 76
  clipped a cell) and the winner label wraps beside its icon.
- **Text scale**: every screen is pinned at 360×740 at text scales 1.5 and 2.0, the
  largest Android offers. The screens with no phone group of their own — home, splash,
  login, register, not-found and the game screen's loading, load-failed and "not started"
  states — are in `test/text_scale_test.dart`, which also checks their key controls lie
  inside the screen: a clip inside a fixed-size box raises no overflow error.

### Admin (`screens/admin_screen.dart`, `widgets/admin_*.dart`)

Ported from the React client's `components/Admin/{AdminRoute,AdminLayout}.jsx` and
`Users/UserList.jsx`, `Parties/AdminPartyList.jsx`, `Statistics/AdminStats.jsx` (removed on
2026-09-29, [[Frontend]]).

- **Routes** (`lib/router.dart`): `/admin` opens the Users tab; `/admin/users`,
  `/admin/parties`, `/admin/statistics` (`AppRoutes.adminTab(AdminTab)`) open that tab, any
  other `/admin/<x>` is the not-found screen. `authRedirect` sends a session without
  `isAdmin` to `/parties` before any of them builds. The guard is cosmetic: the backend
  refuses every `/api/admin` call to a non-admin ([[Api]]).
- **`AdminScreen`**: `ZapZapAppBar` with a back button (`popOrGo(/parties)`), then a
  scrollable `TabBar` (Users, Parties, Statistics — keys `admin-tab-*`; in the content
  column, its first label in line with the content) over an
  `IndexedStack`. A tab is built, and loads, the first time it shows (`_opened`), then
  stays alive, so the users list keeps its page and search and the parties their filter
  while another tab shows. A tab change does not change the URL.
- **Shared** (`widgets/admin_common.dart`): `adminErrorText` (400 → "Action refusée",
  `ADMIN_REQUIRED`/403, 404, no answer; a tab passes its own `refused`/`notFound` texts),
  `confirmAdminAction` (the `AlertDialog`, `admin-confirm-ok`; cancel or a tap outside is
  false and sends nothing), `AdminPager` (Previous / `first–last sur total` / Next, keyed
  `<prefix>-previous`, `-range`, `-next`).
- **`AdminUsersView`**: `GET /admin/users?limit=50&offset=` (`AdminUsersView.pageSize`),
  the total, a search field (`admin-users-search`) that filters the page on show by
  username, case-insensitively, as React does; Previous / `first–last sur total` / Next
  (`admin-users-previous`, `-range`, `-next`) when the total passes 50. A row
  (`AdminUserTile`, `admin-user-<id>`): name, a "Toi" badge on one's own, an Admin badge,
  created, last login ("Jamais connecté" when null), games and play time (`2h 5m`, React's
  format). Toggle admin (`admin-toggle-<id>`) and delete (`admin-delete-<id>`) show on
  every row but one's own and `admin`'s (`AdminUsersView.defaultAdmin`; the backend refuses
  to delete oneself or any admin, `zapzap-rust/src/api/routes/admin.rs`); each asks first in an
  `AlertDialog` (`admin-confirm-ok`), then posts and reloads the page. A refusal is a snack
  bar and the list stays: `adminErrorText` maps 400 (the code-less refusal for oneself
  or an admin) to "Action refusée", `ADMIN_REQUIRED`/403, 404 and no answer to
  their texts. A failed first load is an `ErrorBanner` with Retry. A deleted last row of a
  later page goes back a page.
- **`AdminPartiesView`** (`widgets/admin_parties.dart`): `GET
  /admin/parties?limit=50&offset=` plus `status=` when a filter chip is on
  (`admin-parties-filter-{all,waiting,playing,finished}`; the backend filters, and a new
  filter goes back to the first page), the total (`admin-parties-count`), the pager past 50,
  pull-to-refresh. A row (`AdminPartyTile`, `admin-party-<id>`): name, a status badge in
  React's colours, the invite code, the owner, `Joueurs : 3 / 5 · Publique` — the seats
  are `playerCount / settings.playerCount`, the settings a JSON string decoded by
  `PartySettings.fromJson`, `?` when they name no player count (`AdminPartyTile.seats`) —
  and the creation date. Stop (`admin-party-stop-<id>`, not on a finished party) and delete
  (`admin-party-delete-<id>`) ask first (`admin-party-stop-confirm`,
  `admin-party-delete-confirm`), then post and reload; a refusal is a snack bar (400 →
  "Action refusée pour cette partie", 404 → the party-not-found text).
- **`AdminStatisticsView`** (`widgets/admin_stats.dart`): `GET /admin/statistics` once, and
  on pull-to-refresh. Four `StatTile`s in a `StatTileGrid` (users, parties, rounds,
  completion rate — `Formats.number` then `%`, since Rust does not round it), the breakdown by status (`admin-stats-{waiting,playing,finished}`), the chart
  card, the most active players (`admin-stats-user-<id>`: `RankBadge`, name, games · wins ·
  win rate), each with its empty text. A failed load is an `ErrorBanner` with Retry.
- **The chart** (`DailyGamesChart`, `DailyGamesPainter`): `DailyGamesChart.lastDays` turns
  `gamesOverTime.daily` — only the UTC days that had a finished game, at most 30 — into the
  last 30 UTC days up to today, oldest first, missing days at 0. The painter draws a
  four-step grid with its scale, one bar per day (a 2 px stub for a day without games, so
  the 30 slots show), the count above a bar when bars are 12 px wide or more, and `dd/MM`
  under every fifth day and the last; its text follows the text scale. The chart is one
  semantics node ("N parties terminées sur les 30 derniers jours"). When the 30 days hold
  no game — always the case today: Rust sends `daily: []` (`zapzap-rust/src/api/routes/admin.rs`) — the card says "Pas assez de
  données" instead.

## Decisions & History

- **Node's `GET /history` sends the caller's place and score (2026-09-24,
  `fix/node-history-user-placement`).** The Rust parity fields were missing on the backend
  production runs, so a lost game showed no place. `getFinishedGamesForUser` already joined
  `player_game_results`; the use case now maps `user_position`/`user_final_score`. The
  fixture was regenerated from a local Node (`PORT=9911`) on a database seeded with the
  fixture game's ids and scores, not from a replayed game.
- **History and statistics (2026-09-22, `feat/flutter-history`).** One `AsyncSection` per
  read rather than one loading state per screen: the statistics screen asks three
  independent endpoints and React hides all three behind three flags anyway. The bot
  difficulties come from the answer instead of React's hard-coded list of eight, so a bot
  kind the backend adds appears on its own; only the name, strategy and colour are looked
  up, with a fallback. `StatsColors` sits with the screens rather than in `AppTheme`: they
  are the only users, and the theme is shared with the game board. The leaderboard marks
  the signed-in row, as React does. Review found six rows that overflowed a 360 px phone —
  two of them without any text scaling — so every text beside another in a `Row` became
  `Flexible` and the screens gained a `phone width` test group, as the lobby screens have.
- **The admin shell and its users tab (2026-09-24, `feat/flutter-admin-users`).** One
  screen with a `TabBar` rather than a `ShellRoute` per tab: the tabs share nothing but
  the header, and a `go` between shell routes would replace the stack the Android Back
  needs. `/admin/<tab>` exists for deep links only; the URL does not follow a tab change,
  because replacing the route would rebuild the users list and lose its page. Rows are
  cards, not React's 800 px table, so a phone needs no horizontal scroll. The search
  filters the page on show, as React's does, since `GET /admin/users` has no search
  parameter. The client hides the actions on the default admin by name, as React does;
  the backend refuses them anyway. Checked with a throwaway `flutter drive` test against a
  local Node backend on a scratch database: signed in as `admin`, the menu's Admin entry,
  Vincent granted admin then revoked, the badge following each time.
- **The admin parties and statistics tabs (2026-09-24, `feat/flutter-admin-parties-stats`).**
  Tabs now build on first show: with all three built at once, opening `/admin` fired three
  admin calls for one tab on screen. The status filter is chips rather than React's
  `<select>`: four short choices fit a phone and need one tap. The chart spans 30 calendar
  days rather than React's "the 30 days that had games", so its x axis is time and a quiet
  week shows as one. The confirm dialog and the pager moved to `admin_common.dart` when a
  second tab needed them. Checked against the local Rust backend on a scratch database:
  `AdminRepository.stopParty` on a playing party moved it to finished (7 playing → 6), and
  the captured Rust answers (settings without `playerCount`, so `3 / ?`; `daily: []`)
  render at 360×740 at 1.5.
- **History and statistics put my own result first (2026-09-23, `feat/flutter-history-ux`).**
  The UX study (H1–H3, St1, St2) found the history row said who won but not how I did, the
  history and the statistics linked only through the menu, an empty list said nothing to
  do, and six equal tiles made nothing stand out. The texts keep the app's "vous", not the
  mockup's "tu" (outdated: "tu" everywhere since 2026-09-23). The summary's games and wins come from `/stats/me` rather than the
  history, which is one page of entries (Node answers 20 by default).
