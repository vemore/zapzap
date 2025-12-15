# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZapZap is a multiplayer card game web application built with Node.js/Express backend and vanilla JavaScript frontend. The game implements a rummy-style card game where players can draw, play, and "zapzap" when their hand value is low enough.

**Architecture:** Clean Architecture with Domain-Driven Design
- Domain Layer (entities, value objects)
- Use Cases (business logic)
- Infrastructure (database, services, repositories)
- API Layer (Express routes, middleware)

## Development Commands

### Running the Application

```bash
# Development mode with auto-reload
npm start

# Initialize demo data (5 users, 1 party)
npm run init-demo

# Production mode
node app.js
```

The server runs on port 9999. The new API is accessible at `http://localhost:9999/api/`.

### Testing

```bash
# Run tests with coverage
npm test

# Run specific test file
npx jest player.test.js

# Test API integration
node scripts/test-api.js
```

Tests are configured with coverage reporting (see `jest.config.js`). Coverage reports are generated in the `coverage/` directory.

## Architecture

### Clean Architecture Structure

```
src/
├── domain/                      # Domain Layer (business entities)
│   ├── entities/
│   │   ├── User.js             # User entity with authentication
│   │   ├── Party.js            # Game party entity
│   │   ├── Round.js            # Round state management
│   │   └── Player.js           # Player within a party
│   └── value-objects/
│       ├── GameState.js        # Immutable game state
│       └── PartySettings.js    # Party configuration
│
├── use-cases/                   # Application Business Logic
│   ├── auth/
│   │   ├── RegisterUser.js     # User registration
│   │   ├── LoginUser.js        # User authentication
│   │   └── ValidateToken.js    # JWT validation
│   ├── party/
│   │   ├── CreateParty.js      # Create new party
│   │   ├── JoinParty.js        # Join existing party
│   │   ├── LeaveParty.js       # Leave party
│   │   ├── StartParty.js       # Start game and deal cards
│   │   ├── ListPublicParties.js # List available parties
│   │   └── GetPartyDetails.js  # Get party information
│   └── game/
│       ├── PlayCards.js        # Play card combinations
│       ├── DrawCard.js         # Draw from deck/discard
│       ├── CallZapZap.js       # Call ZapZap to end round
│       └── GetGameState.js     # Get current game state
│
├── infrastructure/              # Infrastructure Layer
│   ├── database/
│   │   └── sqlite/
│   │       ├── DatabaseConnection.js  # SQLite wrapper
│   │       └── repositories/
│   │           ├── UserRepository.js  # User data access
│   │           └── PartyRepository.js # Party data access
│   ├── services/
│   │   └── JwtService.js       # JWT signing/verification
│   └── di/
│       └── DIContainer.js      # Dependency injection
│
└── api/                         # API Layer
    ├── server.js               # Express server setup
    ├── bootstrap.js            # DI container initialization
    ├── middleware/
    │   └── authMiddleware.js   # JWT authentication
    └── routes/
        ├── index.js            # Main API router
        ├── authRoutes.js       # Authentication endpoints
        ├── partyRoutes.js      # Party management endpoints
        └── gameRoutes.js       # Game action endpoints
```

### Database Schema

**SQLite Database** (`data/zapzap.db`):

```sql
-- Users table
users (
  id TEXT PRIMARY KEY,          -- UUID
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)

-- Parties table
parties (
  id TEXT PRIMARY KEY,          -- UUID
  name TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  invite_code TEXT UNIQUE NOT NULL,
  visibility TEXT NOT NULL,     -- 'public' or 'private'
  status TEXT NOT NULL,         -- 'waiting', 'playing', 'finished'
  settings TEXT NOT NULL,       -- JSON
  current_round_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (owner_id) REFERENCES users(id)
)

-- Party players join table
party_players (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  party_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  player_index INTEGER NOT NULL,
  joined_at TEXT NOT NULL,
  FOREIGN KEY (party_id) REFERENCES parties(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
)

-- Rounds table
rounds (
  id TEXT PRIMARY KEY,          -- UUID
  party_id TEXT NOT NULL,
  round_number INTEGER NOT NULL,
  status TEXT NOT NULL,         -- 'active', 'finished'
  started_at TEXT NOT NULL,
  ended_at TEXT,
  FOREIGN KEY (party_id) REFERENCES parties(id)
)

-- Game state table
game_state (
  party_id TEXT PRIMARY KEY,
  state TEXT NOT NULL,          -- JSON game state
  updated_at TEXT NOT NULL,
  FOREIGN KEY (party_id) REFERENCES parties(id)
)
```

### API Endpoints

**Authentication:**
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login and get JWT token

