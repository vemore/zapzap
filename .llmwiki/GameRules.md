# GameRules

> Scope: where the ZapZap rules (`GAME_RULES.md` at repo root = the reference) are implemented in the Rust backend, and where code and doc disagree.
> Related: [[Bots]] · [[Backend]] · [[Api]] · [[NativeEngine]]
> Updated: 2026-09-24

## Facts

### Reference
- `GAME_RULES.md` is the human rules reference (card values, combinations, turn flow, round start, empty deck, ZapZap eligibility, scoring, elimination, Golden Score). Keep it; this page only maps rules to code.
- Rules live in three Rust layers: `zapzap-rust/src/infrastructure/bot/card_analyzer.rs` (card math, validation), `zapzap-rust/src/domain/services/game_service.rs` (state transitions, scoring), `zapzap-rust/src/application/game/*.rs` (turn/phase checks, persistence). `native/src/card_analyzer.rs` + `headless_engine.rs` re-implement the same rules for training ([[NativeEngine]]).

### Cards
| Rule | Code |
|---|---|
| 54 cards, ids 0-53, deck `(0..54)` | `game_service.rs:40` |
| Joker = id ≥ 52 (`JOKER_START`) | `card_analyzer.rs:9`, `:45-47` |
| Suit = id / 13 (0 S, 1 H, 2 C, 3 D), rank = id % 13 | `card_analyzer.rs:27-42`; suit letters `zapzap-rust/src/infrastructure/bot/strategies/llm_bot.rs:21` |
| Points A=1 … K=13, Joker 0 (eligibility) | `card_analyzer.rs:12-23`, `calculate_hand_value` `:52-54` |
| Joker = 25 at scoring unless holder has the lowest hand | `calculate_hand_score` `card_analyzer.rs:58-73` |

### Combinations
- `is_valid_play`: 1 card always valid; ≥2 cards must name each card once (`first_repeated_card`, also used by `PlayCards`) and be same-rank or sequence (`card_analyzer.rs`).
- Same rank: ≥2 cards, all non-jokers share a rank, jokers wild; all-joker sets are valid (`card_analyzer.rs:81-100`). So "5 + Joker" is a valid pair (the doc only shows a joker as third card).
- Sequence: ≥3 cards, one suit, jokers fill gaps (`gaps_needed <= joker_count`); no Ace-high wrap (`card_analyzer.rs:103-144`).
- A card named twice is refused: `PlayCards` answers 400 `INVALID_CARDS` ("Card c played more than once", `PlayCardsError::RepeatedCard`, `zapzap-rust/src/application/game/play_cards.rs`) before any other card check, and `is_valid_play` refuses it too, so `execute_play` never sees one. Before 2026-09-24 `[c, c, c]` passed as a sequence and put three copies of one card on the table. Node still accepts it (`src/use-cases/game/PlayCards.js`; parity item `invariant:illegal.repeated-card-refused@node`). Tests `test_repeated_card_is_no_valid_play` (`card_analyzer.rs`), `test_play_naming_a_card_twice_is_refused_and_plays_nothing` (`zapzap-rust/tests/rules_and_bots_tests.rs`).
- Clients re-check a selection before posting it: React `frontend/src/utils/validation.js`, Flutter `frontend-flutter/lib/utils/rules.dart` (which also refuses a repeated id). [[FrontendFlutter]]
- Play enumeration for bots: `find_same_rank_plays` (`card_analyzer.rs:156`, jokers added up to 4-card sets), `find_sequence_plays` (`:203`), `find_all_valid_plays` (`:266`).

### Round start
- Party start: 3-8 players (`zapzap-rust/src/domain/entities/party.rs:106-109`); round 1, player index 0 starts (`zapzap-rust/src/application/party/start_party.rs:66-74`).
- `initialize_round` deals `PROVISIONAL_HAND_SIZE` (5, `zapzap-rust/src/domain/value_objects/game_state.rs:14`; the hand size is not a party setting) and sets phase `SelectHandSize` (`game_service.rs:13-60`); this deal is thrown away by the next step.
- `SelectHandSize`: only the current player; 4-7 cards, 4-10 in Golden Score, and never more than the deck can deal with one card left to flip: at most (54 − 1) / active players, so 6 with 8 players (`hand_size_bounds`, `game_service.rs`; 400 `INVALID_HAND_SIZE` otherwise, test `test_hand_size_fits_the_deck_with_eight_players`). Node does not check the deck and deals short hands; gathers all cards, reshuffles, deals, then flips one card to `last_cards_played` (`:77-114`); phase → Play.
- Next round: starter = `next_starting_player` (`zapzap-rust/src/application/game/next_round.rs`), the seat after this round's starter, clockwise, skipping eliminated seats, as `GAME_RULES.md` "Subsequent Rounds" says; the starter picks the hand size and eliminated seats get no cards. Tests: unit tests in `next_round.rs`, `test_eliminated_player_never_starts_a_round` and `test_starter_rotation_wraps_to_seat_zero` (`zapzap-rust/tests/rules_and_bots_tests.rs`).

