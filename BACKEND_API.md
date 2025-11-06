# ZapZap Backend API Documentation

**Version:** 1.0.0
**Base URL:** `http://localhost:9999`
**Protocol:** HTTP/1.1
**Real-time Updates:** Server-Sent Events (SSE)

---

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Common Response Codes](#common-response-codes)
- [Error Response Format](#error-response-format)
- [Endpoints](#endpoints)
  - [GET /party](#get-party)
  - [GET /player/:id/hand](#get-playeridhhand)
  - [GET /player/:id/play](#get-playeridplay)
  - [GET /player/:id/draw](#get-playeriddraw)
  - [GET /player/:id/zapzap](#get-playeridzapzap)
  - [GET /suscribeupdate](#get-suscribeupdate)
- [Card ID System](#card-id-system)
- [Game State Machine](#game-state-machine)
- [Point Calculation](#point-calculation)
- [Examples](#examples)

---

## Overview

The ZapZap API provides endpoints for managing a multiplayer card game. The API is designed around a turn-based game flow where players draw cards, play combinations, and call "ZapZap" to end rounds.

**Key Concepts:**
- **Turn-based**: Players take turns sequentially (0 → 1 → 2 → 3 → 4 → 0...)
- **Action States**: Each turn has phases (DRAW → PLAY)
- **Real-time**: Server-Sent Events push updates to all connected clients
- **Stateful**: Game state is maintained server-side in memory

---

## Authentication

> ⚠️ **Warning:** The current implementation has **NO AUTHENTICATION**.
> Anyone with the URL can perform actions as any player.
> This is a known security issue (see [AUDIT_REPORT.md](AUDIT_REPORT.md#1-no-turn-validation-in-api-endpoints)).

**Planned for v2.0:**
- Session-based authentication
- JWT tokens
- WebSocket with authentication

---

## Common Response Codes

| Code | Status | Meaning |
|------|--------|---------|
| `200` | OK | Request succeeded |
| `400` | Bad Request | Invalid input parameters |
| `403` | Forbidden | Not your turn or invalid action state |
| `404` | Not Found | Resource doesn't exist |
| `500` | Internal Server Error | Server error |

---

## Error Response Format

**Current Implementation:**
Most endpoints return `200 OK` even on failure (⚠️ this is a bug).

**Planned Error Format (v1.1):**
```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE_CONSTANT",
  "details": {
    "field": "Additional context"
  }
}
```

**Error Codes:**
- `INVALID_PLAYER_ID`: Player ID out of bounds or invalid
- `INVALID_TURN`: Not the player's turn
- `INVALID_ACTION_STATE`: Action not allowed in current state
- `INVALID_CARD_COMBINATION`: Cards don't form a valid play
- `CARD_NOT_IN_HAND`: Attempted to play card not in player's hand
- `CARD_NOT_AVAILABLE`: Attempted to draw unavailable card
- `INVALID_ZAPZAP`: Hand value too high for ZapZap

---

## Endpoints

### GET /party

Get complete game state including all players, current turn, and played cards.

#### Request

```http
GET /party HTTP/1.1
```

**No parameters required.**

#### Response

```json
{
  "nb_players": 5,
  "current_turn": 12,
  "card_in_deck": 34,
  "last_cards_played": [12, 25, 38],
  "cards_played": [7],
  "players": [
    {
      "name": "Vincent",
      "nb_cards": 9
    },
    {
      "name": "Thibaut",
      "nb_cards": 10
    },
    {
      "name": "Simon",
      "nb_cards": 11
    },
    {
      "name": "Lyo",
      "nb_cards": 10
    },
    {
      "name": "Laurent",
      "nb_cards": 9
    }
  ],
  "action": "draw"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `nb_players` | number | Total number of players (always 5) |
| `current_turn` | number | Absolute turn counter (increments each turn) |
| `card_in_deck` | number | Number of cards remaining in draw pile |
| `last_cards_played` | array | Card IDs from previous player's discard (drawable) |
| `cards_played` | array | Card IDs just played this turn (not yet drawable) |
| `players` | array | Player information (name, card count) |
| `action` | string | Current game state: `"draw"`, `"play"`, or `"zapzap"` |

**Action States:**

- `"draw"`: Waiting for player to draw a card
- `"play"`: Waiting for player to play cards
- `"zapzap"`: Round ended, scores are displayed

**During ZapZap State:**

When `action === "zapzap"`, the response includes additional fields:

```json
{
  "nb_players": 5,
  "current_turn": 12,
  "card_in_deck": 34,
  "last_cards_played": [],
  "cards_played": [],
  "players": [
    {
      "name": "Vincent",
      "nb_cards": 9,
      "hand": [0, 5, 12, 18, 23, 28, 33, 38, 52],
      "score": 48
    },
    // ... other players with hand and score
  ],
  "action": "zapzap"
}
```

---

### GET /player/:id/hand

Get a specific player's hand as an array of card IDs.

#### Request

```http
GET /player/2/hand HTTP/1.1
```

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | number | Player ID (0-4) |

#### Response

```json
[0, 5, 12, 18, 23, 28, 33, 38, 52]
```

**Response:** Array of card IDs (see [Card ID System](#card-id-system))

#### Examples

```bash
# Get Player 0's hand
curl http://localhost:9999/player/0/hand

# Get Player 3's hand
curl http://localhost:9999/player/3/hand
```

#### Errors

| Status | Condition |
|--------|-----------|
| `400` | Player ID is invalid (not 0-4) |
| `404` | Player not found |

---

### GET /player/:id/play

Play cards from the player's hand.

#### Request

```http
GET /player/2/play?cards=0,13,26 HTTP/1.1
```

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | number | Player ID (0-4) |

**Query Parameters:**

| Parameter | Type | Description | Required |
|-----------|------|-------------|----------|
| `cards` | array/number | Comma-separated card IDs or single card ID | Yes |

#### Response

```json
[5, 12, 18, 23, 28, 52]
```

**Response:** Updated hand after playing cards

#### Valid Plays

**Single Card:**
```bash
curl "http://localhost:9999/player/2/play?cards=5"
```

**Pair/Triple (Same Rank):**
```bash
# Three Aces (0=A♠, 13=A♥, 26=A♣)
curl "http://localhost:9999/player/2/play?cards=0,13,26"

# Four Kings (12=K♠, 25=K♥, 38=K♣, 51=K♦)
curl "http://localhost:9999/player/2/play?cards=12,25,38,51"
```

**Sequence (Same Suit, 3+ consecutive):**
```bash
# 5♠ 6♠ 7♠ (4, 5, 6 = 5,6,7 of Spades)
curl "http://localhost:9999/player/2/play?cards=4,5,6"

# 10♥ J♥ Q♥ K♥ (22-25 = 10,J,Q,K of Hearts)
curl "http://localhost:9999/player/2/play?cards=22,23,24,25"
```

**Sequence with Joker:**
```bash
# 5♠ Joker 7♠ (4, 52, 6 = 5,?,7 of Spades)
curl "http://localhost:9999/player/2/play?cards=4,52,6"
```

#### Invalid Plays

```bash
# Mixed suits in sequence (INVALID)
curl "http://localhost:9999/player/2/play?cards=4,18,31"  # 5♠ 6♥ 7♣

# Non-consecutive sequence (INVALID)
curl "http://localhost:9999/player/2/play?cards=4,6,8"  # 5♠ 7♠ 9♠

# Only 2 cards in sequence (INVALID)
curl "http://localhost:9999/player/2/play?cards=4,5"  # 5♠ 6♠
```

#### Errors

| Status | Condition |
|--------|-----------|
| `403` | Not player's turn |
| `403` | Action state is not `"draw"` (wrong phase) |
| `400` | Invalid card combination |
| `400` | Cards not in player's hand |
| `400` | Missing `cards` parameter |

---

### GET /player/:id/draw

Draw a card from the deck or from last played cards.

#### Request

```http
GET /player/2/draw?card=deck HTTP/1.1
```

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | number | Player ID (0-4) |

**Query Parameters:**

| Parameter | Type | Description | Required |
|-----------|------|-------------|----------|
| `card` | string/number | `"deck"` for random card, or card ID from `last_cards_played` | Yes |

#### Response

```json
{
  "draw": 42,
  "hand": [0, 5, 12, 18, 23, 28, 33, 38, 42, 52]
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `draw` | number | Card ID that was drawn |
| `hand` | array | Updated hand after drawing |

#### Examples

**Draw from Deck (Random):**
```bash
curl "http://localhost:9999/player/2/draw?card=deck"
```

**Draw Specific Card from Last Played:**
```bash
# Assuming last_cards_played = [12, 25, 38]
# Draw the K♥ (card ID 25)
curl "http://localhost:9999/player/2/draw?card=25"
```

#### Behavior

1. **Drawing completes the turn**:
   - Turn counter increments (`current_turn++`)
   - Action state changes to `"draw"` for next player
   - `cards_played` moves to `last_cards_played`
   - Previous `last_cards_played` are discarded

2. **Deck Reshuffling**:
   - If `card_in_deck < 1`, discarded cards are shuffled back into deck
   - Happens automatically before draw

#### Errors

| Status | Condition |
|--------|-----------|
| `403` | Not player's turn |
| `403` | Action state is not `"play"` (wrong phase) |
| `400` | Requested card not in `last_cards_played` |
| `400` | Missing `card` parameter |
| `500` | Deck empty (should never happen due to reshuffling) |

---

### GET /player/:id/zapzap

Call "ZapZap" to end the round and trigger scoring.

#### Request

```http
GET /player/2/zapzap HTTP/1.1
```

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | number | Player ID (0-4) |

**No query parameters.**

#### Response

```json
{
  "ret": true
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `ret` | boolean | `true` if ZapZap succeeded, `false` otherwise |

#### Requirements

To call ZapZap successfully:
1. **Hand value ≤ 5 points** (calculated without Joker penalty)
2. **Your turn** (recommended, not currently enforced)

#### Scoring

After ZapZap is called, the game calculates scores:

**Standard Scoring:**
```
Player with lowest hand: 0 points
All other players: Sum of hand values (Jokers = 25)
```

**Counteract Penalty:**
```
If any player has equal or lower hand value than ZapZap caller:
  ZapZap caller score = hand_value + (num_players × 4)

Example with 5 players:
  Caller hand = 5 points
  Another player hand = 3 points (counteract!)
  Caller final score = 5 + (5 × 4) = 25 points
```

#### Examples

```bash
# Call ZapZap as Player 2
curl "http://localhost:9999/player/2/zapzap"

# Response if successful:
# {"ret": true}

# Response if hand > 5 points:
# {"ret": false}
```

#### Game State After ZapZap

- Action state changes to `"zapzap"`
- All player hands are revealed in `/party` response
- Scores are calculated and included
- **No new round is started** (manual server restart required currently)

#### Errors

| Status | Condition |
|--------|-----------|
| `403` | Not player's turn (recommended, not enforced) |
| `400` | Hand value > 5 points |

---

### GET /suscribeupdate

Establish a Server-Sent Events (SSE) connection for real-time game updates.

#### Request

```http
GET /suscribeupdate HTTP/1.1
```

**No parameters required.**

#### Response

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

retry: 500
event: event
data: {"id":"2"}

retry: 500
event: event
data: {"id":"0"}

(newline heartbeat every 15 seconds)
```

#### Event Format

**Event Type:** `event`

**Data Payload:**
```json
{
  "id": "2"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Player ID who triggered the action |

#### Behavior

1. **Connection Established**:
   - Server keeps connection open
   - Client listens for events

2. **Events Triggered On**:
   - Player plays cards (`/play`)
   - Player draws card (`/draw`)
   - Player calls ZapZap (`/zapzap`)

3. **Client Should**:
   - Call `GET /party` to fetch updated game state
   - Update UI with new state

4. **Heartbeat**:
   - Empty newline sent every 15 seconds
   - Keeps connection alive
   - Prevents proxy timeouts

5. **Connection Close**:
   - Client closes tab/browser
   - Server cleans up listeners automatically

#### JavaScript Example

```javascript
const evtSource = new EventSource('/suscribeupdate');

evtSource.addEventListener('event', function(evt) {
  const data = JSON.parse(evt.data);
  console.log('Game updated by player:', data.id);

  // Fetch updated game state
  fetch('/party')
    .then(res => res.json())
    .then(gameState => updateUI(gameState));
});

evtSource.onerror = function(err) {
  console.error('SSE connection error:', err);
};
```

#### Notes

- **All clients receive all events** (no filtering by player)
- **No authentication** on SSE connection
- **Reconnect** on error with 500ms retry
- **No event history** (events not persisted)

---

## Card ID System

The API uses numeric IDs (0-53) to represent cards for efficient serialization.

### ID Ranges

| Range | Suit | Cards |
|-------|------|-------|
| **0-12** | **Spades ♠** | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| **13-25** | **Hearts ♥** | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| **26-38** | **Clubs ♣** | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| **39-51** | **Diamonds ♦** | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| **52-53** | **Jokers 🃏** | Joker 1, Joker 2 |

### Detailed Mapping

**Spades ♠ (0-12):**
```
0=A♠  1=2♠  2=3♠  3=4♠  4=5♠  5=6♠  6=7♠
7=8♠  8=9♠  9=10♠  10=J♠  11=Q♠  12=K♠
```

**Hearts ♥ (13-25):**
```
13=A♥  14=2♥  15=3♥  16=4♥  17=5♥  18=6♥  19=7♥
20=8♥  21=9♥  22=10♥  23=J♥  24=Q♥  25=K♥
```

**Clubs ♣ (26-38):**
```
26=A♣  27=2♣  28=3♣  29=4♣  30=5♣  31=6♣  32=7♣
33=8♣  34=9♣  35=10♣  36=J♣  37=Q♣  38=K♣
```

**Diamonds ♦ (39-51):**
```
39=A♦  40=2♦  41=3♦  42=4♦  43=5♦  44=6♦  45=7♦
46=8♦  47=9♦  48=10♦  49=J♦  50=Q♦  51=K♦
```

**Jokers 🃏 (52-53):**
```
52=Joker1  53=Joker2
```

### Formula

**Suit Calculation:**
```javascript
suit_index = Math.floor(card_id / 13)
// 0=Spades, 1=Hearts, 2=Clubs, 3=Diamonds

rank_index = card_id % 13
// 0=Ace, 1-9=2-10, 10=Jack, 11=Queen, 12=King
```

**Reverse (Card to ID):**
```javascript
card_id = (suit_index * 13) + rank_index
```

---

## Game State Machine

The game follows a strict state machine for each turn:

```
         ┌─────────────┐
         │  ROUND      │
         │  START      │
         └──────┬──────┘
                │
                ▼
         ┌─────────────┐
      ┌──│    DRAW     │◄───┐
      │  │   (Action)  │    │
      │  └──────┬──────┘    │
      │         │            │
      │         │ Player     │
      │         │ draws      │
      │         │ card       │
      │         ▼            │
      │  ┌─────────────┐    │
      │  │    PLAY     │    │
      │  │   (Action)  │    │
      │  └──────┬──────┘    │
      │         │            │
      │         │ Player     │
      │         │ plays      │
      │         │ cards      │
      │         │            │
      │         ├────────────┘
      │         │ Turn
      │         │ increments
      │         │
      │         │ ZapZap
      │         │ called?
      │         │
      │         ▼
      │  ┌─────────────┐
      └─▶│   ZAPZAP    │
         │   (Action)  │
         │  Round End  │
         └─────────────┘
```

### State Transitions

| Current State | Action | Next State | Notes |
|---------------|--------|------------|-------|
| `DRAW` | `GET /player/:id/play` | `PLAY` | Player plays valid cards |
| `PLAY` | `GET /player/:id/draw` | `DRAW` | Turn increments, next player |
| `DRAW` or `PLAY` | `GET /player/:id/zapzap` | `ZAPZAP` | Round ends, scores calculated |
| `ZAPZAP` | N/A | N/A | Manual restart required |

### Action State Validation

**During DRAW State:**
- ✅ Can play cards (`/play`)
- ✅ Can call ZapZap (`/zapzap`)
- ❌ Cannot draw card (`/draw`) until cards are played

**During PLAY State:**
- ✅ Can draw card (`/draw`)
- ✅ Can call ZapZap (`/zapzap`)
- ❌ Cannot play more cards (`/play`) until draw

**During ZAPZAP State:**
- ❌ No actions allowed
- ℹ️ Round is over
- ℹ️ Server restart required for new round

---

## Point Calculation

### Card Values

| Card | Points | Notes |
|------|--------|-------|
| Ace (A) | 1 | Lowest value |
| 2 | 2 | Face value |
| 3 | 3 | Face value |
| 4 | 4 | Face value |
| 5 | 5 | Face value |
| 6 | 6 | Face value |
| 7 | 7 | Face value |
| 8 | 8 | Face value |
| 9 | 9 | Face value |
| 10 | 10 | Face value |
| Jack (J) | 11 | Face card |
| Queen (Q) | 12 | Face card |
| King (K) | 13 | Highest value |
| **Joker (in play)** | **0** | **Used for ZapZap calculation** |
| **Joker (penalty)** | **25** | **Used for final scoring** |

### ZapZap Eligibility

```javascript
// Calculated WITHOUT Joker penalty
hand_points = sum of all cards (Jokers = 0)

if (hand_points <= 5) {
  // Can call ZapZap
}
```

**Example Hands:**

| Hand | Calculation | Eligible? |
|------|-------------|-----------|
| A♠, 2♥, 2♣ | 1 + 2 + 2 = 5 | ✅ Yes |
| Joker, 3♦, 2♠ | 0 + 3 + 2 = 5 | ✅ Yes |
| A♠, A♥, A♣, A♦, Joker | 1+1+1+1+0 = 4 | ✅ Yes |
| 3♠, 3♥ | 3 + 3 = 6 | ❌ No |
| K♠ | 13 | ❌ No |

### Final Scoring

```javascript
// Calculated WITH Joker penalty
hand_points_with_joker = sum of all cards (Jokers = 25)

// Standard scoring
if (player has lowest hand) {
  score = 0
} else {
  score = hand_points_with_joker
}

// Counteract penalty
if (zapzap_called && someone_has_lower_or_equal) {
  zapzap_caller_score = hand_points_with_joker + (num_players * 4)
}
```

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
Player 1: 0 points (lowest)
Player 2: 29 points (4 + (5 × 4) = 24 points, Joker penalty)
Player 3: 25 points
Player 4: 10 points
```

---

## Examples

### Complete Turn Sequence

```bash
# 1. Check game state
curl http://localhost:9999/party
# Response: {"action": "draw", "current_turn": 10, ...}
# Turn 10 % 5 = 0, so it's Player 0's turn

# 2. Get Player 0's hand
curl http://localhost:9999/player/0/hand
# Response: [0, 5, 12, 18, 23, 28, 33, 38, 52]

# 3. Player 0 plays three Kings (12=K♠, 25=K♥, 38=K♣)
curl "http://localhost:9999/player/0/play?cards=12,25,38"
# Response: [0, 5, 18, 23, 28, 33, 52]
# State changes to "play"

# 4. Player 0 draws from deck
curl "http://localhost:9999/player/0/draw?card=deck"
# Response: {"draw": 42, "hand": [0, 5, 18, 23, 28, 33, 42, 52]}
# Turn increments to 11, state changes to "draw"
# Now it's Player 1's turn (11 % 5 = 1)
```

### ZapZap Scenario

```bash
# Player has: A♠, 2♥, Joker (hand_points = 1 + 2 + 0 = 3)

# 1. Check hand points
curl http://localhost:9999/player/2/hand
# Response: [0, 14, 52]

# 2. Call ZapZap
curl http://localhost:9999/player/2/zapzap
# Response: {"ret": true}

# 3. Check final state
curl http://localhost:9999/party
# Response includes all hands and scores
{
  "action": "zapzap",
  "players": [
    {"name": "Vincent", "hand": [5,6,7,8,9,10,11], "score": 46},
    {"name": "Thibaut", "hand": [13,14,15,16], "score": 54},
    {"name": "Simon", "hand": [0,14,52], "score": 0},  // Lowest!
    {"name": "Lyo", "hand": [26,27], "score": 3},
    {"name": "Laurent", "hand": [39,40,41], "score": 6}
  ]
}
# Simon wins with 0 points (lowest hand)
```

### Real-time Updates

```javascript
// Frontend code
const evtSource = new EventSource('/suscribeupdate');

evtSource.addEventListener('event', function(evt) {
  const { id } = JSON.parse(evt.data);
  console.log(`Player ${id} made a move`);

  // Fetch and update game state
  fetch('/party')
    .then(res => res.json())
    .then(gameState => {
      updatePlayerTable(gameState.players);
      updateCommonDeck(gameState);
      updateCurrentTurn(gameState.current_turn);

      // Enable/disable buttons based on state
      if (gameState.current_turn % gameState.nb_players === myPlayerId) {
        enableButtons(gameState.action);
      } else {
        disableButtons();
      }
    });
});
```

---

## Rate Limiting

> ⚠️ **Not Implemented**
> Currently no rate limiting exists. This is a potential DoS vector.

**Planned for v2.0:**
- 10 requests per second per IP
- 100 requests per minute per player session

---

## Changelog

### v1.0.0 (Current)
- Initial API implementation
- GET-based endpoints
- Server-Sent Events for real-time updates
- Basic game flow support

### v1.1 (Planned)
- Proper error responses with codes
- Input validation
- Turn enforcement
- Security hardening

### v2.0 (Planned)
- RESTful POST endpoints for mutations
- Authentication and sessions
- WebSocket support
- Multiple game rooms

---

## Support

For API questions or issues:
- **GitHub Issues:** [https://github.com/vemore/zapzap/issues](https://github.com/vemore/zapzap/issues)
- **Documentation:** See [CLAUDE.md](CLAUDE.md) for implementation details

---

**Last Updated:** 2025-11-06
**API Version:** 1.0.0
