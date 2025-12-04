# ZapZap Backend API Documentation

**Base URL:** `http://localhost:9999`
**API Base:** `/api`
**Protocol:** HTTP/1.1
**Real-time Updates:** Server-Sent Events (SSE)
**Authentication:** JWT Bearer Tokens

---

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Error Handling](#error-handling)
- [API Endpoints](#api-endpoints)
  - [Authentication](#authentication-endpoints)
  - [Party Management](#party-management-endpoints)
  - [Game Actions](#game-action-endpoints)
  - [Real-time Updates](#real-time-updates-sse)
- [Data Models](#data-models)
- [Game Flow](#game-flow)
- [Examples](#examples)

---

## Overview

The ZapZap API provides a clean architecture RESTful interface for managing multiplayer card games.

- **Authentication**: JWT token-based security
- **Persistence**: SQLite database for game state
- **RESTful**: Proper POST/GET methods with structured responses
- **Multi-party**: Support for multiple concurrent games
- **User Management**: Dynamic player registration and management

### Key Concepts

- **Users**: Authenticated players with unique accounts
- **Parties**: Game lobbies that players can create and join
- **Rounds**: Individual game rounds within a party
- **Game State**: Current state of cards, turns, and actions
- **Real-time**: Server-Sent Events push updates to all clients

### Architecture

```
┌──────────────┐
│    Client    │
└──────┬───────┘
       │ JWT Token
       ▼
┌──────────────┐
│ API Layer    │ /api/*
│ (Express)    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Use Cases   │ Business Logic
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Repositories │ Data Access
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   SQLite DB  │ Persistence
└──────────────┘
```

---

## Authentication

All protected endpoints require a JWT token in the Authorization header.

### Token Format

```
Authorization: Bearer <JWT_TOKEN>
```

### Obtaining a Token

1. **Register** a new user: `POST /api/auth/register`
2. **Login** to get token: `POST /api/auth/login`
3. **Include token** in all protected requests

### Token Expiration

- Default expiration: **24 hours**
- Expired tokens return `401 Unauthorized`
- No automatic refresh (re-login required)

---

## Error Handling

### Error Response Format

```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE_CONSTANT",
  "details": "Additional context (optional)"
}
```

### Common Status Codes

| Code | Status | Meaning |
|------|--------|---------|
| `200` | OK | Request succeeded |
| `201` | Created | Resource created successfully |
| `400` | Bad Request | Invalid input parameters |
| `401` | Unauthorized | Missing or invalid authentication |
| `403` | Forbidden | Not authorized for this action |
| `404` | Not Found | Resource doesn't exist |
| `409` | Conflict | Resource conflict (e.g., party full) |
| `500` | Internal Server Error | Server error |

### Error Codes

**Authentication:**
- `MISSING_AUTH_HEADER` - No Authorization header provided
- `INVALID_AUTH_FORMAT` - Invalid header format (not "Bearer <token>")
- `INVALID_TOKEN` - Token invalid or expired
- `USERNAME_EXISTS` - Username already taken
- `INVALID_CREDENTIALS` - Wrong username/password

**Party Management:**
- `MISSING_PARTY_NAME` - Party name required
- `PARTY_NOT_FOUND` - Party doesn't exist
- `PARTY_FULL` - Party has reached max players
- `ALREADY_IN_PARTY` - User already in this party
- `NOT_IN_PARTY` - User not a member
- `NOT_OWNER` - Only party owner can perform this action
- `PARTY_STARTED` - Cannot join game in progress

**Game Actions:**
- `GAME_NOT_STARTED` - Party hasn't started playing yet
- `INVALID_TURN` - Not your turn
- `INVALID_ACTION` - Action not allowed in current state
- `INVALID_CARDS` - Invalid card combination
- `CARD_NOT_IN_HAND` - Card not in player's hand

---

## API Endpoints

### Authentication Endpoints

#### POST /api/auth/register

Register a new user account.

**Request:**
```json
{
  "username": "string (3-20 chars, unique)",
  "password": "string (6+ chars)"
}
```

**Response:** `201 Created`
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "username": "player1",
    "createdAt": "2025-11-06T20:00:00.000Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Errors:**
- `400` - Invalid username/password format
- `409` - Username already exists

**Example:**
```bash
curl -X POST http://localhost:9999/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"player1","password":"secret123"}'
```

---

#### POST /api/auth/login

Login and receive JWT token.

**Request:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response:** `200 OK`
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "username": "player1",
    "createdAt": "2025-11-06T20:00:00.000Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Errors:**
- `400` - Missing username/password
- `401` - Invalid credentials

**Example:**
```bash
curl -X POST http://localhost:9999/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"Vincent","password":"demo123"}'
```

---

### Party Management Endpoints

#### POST /api/party

Create a new party. **Requires authentication.**

**Request:**
```json
{
  "name": "string (3-50 chars)",
  "visibility": "public" | "private",
  "settings": {
    "playerCount": "number (3-8)",
    "handSize": "number (5-7)",
    "allowSpectators": "boolean (optional)",
    "roundTimeLimit": "number (seconds, optional)"
  }
}
```

**Response:** `201 Created`
```json
{
  "success": true,
  "party": {
    "id": "uuid",
    "name": "Epic Game",
    "ownerId": "uuid",
    "inviteCode": "ABC123",
    "visibility": "public",
    "status": "waiting",
    "settings": {
      "playerCount": 5,
      "handSize": 7,
      "allowSpectators": false,
      "roundTimeLimit": 0
    },
    "createdAt": "2025-11-06T20:00:00.000Z"
  }
}
```

**Errors:**
- `401` - Not authenticated
- `400` - Invalid party name or settings

**Example:**
```bash
curl -X POST http://localhost:9999/api/party \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name":"Epic Game",
    "visibility":"public",
    "settings":{"playerCount":5,"handSize":7}
  }'
```

---

#### GET /api/party

List all public parties.

**Query Parameters:**
- `status` (optional): Filter by status ('waiting', 'playing', 'finished')
- `limit` (optional): Max results (default: 50, max: 100)
- `offset` (optional): Pagination offset (default: 0)

**Response:** `200 OK`
```json
{
  "success": true,
  "parties": [
    {
      "id": "uuid",
      "name": "Demo Game",
      "ownerId": "uuid",
      "inviteCode": "XYZ789",
      "status": "waiting",
      "currentPlayers": 3,
      "maxPlayers": 5,
      "isFull": false,
      "createdAt": "2025-11-06T20:00:00.000Z"
    }
  ],
  "pagination": {
    "limit": 50,
    "offset": 0,
    "count": 1
  }
}
```

**Example:**
```bash
curl http://localhost:9999/api/party?status=waiting&limit=10
```

---

#### GET /api/party/:partyId

Get detailed party information. **Requires authentication and membership.**

**Response:** `200 OK`
```json
{
  "success": true,
  "party": {
    "id": "uuid",
    "name": "Demo Game",
    "ownerId": "uuid",
    "inviteCode": "XYZ789",
    "visibility": "public",
    "status": "playing",
    "settings": {
      "playerCount": 5,
      "handSize": 7
    },
    "currentRoundId": "uuid",
    "createdAt": "2025-11-06T20:00:00.000Z",
    "updatedAt": "2025-11-06T20:05:00.000Z"
  },
  "players": [
    {
      "userId": "uuid",
      "playerIndex": 0,
      "joinedAt": "2025-11-06T20:00:00.000Z"
    }
  ],
  "isOwner": true,
  "userPlayerIndex": 0
}
```

**Errors:**
- `401` - Not authenticated
- `403` - Not a member of this party
- `404` - Party not found

---

#### POST /api/party/:partyId/join

Join an existing party. **Requires authentication.**

**Request Body (optional):**
```json
{
  "inviteCode": "string (for private parties)"
}
```

**Response:** `200 OK`
```json
{
  "success": true,
  "party": {
    "id": "uuid",
    "name": "Demo Game",
    "status": "waiting"
  },
  "playerIndex": 3
}
```

**Errors:**
- `401` - Not authenticated
- `404` - Party not found
- `409` - Party full
- `409` - Already in party
- `409` - Game already started

---

#### POST /api/party/:partyId/leave

Leave a party. **Requires authentication and membership.**

**Response:** `200 OK`
```json
{
  "success": true,
  "message": "Left party successfully",
  "newOwner": "uuid (if owner left and ownership transferred)"
}
```

**Errors:**
- `401` - Not authenticated
- `403` - Not in party
- `404` - Party not found

---

#### POST /api/party/:partyId/start

Start the game. **Requires authentication and owner privileges.**

**Response:** `200 OK`
```json
{
  "success": true,
  "party": {
    "id": "uuid",
    "status": "playing",
    "currentRoundId": "uuid"
  },
  "round": {
    "id": "uuid",
    "roundNumber": 1,
    "status": "active"
  }
}
```

**Errors:**
- `401` - Not authenticated
- `403` - Not the party owner
- `404` - Party not found
- `409` - Already playing
- `400` - Not enough players (minimum 2)

**Example:**
```bash
curl -X POST http://localhost:9999/api/party/$PARTY_ID/start \
  -H "Authorization: Bearer $TOKEN"
```

---

### Game Action Endpoints

#### GET /api/game/:partyId/state

Get current game state. **Requires authentication and membership.**

**Response:** `200 OK`
```json
{
  "success": true,
  "partyId": "uuid",
  "party": {
    "id": "uuid",
    "name": "Demo Game",
    "status": "playing"
  },
  "round": {
    "id": "uuid",
    "roundNumber": 1,
    "status": "active"
  },
  "gameState": {
    "currentTurn": 0,
    "currentAction": "play",
    "deck": [10, 15, 20, 25, ...],
    "hands": {
      "0": [0, 5, 12, 18, 23],
      "1": [13, 19, 26, 33, 38],
      "2": [14, 21, 28, 35, 42]
    },
    "cardsPlayed": [],
    "lastCardsPlayed": [8, 9, 10],
    "roundNumber": 1
  },
  "players": [
    {
      "userId": "uuid",
      "playerIndex": 0,
      "hand": [0, 5, 12, 18, 23]
    }
  ],
  "myPlayerIndex": 0
}
```

**Game State Fields:**
- `currentTurn`: Turn counter (mod player count for active player)
- `currentAction`: 'play' or 'draw'
- `deck`: Remaining cards (as IDs)
- `hands`: Player hands by index (you only see yours)
- `cardsPlayed`: Just played this turn
- `lastCardsPlayed`: Available to draw from

**Errors:**
- `401` - Not authenticated
- `403` - Not in party
- `404` - Party not found
- `400` - Game not started

---

#### POST /api/game/:partyId/play

Play cards from hand. **Requires authentication, membership, and your turn.**

**Request:**
```json
{
  "cardIds": [0, 13, 26]
}
```

**Response:** `200 OK`
```json
{
  "success": true,
  "gameState": {
    "currentTurn": 0,
    "currentAction": "draw",
    "cardsPlayed": [0, 13, 26]
  },
  "hand": [5, 12, 18, 23]
}
```

**Valid Plays:**
- **Single card**: Any card
- **Pair/Triple**: 2+ same rank (e.g., three Aces)
- **Sequence**: 3+ consecutive cards, same suit (e.g., 5♠ 6♠ 7♠)
- **With Jokers**: Jokers can substitute in sequences

**Errors:**
- `401` - Not authenticated
- `403` - Not your turn
- `403` - Wrong action state (need to be in 'play')
- `400` - Invalid card combination
- `400` - Cards not in hand

**Example:**
```bash
curl -X POST http://localhost:9999/api/game/$PARTY_ID/play \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cardIds":[0,13,26]}'
```

---

#### POST /api/game/:partyId/draw

Draw a card. **Requires authentication, membership, and your turn.**

**Request:**
```json
{
  "source": "deck" | "discard",
  "cardId": "number (only if source=discard)"
}
```

**Response:** `200 OK`
```json
{
  "success": true,
  "drawnCard": 42,
  "gameState": {
    "currentTurn": 1,
    "currentAction": "play"
  },
  "hand": [5, 12, 18, 23, 42]
}
```

**Errors:**
- `401` - Not authenticated
- `403` - Not your turn
- `403` - Wrong action state (need to be in 'draw')
- `400` - Card not available in discard
- `500` - Deck empty (should not happen with reshuffling)

**Example:**
```bash
# Draw from deck
curl -X POST http://localhost:9999/api/game/$PARTY_ID/draw \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"deck"}'

# Draw specific card from discard
curl -X POST http://localhost:9999/api/game/$PARTY_ID/draw \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type": application/json" \
  -d '{"source":"discard","cardId":25}'
```

---

#### POST /api/game/:partyId/zapzap

Call ZapZap to end round. **Requires authentication, membership, and hand ≤ 5 points.**

**Response:** `200 OK`
```json
{
  "success": true,
  "result": {
    "caller": {
      "userId": "uuid",
      "hand": [0, 14, 52],
      "points": 3,
      "score": 0
    },
    "players": [
      {
        "userId": "uuid",
        "hand": [5, 6, 7],
        "points": 18,
        "score": 18
      }
    ],
    "counteracted": false,
    "winner": "uuid"
  }
}
```

**Scoring:**
- **Success**: Lowest hand scores 0, others score their hand value
- **Counteracted**: If anyone has ≤ your points, you get penalized (hand + players × 5)
- **Jokers**: Count as 0 for ZapZap check, 25 for final scoring

**Errors:**
- `401` - Not authenticated
- `403` - Not in party
- `400` - Hand value > 5 points
- `404` - Party not found

**Example:**
```bash
curl -X POST http://localhost:9999/api/game/$PARTY_ID/zapzap \
  -H "Authorization: Bearer $TOKEN"
```

---

### Real-time Updates (SSE)

#### GET /suscribeupdate

Subscribe to Server-Sent Events for real-time game updates.

**Response:** `200 OK` (streaming)
```
Content-Type: text/event-stream

retry: 500
event: event
data: {"partyId":"uuid","userId":"uuid","action":"play"}

(heartbeat every 15 seconds)
```

**Event Data:**
- `partyId`: Party where action occurred
- `userId`: User who performed action
- `action`: Type of action ('play', 'draw', 'zapzap', 'join', 'leave', 'start')

**Usage:**
```javascript
const evtSource = new EventSource('/suscribeupdate');

evtSource.addEventListener('event', (evt) => {
  const { partyId, userId, action } = JSON.parse(evt.data);

  if (partyId === myPartyId) {
    // Refresh game state
    fetch(`/api/game/${partyId}/state`, {
      headers: { 'Authorization': `Bearer ${token}` }
    })
    .then(res => res.json())
    .then(updateUI);
  }
});
```

---

### Health Check

#### GET /api/health

Check API health status.

**Response:** `200 OK`
```json
{
  "status": "ok",
  "timestamp": "2025-11-06T20:00:00.000Z"
}
```

---

## Data Models

### Card ID System

Cards are represented as numeric IDs (0-53):

| Range | Suit | Cards |
|-------|------|-------|
| 0-12 | Spades ♠ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 13-25 | Hearts ♥ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 26-38 | Clubs ♣ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 39-51 | Diamonds ♦ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 52-53 | Jokers 🃏 | Joker 1, Joker 2 |

**Example:**
- `0` = Ace of Spades
- `25` = King of Hearts
- `52` = Joker

### Card Values

| Card | Points |
|------|--------|
| Ace | 1 |
| 2-10 | Face value |
| Jack | 11 |
| Queen | 12 |
| King | 13 |
| Joker (in play) | 0 |
| Joker (penalty) | 25 |

### Party Status

- `waiting`: Lobby, players can join
- `playing`: Game in progress
- `finished`: Game completed

### Game Actions

- `play`: Player must play cards
- `draw`: Player must draw a card
- `zapzap`: Round ended, showing scores

---

## Game Flow

### Complete Game Lifecycle

```
1. REGISTER/LOGIN
   ↓
2. CREATE or JOIN PARTY
   ↓
3. WAIT for PLAYERS
   ↓
4. OWNER STARTS GAME
   ↓
5. GAME LOOP:
   a. Player PLAYS cards
   b. Player DRAWS card
   c. Turn increments
   d. Repeat or ZAPZAP
   ↓
6. ZAPZAP → SCORING
   ↓
7. NEW ROUND or END GAME
```

### Turn Flow

```
Current Action: PLAY
↓
POST /api/game/:id/play (cards)
↓
Current Action: DRAW
↓
POST /api/game/:id/draw (card)
↓
Turn increments
Current Action: PLAY (next player)
```

### ZapZap Flow

```
Any turn: Hand ≤ 5 points?
↓ YES
POST /api/game/:id/zapzap
↓
All hands revealed
↓
Lowest hand: 0 points
Others: Hand value (Jokers = 25)
Counteract: Hand + (players × 5)
↓
Round ends
```

---

## Examples

### Complete Game Session

```bash
# 1. Login
TOKEN=$(curl -s -X POST http://localhost:9999/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"Vincent","password":"demo123"}' \
  | jq -r '.token')

# 2. List parties
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:9999/api/party

# 3. Join party
PARTY_ID="c0787a87-088d-445b-b875-97afd31d1374"
curl -X POST http://localhost:9999/api/party/$PARTY_ID/join \
  -H "Authorization: Bearer $TOKEN"

# 4. Get game state
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:9999/api/game/$PARTY_ID/state

# 5. Play cards (three Aces)
curl -X POST http://localhost:9999/api/game/$PARTY_ID/play \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cardIds":[0,13,26]}'

# 6. Draw from deck
curl -X POST http://localhost:9999/api/game/$PARTY_ID/draw \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"deck"}'

# 7. Call ZapZap (when hand ≤ 5 points)
curl -X POST http://localhost:9999/api/game/$PARTY_ID/zapzap \
  -H "Authorization: Bearer $TOKEN"
```

---

## Rate Limiting

**Current:** Not implemented
**Planned:** 100 requests/minute per user

---

## Support

- **Documentation**: [CLAUDE.md](CLAUDE.md)
- **Issues**: [GitHub Issues](https://github.com/vemore/zapzap/issues)

---

**Last Updated:** 2025-12-04
