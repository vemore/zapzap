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
# Development mode with auto-reload (new clean architecture)
npm start

# Legacy server (old implementation)
npm start:legacy

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

Legacy Files:
├── app.js                      # New entry point (uses clean architecture)
├── app.legacy.js               # Old monolithic implementation
├── party.js                    # Legacy party management
├── round.js                    # Legacy round state
├── player.js                   # Legacy player class
└── utils.js                    # Legacy card utilities
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

### API Endpoints (v2 - Clean Architecture)

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

**Conversion Functions in GameState:**
- Cards are stored as numeric IDs in database
- Frontend converts IDs to visual representations
- Legacy utils.js contains conversion helpers

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

## Migration from Legacy Code

### Legacy vs. New Architecture

**Legacy (`app.legacy.js`):**
- Monolithic server file
- In-memory game state
- No authentication
- Direct player ID access (0-4)
- Hardcoded 5 players

**New (`app.js` + `src/`):**
- Clean architecture with layers
- Database persistence
- JWT authentication
- User-based access control
- Dynamic player management

### Running Both Versions

```bash
# New clean architecture (default)
npm start

# Legacy implementation
npm start:legacy
```

### Migration Checklist

If migrating from legacy:

1. ✅ Run `npm run init-demo` to create demo users
2. ✅ Update frontend to use new API endpoints (`/api/...`)
3. ✅ Add authentication (login flow, JWT tokens)
4. ✅ Update player identification (user IDs instead of indices)
5. ⏳ Update game state management (database instead of memory)
6. ⏳ Update real-time updates (party-specific SSE events)

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

### Current (v2.0)

- Single server instance (no horizontal scaling)
- SQLite database (not suitable for high concurrency)
- Simple JWT authentication (no refresh tokens)
- Basic session management
- SSE for real-time updates (consider WebSocket for production)

### Legacy Limitations (Still Present in Old Code)

- Player list hardcoded in `app.legacy.js` (5 players)
- No authentication or session management
- Game state in memory only
- Single game instance per server
- No mobile optimization

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

## Performance Considerations

- **Database Queries**: Use indexes on foreign keys
- **JWT Validation**: Cached in-memory for duration of request
- **Game State**: Denormalized JSON for fast reads
- **SSE Connections**: Limited by system file descriptors
- **Concurrent Games**: Each party is independent

## Security Notes

⚠️ **Current Implementation**:
- Basic JWT authentication
- Bcrypt password hashing
- Input validation in use cases
- SQL injection protection via parameterized queries

⚠️ **Production Improvements Needed**:
- Rate limiting
- HTTPS enforcement
- CORS configuration
- Input sanitization
- Security headers
- Session management
- Password reset flow
- Email verification

## Further Reading

- [BACKEND_API.md](BACKEND_API.md) - Complete API documentation
- [README.md](README.md) - User-facing documentation
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Legacy to v2 migration