**Party Management:**
- `POST /api/party` - Create new party (authenticated)
- `GET /api/party` - List public parties
- `GET /api/party/:partyId` - Get party details (authenticated)
- `POST /api/party/:partyId/join` - Join party (authenticated)
- `POST /api/party/:partyId/leave` - Leave party (authenticated)
- `POST /api/party/:partyId/start` - Start game (owner only)

**Game Actions:**
- `GET /api/game/:partyId/state` - Get current game state (authenticated)
- `POST /api/game/:partyId/play` - Play cards (authenticated)
- `POST /api/game/:partyId/draw` - Draw card (authenticated)
- `POST /api/game/:partyId/zapzap` - Call ZapZap (authenticated)

**Real-time Updates:**
- `GET /suscribeupdate` - Server-Sent Events for live updates

**Health:**
- `GET /api/health` - Health check

### Key Domain Concepts

**User Entity** (`src/domain/entities/User.js`):
- Represents authenticated users
- Password hashing with bcrypt
- UUID-based identification
- Public object serialization (no password exposure)

**Party Entity** (`src/domain/entities/Party.js`):
- Manages game parties
- Tracks owner, players, visibility, status
- Generates unique invite codes
- Lifecycle: waiting → playing → finished

**Round Entity** (`src/domain/entities/Round.js`):
- Manages individual game rounds
- Tracks round number and status
- Links to parent party

**GameState Value Object** (`src/domain/value-objects/GameState.js`):
- Immutable game state representation
- Tracks deck, hands, turn, action, cards played
- Pure functional updates via `with()` method

**PartySettings Value Object** (`src/domain/value-objects/PartySettings.js`):
- Party configuration (player count, hand size, spectators, time limits)
- Validation rules (3-8 players, 5-7 card hand size)

### Use Case Pattern

All use cases follow this pattern:

```javascript
class UseCase {
  constructor(repositories, services) {
    this.repository = repositories;
    this.service = services;
  }

  async execute({ param1, param2 }) {
    // 1. Validate input
    // 2. Load domain entities
    // 3. Execute business logic
    // 4. Persist changes
    // 5. Return result
  }
}
```

Example: `CreateParty.js`:

```javascript
async execute({ ownerId, name, visibility, settings }) {
  // Validate input
  if (!ownerId || typeof ownerId !== 'string') {
    throw new Error('Owner ID is required');
  }

  // Verify owner exists
  const owner = await this.userRepository.findById(ownerId);
  if (!owner) {
    throw new Error('Owner not found');
  }

  // Create entity
  const party = Party.create(name, ownerId, visibility, partySettings);

  // Persist
  const savedParty = await this.partyRepository.save(party);

  return { success: true, party: savedParty.toPublicObject() };
}
```

### Repository Pattern

Repositories abstract data access:

```javascript
class PartyRepository {
  async save(party) { /* Save to database */ }
  async findById(id) { /* Load from database */ }
  async findPublicParties(status, limit, offset) { /* Query */ }
  async addPlayer(partyId, userId, playerIndex) { /* Join table */ }
  // ...
}
```

### Authentication Flow

1. **Registration/Login** → Use case validates → JWT token generated
2. **API Request** → AuthMiddleware extracts Bearer token → ValidateToken use case → User attached to `req.user`
3. **Protected Endpoint** → Access `req.user.id` for authorization

### Card ID System

The application uses numeric card IDs (0-53) for frontend/backend communication:
- 0-12: Spades (A-K)
- 13-25: Hearts (A-K)
- 26-38: Clubs (A-K)
- 39-51: Diamonds (A-K)
- 52-53: Jokers

**Conversion:**
- Cards are stored as numeric IDs in database
- Frontend converts IDs to visual representations using `frontend/src/utils/cardAdapter.js`

## Common Development Patterns

### Adding New Use Case

1. **Create use case file** in appropriate directory (`src/use-cases/`)
2. **Implement execute() method** with business logic
3. **Register in bootstrap.js**:
   ```javascript
   container.register('myUseCase', new MyUseCase(repository, service));
   ```
4. **Create API route** in `src/api/routes/`
5. **Add route to main router** in `src/api/routes/index.js`

### Adding New Entity

1. **Create entity file** in `src/domain/entities/`
2. **Implement core methods**:
   - Static factory methods (`create()`, `fromDatabase()`)
   - Business logic methods
   - `toPublicObject()` for API serialization
3. **Add validation** in constructor or factory methods
4. **Update repository** with data access methods

### Adding New API Endpoint

1. **Create route handler** in appropriate route file
2. **Apply authentication** if needed:
   ```javascript
   router.post('/endpoint', authMiddleware, async (req, res) => {
     // Access req.user.id
   });
   ```
