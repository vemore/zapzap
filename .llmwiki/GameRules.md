# GameRules

> Scope: where the ZapZap rules (`GAME_RULES.md` at repo root = the reference) are implemented in the Rust backend, and where code and doc disagree.
> Related: [[Bots]] · [[Backend]] · [[Api]] · [[NativeEngine]]
> Updated: 2026-09-22

## Facts

### Reference
- `GAME_RULES.md` is the human rules reference (card values, combinations, turn flow, round start, empty deck, ZapZap eligibility, scoring, elimination, Golden Score). Keep it; this page only maps rules to code.
- Rules live in three Rust layers: `zapzap-rust/src/infrastructure/bot/card_analyzer.rs` (card math, validation), `zapzap-rust/src/domain/services/game_service.rs` (state transitions, scoring), `zapzap-rust/src/application/game/*.rs` (turn/phase checks, persistence). `native/src/card_analyzer.rs` + `headless_engine.rs` re-implement the same rules for training ([[NativeEngine]]).

### Cards
| Rule | Code |
|---|---|
| 54 cards, ids 0-53, deck `(0..54)` | `game_service.rs:37` |
| Joker = id ≥ 52 (`JOKER_START`) | `card_analyzer.rs:9`, `:45-47` |
| Suit = id / 13 (0 S, 1 H, 2 C, 3 D), rank = id % 13 | `card_analyzer.rs:27-42`; suit letters `zapzap-rust/src/infrastructure/bot/strategies/llm_bot.rs:21` |
| Points A=1 … K=13, Joker 0 (eligibility) | `card_analyzer.rs:12-23`, `calculate_hand_value` `:52-54` |
| Joker = 25 at scoring unless holder has the lowest hand | `calculate_hand_score` `card_analyzer.rs:58-73` |

### Combinations
- `is_valid_play`: 1 card always valid; ≥2 cards must be same-rank or sequence (`card_analyzer.rs:147-153`).
- Same rank: ≥2 cards, all non-jokers share a rank, jokers wild; all-joker sets are valid (`card_analyzer.rs:81-100`). So "5 + Joker" is a valid pair (the doc only shows a joker as third card).
- Sequence: ≥3 cards, one suit, jokers fill gaps (`gaps_needed <= joker_count`); no Ace-high wrap (`card_analyzer.rs:103-144`).
- **No duplicate-id check** anywhere: `is_valid_play` accepts `[c, c]` (same rank) or `[c, c, c]` (a "sequence": sorted diffs are −1, gaps 0), and `execute_play` checks each id with `hand.contains` before removing (`game_service.rs:76-88`) and copies the raw list into `cards_played` (`:99-106`). A client posting `cardIds: [c, c, c]` removes one card but puts three copies on the table. Entry: `zapzap-rust/src/application/game/play_cards.rs:74-79`.
- Play enumeration for bots: `find_same_rank_plays` (`card_analyzer.rs:156`, jokers added up to 4-card sets), `find_sequence_plays` (`:203`), `find_all_valid_plays` (`:266`).

### Round start
- Party start: 3-8 players (`zapzap-rust/src/domain/entities/party.rs:105-107`); round 1, player index 0 starts (`zapzap-rust/src/application/party/start_party.rs:66-74`).
- `initialize_round` deals `party.settings.hand_size` (default 5, clamped 4-7, `zapzap-rust/src/domain/value_objects/party_settings.rs:20`, `:31`) and sets phase `SelectHandSize` (`game_service.rs:13-60`); this deal is thrown away by the next step.
- `SelectHandSize`: only the current player; 4-7 cards, 4-10 in Golden Score (`zapzap-rust/src/application/game/select_hand_size.rs:61-64`); gathers all cards, reshuffles, deals, then flips one card to `last_cards_played` (`:77-114`); phase → Play.
- Next round: starter = `(starting_player + 1) % player_count` (`zapzap-rust/src/application/game/next_round.rs:175`) — **does not skip eliminated players**, contrary to `GAME_RULES.md:86`. Eliminated bots are skipped later by the bot loop (`zapzap-rust/src/api/routes/game.rs:1395-1411`); an eliminated **human** starter is not skipped, so the round waits on a player who cannot act.

