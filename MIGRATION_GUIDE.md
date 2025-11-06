# Migration Guide: Legacy to Clean Architecture v2

This guide helps you migrate from the legacy monolithic implementation to the new clean architecture.

## Table of Contents

- [Overview](#overview)
- [What Changed](#what-changed)
- [Quick Migration](#quick-migration)
- [Detailed Migration Steps](#detailed-migration-steps)
- [API Changes](#api-changes)
- [Frontend Integration](#frontend-integration)
- [Testing](#testing)
- [Rollback Plan](#rollback-plan)
- [FAQ](#faq)

---

## Overview

### Legacy Architecture (v1)

- **File**: `app.legacy.js`
- **State**: In-memory only
- **Auth**: None
- **Players**: Hardcoded 5 players
- **Database**: None
- **API**: GET endpoints at `/player/:id/*` and `/party`

### New Architecture (v2)

- **Files**: `app.js` + `src/` directory structure
- **State**: SQLite database persistence
- **Auth**: JWT token-based
- **Players**: Dynamic user management
- **Database**: SQLite with full schema
- **API**: RESTful endpoints at `/api/*`

---

## What Changed

### Architecture

```
BEFORE (Legacy)                    AFTER (Clean Architecture)
┌─────────────────────┐           ┌──────────────────────────┐
│    app.legacy.js    │           │    Domain Entities       │
│  (Monolithic)       │           │  (User, Party, Round)    │
│                     │           └────────────┬─────────────┘
│  - Party            │                        │
│  - Round            │           ┌────────────▼─────────────┐
│  - Player           │           │      Use Cases           │
│  - Utils            │           │  (Business Logic)        │
│  - Routes           │           └────────────┬─────────────┘
│  - SSE              │                        │
│                     │           ┌────────────▼─────────────┐
└─────────────────────┘           │    Infrastructure        │
                                  │  (DB, Repos, Services)   │
                                  └────────────┬─────────────┘
                                               │
                                  ┌────────────▼─────────────┐
                                  │      API Layer           │
                                  │  (Routes, Middleware)    │
                                  └──────────────────────────┘
```

### Key Differences

| Feature | Legacy | New |
|---------|--------|-----|
| **Entry Point** | `app.legacy.js` | `app.js` → `src/api/server.js` |
| **State Storage** | In-memory objects | SQLite database |
| **Authentication** | None | JWT tokens |
| **Player Management** | Fixed 5 players | Dynamic users |
| **API Base Path** | `/` | `/api/` |
| **Endpoints** | GET-only | RESTful (GET/POST) |
| **Error Handling** | Basic | Structured with codes |
| **Validation** | Minimal | Comprehensive |
| **Architecture** | Monolithic | Layered/Clean |

---

## Quick Migration

### For Testing (5 Minutes)

```bash
# 1. Install dependencies (if needed)
npm install

# 2. Initialize demo data
npm run init-demo

# 3. Start new server
npm start

# 4. Test API
node scripts/test-api.js
```

**Test Credentials:**
- Username: `Vincent` (or `Thibaut`, `Simon`, `Lyo`, `Laurent`)
- Password: `demo123`

### For Development (30 Minutes)

1. **Review new structure**: Read [CLAUDE.md](CLAUDE.md)
2. **Understand API changes**: See [API Changes](#api-changes) below
3. **Update frontend code**: See [Frontend Integration](#frontend-integration)
4. **Run tests**: `npm test` and `node scripts/test-api.js`
5. **Deploy**: Configure environment variables and deploy

---

## Detailed Migration Steps

### Step 1: Database Setup

**New clean architecture requires a database.**

```bash
# The database is created automatically on first run
# Location: data/zapzap.db

# Initialize with demo data
npm run init-demo
```

**Schema Overview:**
- `users` - User accounts with authentication
- `parties` - Game parties
- `party_players` - Player membership
- `rounds` - Game rounds
- `game_state` - Current game state (JSON)

### Step 2: Authentication Integration

**Legacy had no authentication. New version requires JWT tokens.**

#### Login Flow

```javascript
// 1. User logs in
const response = await fetch('/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    username: 'Vincent',
    password: 'demo123'
  })
});

const { token, user } = await response.json();

// 2. Store token
localStorage.setItem('authToken', token);
localStorage.setItem('userId', user.id);

// 3. Use token in subsequent requests
const gameState = await fetch(`/api/game/${partyId}/state`, {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});
```

#### Registration Flow

```javascript
const response = await fetch('/api/auth/register', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    username: 'NewPlayer',
    password: 'securepassword123'
  })
});

const { token, user } = await response.json();
```

### Step 3: Update Player Identification

**Legacy**: Players identified by index (0-4)
**New**: Players identified by user UUID

#### Before (Legacy)

```javascript
const playerId = 2; // Fixed player index
const url = `/player/${playerId}/hand`;
```

#### After (New)

```javascript
const userId = localStorage.getItem('userId');
const partyId = 'c0787a87-088d-445b-b875-97afd31d1374';
const token = localStorage.getItem('authToken');

// Join party first
await fetch(`/api/party/${partyId}/join`, {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${token}` }
});

// Then access game state
const gameState = await fetch(`/api/game/${partyId}/state`, {
  headers: { 'Authorization': `Bearer ${token}` }
});
```

### Step 4: Update API Calls

See [API Changes](#api-changes) section below for complete mapping.

### Step 5: Update SSE Integration

**Legacy SSE**: Simple event with player ID
**New SSE**: Includes party ID and action

#### Before (Legacy)

```javascript
const evtSource = new EventSource('/suscribeupdate');
evtSource.addEventListener('event', (evt) => {
  const { id } = JSON.parse(evt.data);
  updateGame(); // Update for any player action
});
```

#### After (New)

```javascript
const evtSource = new EventSource('/suscribeupdate');
evtSource.addEventListener('event', (evt) => {
  const { partyId, userId, action } = JSON.parse(evt.data);

  // Only update if it's your party
  if (partyId === currentPartyId) {
    updateGame();
  }
});
```

---

## API Changes

### Complete API Mapping

| Legacy Endpoint | New Endpoint | Method | Auth | Notes |
|----------------|--------------|--------|------|-------|
| N/A | `/api/auth/register` | POST | No | New: user registration |
| N/A | `/api/auth/login` | POST | No | New: get JWT token |
| `/party` | `/api/party` | GET | No | List public parties |
| N/A | `/api/party` | POST | Yes | Create new party |
| N/A | `/api/party/:id` | GET | Yes | Get party details |
| N/A | `/api/party/:id/join` | POST | Yes | Join party |
| N/A | `/api/party/:id/leave` | POST | Yes | Leave party |
| N/A | `/api/party/:id/start` | POST | Yes | Start game (owner) |
| `/player/:id/hand` | `/api/game/:partyId/state` | GET | Yes | Get game state (includes hand) |
| `/player/:id/play?cards=...` | `/api/game/:partyId/play` | POST | Yes | Play cards |
| `/player/:id/draw?card=...` | `/api/game/:partyId/draw` | POST | Yes | Draw card |
| `/player/:id/zapzap` | `/api/game/:partyId/zapzap` | POST | Yes | Call ZapZap |
| `/suscribeupdate` | `/suscribeupdate` | GET | No | SSE (unchanged path) |

### Detailed Request/Response Changes

#### Get Game State

**Before:**
```javascript
// GET /party
{
  "nb_players": 5,
  "current_turn": 12,
  "action": "draw",
  "players": [{"name": "Vincent", "nb_cards": 9}, ...]
}

// GET /player/2/hand
[0, 5, 12, 18, 23]
```

**After:**
```javascript
// GET /api/game/:partyId/state
{
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
    "deck": [10, 15, 20, ...],
    "hands": {
      "0": [0, 5, 12],
      "1": [13, 18, 23]
    },
    "cardsPlayed": [],
    "lastCardsPlayed": []
  },
  "players": [
    {
      "userId": "uuid",
      "playerIndex": 0,
      "hand": [0, 5, 12]
    }
  ],
  "myPlayerIndex": 0
}
```

#### Play Cards

**Before:**
```javascript
// GET /player/2/play?cards=0,13,26
// Response: [5, 12, 18, 23] (updated hand)
```

**After:**
```javascript
// POST /api/game/:partyId/play
// Body: {"cardIds": [0, 13, 26]}
// Response:
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

#### Draw Card

**Before:**
```javascript
// GET /player/2/draw?card=deck
// Response: {"draw": 42, "hand": [5, 12, 18, 23, 42]}
```

**After:**
```javascript
// POST /api/game/:partyId/draw
// Body: {"source": "deck"} or {"source": "discard", "cardId": 42}
// Response:
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

---

## Frontend Integration

### Complete Frontend Migration Example

```javascript
// ================================
// 1. INITIALIZATION
// ================================

// Add login UI
function showLoginScreen() {
  // Create login form
  const loginForm = `
    <div id="login">
      <input id="username" placeholder="Username" />
      <input id="password" type="password" placeholder="Password" />
      <button onclick="login()">Login</button>
      <button onclick="register()">Register</button>
    </div>
  `;
  document.body.innerHTML = loginForm;
}

// ================================
// 2. AUTHENTICATION
// ================================

async function login() {
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;

  try {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    if (!response.ok) {
      throw new Error('Login failed');
    }

    const { token, user } = await response.json();

    // Store credentials
    localStorage.setItem('authToken', token);
    localStorage.setItem('userId', user.id);
    localStorage.setItem('username', user.username);

    // Show party list
    showPartyList();
  } catch (error) {
    alert('Login failed: ' + error.message);
  }
}

// ================================
// 3. PARTY SELECTION
// ================================

async function showPartyList() {
  const response = await fetch('/api/party');
  const { parties } = await response.json();

  const partyList = parties.map(p => `
    <div>
      <h3>${p.name}</h3>
      <p>Players: ${p.currentPlayers}/${p.maxPlayers}</p>
      <button onclick="joinParty('${p.id}')">Join</button>
    </div>
  `).join('');

  document.body.innerHTML = `
    <div>
      <h2>Available Parties</h2>
      ${partyList}
      <button onclick="createParty()">Create New Party</button>
    </div>
  `;
}

async function joinParty(partyId) {
  const token = localStorage.getItem('authToken');

  try {
    const response = await fetch(`/api/party/${partyId}/join`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (!response.ok) {
      throw new Error('Failed to join party');
    }

    localStorage.setItem('partyId', partyId);
    startGame(partyId);
  } catch (error) {
    alert('Join failed: ' + error.message);
  }
}

// ================================
// 4. GAME STATE LOADING
// ================================

async function startGame(partyId) {
  const token = localStorage.getItem('authToken');

  try {
    const response = await fetch(`/api/game/${partyId}/state`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (!response.ok) {
      throw new Error('Failed to load game state');
    }

    const gameData = await response.json();

    // Store player index
    localStorage.setItem('myPlayerIndex', gameData.myPlayerIndex);

    // Initialize UI
    buildGameUI(gameData);

    // Setup SSE
    setupRealtimeUpdates(partyId);
  } catch (error) {
    alert('Game load failed: ' + error.message);
  }
}

// ================================
// 5. GAME ACTIONS
// ================================

async function playCards(cardIds) {
  const token = localStorage.getItem('authToken');
  const partyId = localStorage.getItem('partyId');

  try {
    const response = await fetch(`/api/game/${partyId}/play`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ cardIds })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'Play failed');
    }

    const result = await response.json();
    updateGameUI(result);
  } catch (error) {
    alert('Play failed: ' + error.message);
  }
}

async function drawCard(source, cardId = null) {
  const token = localStorage.getItem('authToken');
  const partyId = localStorage.getItem('partyId');

  const body = source === 'deck'
    ? { source: 'deck' }
    : { source: 'discard', cardId };

  try {
    const response = await fetch(`/api/game/${partyId}/draw`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'Draw failed');
    }

    const result = await response.json();
    updateGameUI(result);
  } catch (error) {
    alert('Draw failed: ' + error.message);
  }
}

async function callZapZap() {
  const token = localStorage.getItem('authToken');
  const partyId = localStorage.getItem('partyId');

  try {
    const response = await fetch(`/api/game/${partyId}/zapzap`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'ZapZap failed');
    }

    const result = await response.json();
    showZapZapResults(result);
  } catch (error) {
    alert('ZapZap failed: ' + error.message);
  }
}

// ================================
// 6. REAL-TIME UPDATES
// ================================

function setupRealtimeUpdates(partyId) {
  const evtSource = new EventSource('/suscribeupdate');

  evtSource.addEventListener('event', async (evt) => {
    const { partyId: eventPartyId } = JSON.parse(evt.data);

    // Only update if it's our party
    if (eventPartyId === partyId) {
      await refreshGameState();
    }
  });

  evtSource.onerror = (error) => {
    console.error('SSE connection error:', error);
  };
}

async function refreshGameState() {
  const token = localStorage.getItem('authToken');
  const partyId = localStorage.getItem('partyId');

  const response = await fetch(`/api/game/${partyId}/state`, {
    headers: { 'Authorization': `Bearer ${token}` }
  });

  const gameData = await response.json();
  updateGameUI(gameData);
}
```

---

## Testing

### Test Migration

```bash
# 1. Install dependencies
npm install

# 2. Run unit tests
npm test

# 3. Initialize demo data
npm run init-demo

# 4. Start server
npm start

# 5. In another terminal, run API integration tests
node scripts/test-api.js
```

### Manual Testing Checklist

- [ ] User registration works
- [ ] User login returns valid JWT token
- [ ] Token authentication on protected endpoints
- [ ] Create party with settings
- [ ] List public parties
- [ ] Join party
- [ ] Start game (owner only)
- [ ] Get game state
- [ ] Play cards
- [ ] Draw cards
- [ ] Call ZapZap
- [ ] SSE updates working
- [ ] Leave party
- [ ] Multiple concurrent parties

---

## Rollback Plan

### If Migration Fails

```bash
# 1. Stop new server
pkill -f "node app.js"

# 2. Start legacy server
npm run start:legacy
```

### Database Backup

```bash
# Backup before migration
cp data/zapzap.db data/zapzap.db.backup

# Restore if needed
cp data/zapzap.db.backup data/zapzap.db
```

### Keep Both Versions Running

```bash
# Terminal 1: New architecture
npm start  # Port 9999

# Terminal 2: Legacy (change port in app.legacy.js first)
# Edit app.legacy.js: app.listen(9998)
node app.legacy.js  # Port 9998
```

---

## FAQ

### Q: Can I run both versions simultaneously?
**A**: Yes, but you need to change the port in one version. The legacy and new implementations are completely separate.

### Q: Do I need to migrate my database?
**A**: No, they use different data models. Legacy has no database. Start fresh with `npm run init-demo`.

### Q: How do I migrate my existing players?
**A**: Create new user accounts for each player using `/api/auth/register`. Player names can match the old player names.

### Q: What happens to in-game state during migration?
**A**: In-memory state from legacy is lost. You need to start new games with the new system.

### Q: Is the card game logic different?
**A**: No, the core game rules and card logic are the same. Only the API and architecture changed.

### Q: Do I need to change my frontend?
**A**: Yes, you need to update API calls and add authentication. See [Frontend Integration](#frontend-integration).

### Q: Can I still use Server-Sent Events?
**A**: Yes, SSE endpoint path is the same (`/suscribeupdate`), but the event payload has changed.

### Q: How do I debug authentication issues?
**A**: Check browser localStorage for `authToken`. Use jwt.io to decode tokens. Check server logs for validation errors.

### Q: What if my tests fail?
**A**: Ensure demo data is initialized (`npm run init-demo`). Check that SQLite database exists at `data/zapzap.db`.

### Q: How do I create new parties?
**A**: Use `POST /api/party` with authentication token. Parties are no longer hardcoded.

---

## Additional Resources

- [CLAUDE.md](CLAUDE.md) - Developer guide with architecture details
- [BACKEND_API.md](BACKEND_API.md) - Complete API documentation
- [README.md](README.md) - User-facing documentation
- `scripts/test-api.js` - Example API integration tests
- `scripts/init-demo-data.js` - Demo data creation script

---

## Support

If you encounter issues during migration:

1. Check logs in `logs/` directory
2. Run `node scripts/test-api.js` to verify API
3. Check database: `sqlite3 data/zapzap.db "SELECT * FROM users;"`
4. Review [GitHub Issues](https://github.com/vemore/zapzap/issues)

---

**Migration completed? Update this checklist:**

- [ ] Database initialized
- [ ] Demo users created
- [ ] Authentication working
- [ ] Frontend updated
- [ ] Tests passing
- [ ] SSE working
- [ ] Documentation updated
- [ ] Team trained
- [ ] Deployed to staging
- [ ] Production deployment

**Happy migrating! 🚀**