3. **Resolve use case** from container
4. **Handle errors** appropriately with status codes
5. **Return JSON** with consistent structure

### Working with Game State

Game state is stored as JSON in the database:

```javascript
// Load game state
const gameState = await partyRepository.getGameState(partyId);

// Update immutably
const newGameState = gameState.with({
  currentTurn: gameState.currentTurn + 1,
  currentAction: 'draw'
});

// Save
await partyRepository.saveGameState(partyId, newGameState);
```

### Event Emission for SSE

```javascript
// In route handler
const result = await useCase.execute(params);

// Emit event for real-time updates
if (emitter) {
  emitter.emit('event', {
    partyId,
    userId: req.user.id,
    action: 'play'
  });
}
```

## Testing Strategy

### Unit Tests

Test domain entities and use cases in isolation:

```javascript
describe('CreateParty', () => {
  it('should create party with valid input', async () => {
    const mockUserRepo = { findById: jest.fn().mockResolvedValue({ id: 'user1' }) };
    const mockPartyRepo = { save: jest.fn().mockResolvedValue(party) };

    const useCase = new CreateParty(mockPartyRepo, mockUserRepo);
    const result = await useCase.execute({ ownerId: 'user1', name: 'Test' });

    expect(result.success).toBe(true);
  });
});
```

### Integration Tests

Test API endpoints with real database:

```javascript
// See scripts/test-api.js for example
const response = await fetch('/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'test', password: 'test123' })
});
```


## Demo Data

Create demo users and party:

```bash
npm run init-demo
```

**Creates:**
- 5 users: Vincent, Thibaut, Simon, Lyo, Laurent (password: demo123)
- 1 public party: "Demo Game" with 3 players
- All data persisted in `data/zapzap.db`

**Testing API:**

```bash
# Login
curl -X POST http://localhost:9999/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"Vincent","password":"demo123"}'

# List parties
curl http://localhost:9999/api/party

# Join party (with token)
curl -X POST http://localhost:9999/api/party/:id/join \
  -H "Authorization: Bearer <token>"
```

## Known Limitations

### Current Limitations

- Single server instance (no horizontal scaling)
- SQLite database (not suitable for high concurrency)
- Simple JWT authentication (no refresh tokens)
- Basic session management
- SSE for real-time updates (consider WebSocket for production)

## Code Quality Standards

- **Clean Architecture**: Maintain separation between layers
- **SOLID Principles**: Single responsibility, dependency injection
- **Error Handling**: Use descriptive error messages, proper status codes
- **Validation**: Validate all inputs at use case layer
- **Immutability**: Prefer immutable value objects (GameState, PartySettings)
- **Testing**: Aim for >90% coverage on business logic
- **Logging**: Use winston logger for all significant events
- **Documentation**: JSDoc comments on public methods

## Environment Variables

```env
# Server
PORT=9999
NODE_ENV=development

# Database
DB_PATH=./data/zapzap.db

# JWT
JWT_SECRET=your-secret-key-change-in-production

# Logging
LOG_LEVEL=info
LOG_DIR=./logs
```

## Dangerous Commands - NEVER RUN

⚠️ **The following commands must NEVER be executed:**

```bash
# NEVER run this - it kills VSCode's connection to WSL
pkill -9 -f "node"

# NEVER run these either - same issue
killall -9 node
kill -9 $(pgrep node)
```

**Why:** These commands kill ALL node processes including VSCode's remote server connection to WSL, breaking the development environment.

**Safe alternatives:**
```bash
# Kill specific processes by port
lsof -ti:9999 | xargs kill 2>/dev/null  # Kill process on port 9999
lsof -ti:5173 | xargs kill 2>/dev/null  # Kill process on port 5173

# Kill specific named processes
pkill -f "nodemon"     # Kill nodemon specifically
pkill -f "app.js"      # Kill the app process specifically
```

## Troubleshooting

### Database Issues

```bash
# Check database
sqlite3 data/zapzap.db "SELECT * FROM users;"
sqlite3 data/zapzap.db "SELECT * FROM parties;"

# Reset database (deletes all data!)
rm data/zapzap.db
npm run init-demo
```

### Authentication Issues

- Check JWT_SECRET environment variable
- Verify token format: `Authorization: Bearer <token>`
- Check token expiration (default 24h)
- Use ValidateToken use case for debugging

### API Testing

```bash
# Test API integration
node scripts/test-api.js

# Check server health
curl http://localhost:9999/api/health
```

- Toute modification du backend doit en premier être testée avec des appel direct à l'API
- Toute modification doit être testée avec le navigateur. Tout bugs identifié doit être corrigé.
- Toute modification et a été testée avec le navigateur et dont tout les bugs ont été corrigés peut être commité sur le repo git local.

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