### Turn flow
- Phases `SelectHandSize → Play → Draw → Play…`, terminal `Finished` (`zapzap-rust/src/domain/value_objects/game_state.rs:17-27`).
- Play: must be current player and phase Play (`play_cards.rs` via `execute_play`, `game_service.rs:67-128`); non-empty (`play_cards.rs:71`). First play of a round keeps the flipped card drawable; later plays push the previous `last_cards_played` to `discard_pile` and make the previous player's cards drawable (`game_service.rs:105-115`). The player draws from the *previous* player's cards, never their own.
- Draw: phase Draw only (`game_service.rs:136-138`); `source == "played"` means discard, anything else deck (`zapzap-rust/src/application/game/draw_card.rs:71`); taking from discard records it in `card_tracker` (`game_service.rs:151`).
- Empty deck: `discard_pile` (not `last_cards_played`) is reshuffled into the deck; both empty → error "No cards to draw" (`game_service.rs:155-164`). Matches `GAME_RULES.md:99-113`.
- Turn advance skips eliminated players (`game_state.rs:508-516`, called `game_service.rs:183`).

### ZapZap
- Allowed only in phase Play, on your turn, hand value ≤5 with Joker = 0 (`zapzap-rust/src/application/game/call_zapzap.rs:70-83`, `card_analyzer.rs:76-78`, re-checked `game_service.rs:215`).
- Counteract: any active opponent with value ≤ running minimum (ties included) counteracts; the last such player in index order becomes `counteracted_by` / lowest hand (`game_service.rs:227-235`).
- Scores (`execute_zapzap`, `game_service.rs`): **every** active player whose hand value equals the lowest scores 0 (a Joker in a lowest hand counts 0); others `calculate_hand_score` (Joker 25); a counteracted caller = hand score + `counteract_penalty(active players)` = (active − 1) × `COUNTERACT_PENALTY_PER_OPPONENT` (5), even when tied at the lowest. As Node (`src/use-cases/game/CallZapZap.js`). `lowest_hand_player_index` / `counteracted_by` still name one player (the last of the tied, in seat order). Tests `test_tied_lowest_hands_all_score_zero` (`game_service.rs` and `rules_and_bots_tests.rs`), `test_counteracted_caller_tied_at_lowest_still_takes_the_penalty`.
- Round end state (`zapzap_caller`, `lowest_hand_player_index`, `round_scores`…) stored and phase → Finished (`game_service.rs:284-296`); per-player `round_scores` rows saved (`call_zapzap.rs:108-145`).

### Elimination, game end, Golden Score
- Eliminated when total score > 100 (`game_service.rs:312-323`), checked right after ZapZap (`call_zapzap.rs:90`).
- Golden Score flag = exactly 2 active players at round init (`game_service.rs:61`).
- Game over (`game_service.rs:332-350`): one active player left, or Golden Score round finished → winner = `lowest_hand_player_index` (caller loses ties because ties counteract). Matches `GAME_RULES.md:170-198`; unit tests `game_service.rs:384-429`.
- Final ranking: winner, then non-eliminated by score, then eliminated by later elimination round (`call_zapzap.rs:182-201`; duplicated in `next_round.rs:105-124`).

### Doc vs code
| `GAME_RULES.md` | Code | Verdict |
|---|---|---|
| "party owner starts" (`:80`) | player index 0 (`start_party.rs:73`) | same if owner is index 0 |
| subsequent starter skips eliminated | `next_starting_player` skips them | agree (fixed 2026-09-24) |
| all lowest hands score 0, ties included | every tied lowest hand scores 0 | agree (fixed 2026-09-24) |
| valid combos (`:17-49`) | also joker pairs, all-joker plays | code more permissive; repeated ids refused since 2026-09-24 |
| LLM prompt penalty | built from `COUNTERACT_PENALTY_PER_OPPONENT` | agree (fixed 2026-09-24) |

## Decisions & History
- 2026-09-24 (fix/rust-rules-and-bots): the three places where the Rust code disagreed with `GAME_RULES.md` were fixed — the eliminated starter, the tied lowest hands (decided 2026-09-22: every tied player scores 0, as Node does; `GAME_RULES.md` "Final Scoring" now says so outright) and the repeated card in a play. The parity suite's `invariant:*@rust` items for them were removed from `tests/parity/divergences.json`.
- Counteract penalty was changed to depend on active players in 15570c2 (2025-12-15, "correct zapzap caller score calculation to account for active players").
- Golden Score first implemented d5df375 (2025-12-18) then switched to "lowest hand wins, not lowest total" in ec13b2b (2025-12-21); starting-player rotation added 4ee11f8 (2025-12-20) — all in the Node backend, ported in e4f83da (2025-12-23).
- The Node backend at one point allowed drawing during the play phase (729aad8, 2025-12-04); the Rust port enforces play-then-draw (`game_service.rs:136-138`), as `GAME_RULES.md:72-74` states.
