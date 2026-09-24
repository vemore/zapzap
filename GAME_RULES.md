## 🎮 Complete Game Rules

### Card Values

| Card | Points | Notes |
|------|--------|-------|
| Ace (A) | 1 | Lowest value |
| 2-10 | Face value | |
| Jack (J) | 11 | Face card |
| Queen (Q) | 12 | Face card |
| King (K) | 13 | Highest value |
| **Joker (in play)** | **0** | **For ZapZap eligibility** |
| **Joker (penalty)** | **25** | **For final scoring** |

### Valid Card Combinations

#### ✅ Valid Plays

```
Single Card:
  5♠

Pairs (Same Rank):
  K♠ K♥
  A♠ A♥ A♣ A♦
  6♠ 6♥ 🃏 (Joker as third 6)

Sequences (Same Suit, 3+ consecutive):
  5♠ 6♠ 7♠
  10♣ J♣ Q♣ K♣
  2♥ 3♥ 4♥ 5♥ 6♥

Sequences with Jokers:
  5♠ 🃏 7♠ (Joker = 6♠)
  10♣ J♣ 🃏 K♣ (Joker = Q♣)
```

#### ❌ Invalid Plays

```
Mixed Suits in Sequence:
  5♠ 6♥ 7♣ (different suits)

Non-Consecutive Sequence:
  5♠ 7♠ 9♠ (missing 6♠ and 8♠)

Sequence with Only 2 Cards:
  5♠ 6♠ (need minimum 3 cards)
```

### Turn Flow

Each player's turn consists of **two mandatory phases** in sequence:

```
┌─────────────────────────────────────────────────────────────┐
│                     PLAYER'S TURN                           │
├─────────────────────────────────────────────────────────────┤
│  1️⃣ PLAY PHASE                                              │
│     → Play one or more cards (single, pair, or sequence)    │
│     → Cards go to the "last played" pile (visible)          │
│                                                             │
│  2️⃣ DRAW PHASE                                              │
│     → Draw ONE card from:                                   │
│        • Deck (face-down, unknown)                          │
│        • Last played cards (visible, choose any one)        │
│                                                             │
│  → Turn passes to next player                               │
└─────────────────────────────────────────────────────────────┘
```

**Important:**
- You **must** play before you can draw
- You **must** draw to end your turn
- You can call **ZapZap** during the play phase (instead of playing cards)

### Round Start

#### First Round
- The **party owner** (first player to join) starts the game
- The starting player chooses the **hand size** (4-7 cards, or 4-10 in Golden Score)
  — never more than the deck can deal to every active player while leaving a card to
  flip: at most (54 − 1) ÷ players, so **6 with 8 players**
- Cards are dealt to all players
- **One card is flipped** from the deck to the discard pile (visible for drawing)

#### Subsequent Rounds
- The **next player** in rotation starts (circular, skipping eliminated players)
- The starting player again chooses the hand size
- One card is flipped to start the discard pile

```
Round 1: Player 0 starts → selects hand size → cards dealt
Round 2: Player 1 starts → selects hand size → cards dealt
Round 3: Player 2 starts → ...
(If Player 2 is eliminated, Player 3 starts instead)
```

### Empty Deck

When the **deck runs out** of cards:

1. The **discard pile is shuffled** automatically
2. It becomes the **new deck**
3. The game continues seamlessly

```
┌──────────────────────────────────────────────────────────┐
│  Deck empty?                                             │
│  ├─ Discard pile has cards → Shuffle → New deck          │
│  └─ Discard pile also empty → Error (extremely rare)     │
└──────────────────────────────────────────────────────────┘
```

**Note:** The "last played" cards remain available for drawing and are NOT included in the reshuffle.

### ZapZap Eligibility

Your hand must be **5 points or less** (calculated **without** Joker penalty):

| Hand | Calculation | Eligible? |
|------|-------------|-----------|
| A♠, 2♥, 2♣ | 1 + 2 + 2 = 5 | ✅ Yes |
| Joker, 3♦, 2♠ | 0 + 3 + 2 = 5 | ✅ Yes |
| A♠, A♥, A♣, A♦, Joker | 1+1+1+1+0 = 4 | ✅ Yes |
| 3♠, 3♥ | 3 + 3 = 6 | ❌ No |

### Final Scoring

```javascript
// Standard scoring
if (player has lowest hand) {
  score = 0
} else {
  score = hand_points_with_joker  // Jokers = 25
}

// Counteract penalty
if (zapzap_called && someone_has_lower_or_equal) {
  zapzap_caller_score = hand_points_with_joker + ((active_players - 1) × 5)
}
```

**Ties:** when several players share the lowest hand value, **every one of them** scores 0.
A counteracted ZapZap caller still takes the penalty above, even when tied for the lowest.
(Golden Score ties: see below.)

**Example Scoring:**

```
Game with 5 players:
Player 0: A♠, 2♥, 3♣ = 6 points
Player 1: Joker, A♦ = 1 point (0 + 1)
Player 2: A♥, A♣, 2♠ = 4 points → Calls ZapZap!
Player 3: K♠, Q♥ = 25 points
Player 4: 5♦, 5♣ = 10 points

Result:
- Player 1 has lowest (1 point)
- Player 2 called ZapZap but Player 1 is lower → Counteracted!

Final Scores:
Player 0: 6 points
Player 1: 0 points (lowest, but note: Joker now worth 25 if counted)
Player 2: 24 points (4 + ((5 - 1) × 5) = 24 points penalty!)
Player 3: 25 points
Player 4: 10 points
```

### Game Elimination

- Players above **100 points** are eliminated (dead)
- Last 2 players alive: "Golden Score" final round
- Winner: Last player alive (≤100 points)

### Golden Score Rules

When only 2 players remain, the game enters **Golden Score mode**:

1. **Winner Determination**: The winner of the Golden Score round is the player with the **lowest hand value** (not the lowest total score)
2. **ZapZap Counteract Rule**: If the ZapZap caller is counteracted (including ties), they **lose the game**
3. **Tie Handling**: If both players have equal hand values, the ZapZap caller loses (they were counteracted)

**Example:**
```
Golden Score round:
Player 0: Hand = Ace (1 point), Total Score = 98
Player 1: Hand = 2+3 (5 points), Total Score = 85

Player 0 calls ZapZap.
Result: Player 0 wins because they have the lowest hand (1 < 5),
        even though Player 1 has a lower total score (85 < 98).
```

**Tie Example:**
```
Golden Score round:
Player 0: Hand = Ace+2 (3 points)
Player 1: Hand = Ace+2 (3 points)

Player 0 calls ZapZap.
Result: Player 1 wins because Player 0 called ZapZap but was
        counteracted (hands are equal), so the caller loses.
```