### Turn flow
- Phases `SelectHandSize → Play → Draw → Play…`, terminal `Finished` (`zapzap-rust/src/domain/value_objects/game_state.rs:17-24`).
- Play: must be current player and phase Play (`play_cards.rs` via `execute_play`, `game_service.rs:64-117`); non-empty (`play_cards.rs:71`). First play of a round keeps the flipped card drawable; later plays push the previous `last_cards_played` to `discard_pile` and make the previous player's cards drawable (`game_service.rs:95-106`). The player draws from the *previous* player's cards, never their own.
- Draw: phase Draw only (`game_service.rs:120-126`); `source == "played"` means discard, anything else deck (`zapzap-rust/src/application/game/draw_card.rs:71`); taking from discard records it in `card_tracker` (`game_service.rs:139`).
- Empty deck: `discard_pile` (not `last_cards_played`) is reshuffled into the deck; both empty → error "No cards to draw" (`game_service.rs:143-149`). Matches `GAME_RULES.md:99-113`.
- Turn advance skips eliminated players (`game_state.rs:395-403`, called `game_service.rs:163`).

### ZapZap
- Allowed only in phase Play, on your turn, hand value ≤5 with Joker = 0 (`zapzap-rust/src/application/game/call_zapzap.rs:70-83`, `card_analyzer.rs:76-78`, re-checked `game_service.rs:174`).
- Counteract: any active opponent with value ≤ running minimum (ties included) counteracts; the last such player in index order becomes `counteracted_by` / lowest hand (`game_service.rs:181-193`).
- Scores (`game_service.rs:205-228`): lowest hand 0; others `calculate_hand_score` (Joker 25); counteracted caller = hand score + (active_players − 1) × 5 (`:219`). Players tied at the lowest value other than the chosen one get their full hand score (doc implies all "lowest" get 0).
- Round end state (`zapzap_caller`, `lowest_hand_player_index`, `round_scores`…) stored and phase → Finished (`game_service.rs:236-249`); per-player `round_scores` rows saved (`call_zapzap.rs:108-145`).

### Elimination, game end, Golden Score
- Eliminated when total score > 100 (`game_service.rs:265-277`), checked right after ZapZap (`call_zapzap.rs:90`).
- Golden Score flag = exactly 2 active players at round init (`game_service.rs:58`).
- Game over (`game_service.rs:285-302`): one active player left, or Golden Score round finished → winner = `lowest_hand_player_index` (caller loses ties because ties counteract). Matches `GAME_RULES.md:170-198`; unit tests `game_service.rs:338-400`.
- Final ranking: winner, then non-eliminated by score, then eliminated by later elimination round (`call_zapzap.rs:182-201`; duplicated in `next_round.rs:105-124`).

### Doc vs code
| `GAME_RULES.md` | Code | Verdict |
|---|---|---|
| "party owner starts" (`:80`) | player index 0 (`start_party.rs:73`) | same if owner is index 0 |
| subsequent starter skips eliminated (`:86`, `:94`) | no skip (`next_round.rs:175`) | **code wrong** |
| all lowest hands score 0 (`:130-131`) | only one tied player gets 0 (`game_service.rs:189`, `:222`) | ambiguous, code stricter |
| valid combos (`:17-49`) | also joker pairs, all-joker plays, duplicate ids | code more permissive; duplicates are a bug |
| LLM prompt "+20 points penalty" | (active−1)×5 (`game_service.rs:219`) | prompt wrong (`llm_bot.rs:100`) |

## Decisions & History
- Counteract penalty was changed to depend on active players in 15570c2 (2025-12-15, "correct zapzap caller score calculation to account for active players").
- Golden Score first implemented d5df375 (2025-12-18) then switched to "lowest hand wins, not lowest total" in ec13b2b (2025-12-21); starting-player rotation added 4ee11f8 (2025-12-20) — all in the Node backend, ported in e4f83da (2025-12-23).
- The Node backend at one point allowed drawing during the play phase (729aad8, 2025-12-04); the Rust port enforces play-then-draw (`game_service.rs:121-123`), as `GAME_RULES.md:72-74` states.
