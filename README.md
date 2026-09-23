# ZapZap 🃏

A real-time multiplayer card game: a Rust backend (axum + SQLite), a React + Vite frontend, a Flutter client in the making (Android + PWA), and a Rust simulation engine for bot training. Production still runs the earlier Node.js/Express backend while the switch to Rust is prepared. ZapZap is a rummy-style game where players race to minimize their hand value and call "ZapZap" when they reach 5 points or less.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D16.0.0-brightgreen.svg)](https://nodejs.org/)
[![API Version](https://img.shields.io/badge/API-v2.0-blue.svg)](.llmwiki/Api.md)

---

## ✨ Features

### Game Features
- 🎮 **Real-time Multiplayer**: 3-8 players with Server-Sent Events (SSE)
- 🃏 **Rummy-Style Gameplay**: Play sequences, pairs, and strategic card combinations
- ⚡ **ZapZap Mechanic**: Call ZapZap when your hand is ≤5 points to win the round
- 🎭 **Counteract System**: Opponents can counteract your ZapZap if they have equal/lower points
- 🎨 **Visual Card Interface**: Beautiful card animations using deck-of-cards library
- 📊 **Live Updates**: Real-time game state synchronization across all players

### Technical Features
- 🏗️ **Clean Architecture**: Domain-driven design with clear layer separation
- 🔐 **JWT Authentication**: Secure token-based user management
- 💾 **Database Persistence**: SQLite for game state and user data
- 🎪 **Multi-Party Support**: Multiple concurrent games
- 📡 **RESTful API**: Well-designed API with proper HTTP methods
- ✅ **Comprehensive Testing**: Unit and integration tests included

---

## 🚀 Quick Start

### Prerequisites

- **Node.js** 16.0.0 or higher
- **npm** 7.0.0 or higher

### Installation

```bash
# Clone the repository
git clone https://github.com/vemore/zapzap.git
cd zapzap

# Install dependencies
npm install

# Initialize demo data (5 users + 1 party)
npm run init-demo
```

### Running the Game

```bash
# Development mode with auto-reload
npm start
```

The server will start on **port 9999** by default.

### Demo Login Credentials

After running `npm run init-demo`, you can login with:
- **Usernames**: Vincent, Thibaut, Simon, Lyo, Laurent
- **Password**: `demo123` (for all users)

### Quick Test

```bash
# Test the API
node scripts/test-api.js

# Expected output: All API tests passed! ✓
```

---

## 🐳 Docker Deployment

### Prerequisites

- **Docker** 20.10.0 or higher
- **Docker Compose** 2.0.0 or higher

### Quick Start with Docker

```bash
# 1. Clone the repository
git clone https://github.com/vemore/zapzap.git
cd zapzap

# 2. Create environment file
cp .env.example .env

# 3. Generate a secure JWT secret
openssl rand -base64 32

# 4. Edit .env and set JWT_SECRET to the generated value
nano .env

# 5. Start all services
docker-compose up -d

# 6. (Optional) Initialize demo data
docker-compose exec backend npm run init-demo
```

The application will be available at **http://localhost** (port 80).

### Docker Services

The Docker setup includes four services:

- **nginx** (Reverse Proxy) - Routes requests to appropriate services
  - Port 80 → Frontend, Flutter PWA and API
- **backend** (Node.js API) - Express API server
  - Internal port 9999
- **frontend** (React App) - Vite-built React application
  - Internal port 80, served at `/`
- **frontend-flutter** (Flutter PWA) - the Flutter web bundle, built with `--base-href /app/`
  - Internal port 80, served at `/app/`

### Configuration

Environment variables in `.env`:

```env
# Required
NODE_ENV=production
JWT_SECRET=your-secure-random-string-here

# Optional
LOG_LEVEL=info
PROXY_PORT=80
```

### Useful Docker Commands

```bash
# Start services
docker-compose up -d

# Stop services (--remove-orphans: also removes a container the compose
# file no longer declares, which otherwise blocks the network removal)
docker-compose down --remove-orphans

# View logs (all services)
docker-compose logs -f

# View logs (specific service)
docker-compose logs -f backend
docker-compose logs -f frontend
docker-compose logs -f frontend-flutter
docker-compose logs -f nginx

# Restart services
docker-compose restart

# Rebuild and restart (after code changes)
docker-compose up -d --build

# Initialize demo data
docker-compose exec backend npm run init-demo

# Access backend shell
docker-compose exec backend sh

# Check service health
docker-compose ps
```

### Volume Persistence

The following directories are persisted:

- `./data/` - SQLite database files
- `./logs/` - Application logs

Data persists across container restarts and rebuilds.

### Troubleshooting Docker

**Services won't start:**
```bash
# Check logs for errors
docker-compose logs

# Verify environment file exists
cat .env

# Check if ports are available
lsof -i :80
```

**Database issues:**
```bash
# Check database file exists
ls -la data/

# Reset database (WARNING: deletes all data!)
rm data/zapzap.db
docker-compose restart backend
docker-compose exec backend npm run init-demo
```

**Network issues:**
```bash
# Recreate network
docker-compose down --remove-orphans
docker network prune
docker-compose up -d
```

**Rebuild from scratch:**
```bash
# Remove all containers, volumes, and images
docker-compose down -v --remove-orphans
docker-compose build --no-cache
docker-compose up -d
```

### Production Considerations

For production deployment:

1. **Set NODE_ENV to production**
   ```env
   NODE_ENV=production
   ```

2. **Use a strong JWT secret**
   ```bash
   openssl rand -base64 64
   ```

3. **Configure proper logging**
   ```env
   LOG_LEVEL=warn
   ```

4. **Consider adding HTTPS** (Modify nginx config for SSL)

5. **Set up proper monitoring and backups**
   - Database backups: `./data/`
   - Log rotation: `./logs/`

6. **Review security settings** in CLAUDE.md

---

## 📖 How to Play (Quick Guide)

### Objective

Be the first player to call **"ZapZap"** when your hand value is **5 points or less**. But beware: if another player has an equal or lower hand value, you'll be **counteracted** and receive a penalty!

### Game Setup

- **Players:** 3 to 8 players
- **Deck:** Standard 52-card deck + 2 Jokers (54 cards total)
- **Starting Hand:** 5 to 7 cards per player (configurable)
- **Turn Order:** Players take turns in sequence

### Turn Structure

Each turn has two phases:

1. **PLAY Phase** (required)
   - Play a valid combination of cards from your hand
   - Valid combinations:
     - **Single card**: Any card
     - **Pair/Triple/etc.**: 2+ cards of the same rank (e.g., 3 Kings)
     - **Sequence**: 3+ cards of the same suit in order (e.g., 5♠ 6♠ 7♠)
     - **Jokers**: Can substitute any card in sequences or pairs

2. **DRAW Phase** (required)
   - Draw a card from the **deck** (unknown card), OR
   - Draw a specific card from the **last cards played** (visible cards from previous player)

### ZapZap Rules

When your hand value is **5 points or less**, you can call **"ZapZap"** at the beginning of your turn:

1. **Click the "ZapZap" button**
2. **All hands are revealed**
3. **Scoring occurs:**
   - If you have the **lowest** hand → You score **0 points** ✅
   - If someone has **equal or lower** → **Counteract!** You get **penalized** ⚠️

### Scoring System

```
Standard Scoring:
  - Player with lowest hand: 0 points (Jokers = 0)
  - All other players: Sum of their hand values (Jokers = 25)

Counteract Penalty:
  - If counteracted: Your hand value + (number of players × 5)
  - Example with 5 players: Your hand (5) + 20 = 25 points
```

For complete rules, see the [Game Rules](#-complete-game-rules) section below.

---

## 🏗️ Architecture

| Part | Path | Stack | Status |
|---|---|---|---|
| Backend | `zapzap-rust/` | Rust 1.92 (pinned), axum, sqlx/SQLite, JWT | target backend, not deployed yet |
| Frontend | `frontend/` | React, Vite, react-router | deployed |
| Flutter client | `frontend-flutter/` | Flutter 3.47 (Dart 3.13), Provider, go_router, gen-l10n fr/en | login, register, the party list, create-party, the lobby, the game board, history and statistics; no admin yet; Android (debug) + PWA deployed under `/app/` |
| Native engine | `native/` | Rust cdylib (napi), burn | offline bot training |
| Legacy backend | `src/`, `app.js` | Node.js, Express, clean architecture | **runs in production** until the switch |

The Flutter client, from `frontend-flutter/`:

```bash
flutter pub get && flutter analyze && flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999
flutter build web --base-href /app/          # the PWA, served under /app/
flutter build apk --debug                    # Android, needs the Android SDK
```

The PWA image (`frontend-flutter/Dockerfile`, service `frontend-flutter`) builds that
bundle with a pinned Flutter SDK and serves it under `/app/`; the proxy routes `/app/` to
it. Its own smoke test, against the built image:

```bash
docker build -t zapzap-frontend-flutter:ci frontend-flutter
scripts/pwa_image_smoke.sh                   # /app/, deep links, manifest, cache headers
```

The detail — module layout, routes, bots, SSE, deployment — lives in the project wiki,
[`.llmwiki/`](.llmwiki/INDEX.md), written from the code.

### Continuous integration

`.github/workflows/ci.yml` runs on every pull request: a `scope` job picks, from the changed
paths (`scripts/ci_scope.sh`), which of these run — Rust backend (fmt, clippy `-D warnings`,
unit tests), native engine (fmt, tests), frontend (build), images (docker build of the
backend and the frontend), hooks (the Claude Code hooks self-test), Flutter client (analyze,
tests, web and debug apk builds). `master` accepts only
squash-merged pull requests with green checks. What CI does not run yet, and why:
[`.llmwiki/KnownLimits.md`](.llmwiki/KnownLimits.md).

---

## 🛠️ Development

### Available Scripts

```bash
# Start development server
npm start

# Initialize demo data
npm run init-demo

# Run tests
npm test

# Test API integration
node scripts/test-api.js
```

### API Endpoints

**Authentication:**
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login and get JWT token

**Party Management:**
- `POST /api/party` - Create new party
- `GET /api/party` - List public parties
- `GET /api/party/:id` - Get party details
- `POST /api/party/:id/join` - Join party
- `POST /api/party/:id/start` - Start game

**Game Actions:**
- `GET /api/game/:partyId/state` - Get game state
- `POST /api/game/:partyId/play` - Play cards
- `POST /api/game/:partyId/draw` - Draw card
- `POST /api/game/:partyId/zapzap` - Call ZapZap

**Real-time:**
- `GET /suscribeupdate` - SSE event stream

These are the Node routes. The Rust backend's complete list: [`.llmwiki/Api.md`](.llmwiki/Api.md).

### Running Tests

```bash
# Run all tests with coverage
npm test

# Run specific test file
npx jest player.test.js

# Run API integration tests (server must be running)
node scripts/test-api.js
```

### Demo Data

```bash
# Initialize 5 demo users and 1 party
npm run init-demo

# Output:
# Demo Users (username / password):
#   - Vincent / demo123
#   - Thibaut / demo123
#   - Simon / demo123
#   - Lyo / demo123
#   - Laurent / demo123
#
# Demo Party:
#   - Party ID: <uuid>
#   - Invite Code: <code>
#   - Name: Demo Game
```

### Environment Variables

Create a `.env` file (optional):

```env
# Server Configuration
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

---

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
Player 2: 24 points (4 + ((5-1) × 5) = 24 points penalty!)
Player 3: 25 points
Player 4: 10 points
```

### Game Elimination

- Players above **100 points** are eliminated (dead)
- Last 2 players alive: "Golden Score" final round
- Winner: Last player alive (≤100 points)

### Strategy Tips

- 💡 **Balance risk and reward**: Don't ZapZap too early!
- 🎯 **Watch the discard pile**: Draw strategically from last played cards
- 🃏 **Save Jokers**: They're worth 0 points until you get caught
- 📊 **Count cards**: Track what others have played
- ⚡ **Timing matters**: ZapZap when confident you have the lowest hand

---

## 📚 Documentation

- **[.llmwiki/INDEX.md](.llmwiki/INDEX.md)** - Project wiki: architecture, API, bots, deployment, testing
- **[GAME_RULES.md](GAME_RULES.md)** - Complete game rules
- **[CLAUDE.md](CLAUDE.md)** - Instructions for Claude Code

---

## 🐛 Known Issues & Limitations

### Current Limitations

1. **Single Server Instance**
   - No horizontal scaling support
   - SQLite not suitable for high concurrency
   - Consider PostgreSQL for production

2. **Basic Authentication**
   - No refresh tokens
   - No password reset flow
   - No email verification

3. **No Mobile Optimization**
   - UI designed for desktop browsers
   - Touch interactions may be awkward

4. **Limited Game Features**
   - No spectator mode
   - No game replay/history
   - No AI opponents

### Security Notes

⚠️ **Current Implementation**:
- Basic JWT authentication
- Bcrypt password hashing
- Input validation
- SQL injection protection via parameterized queries

⚠️ **Production Improvements Needed**:
- Rate limiting
- HTTPS enforcement
- CORS configuration
- Security headers
- Session management improvements

---

## 🗺️ Roadmap

### Current Progress
- [x] Clean architecture implementation
- [x] JWT authentication
- [x] Database persistence
- [x] API documentation
- [ ] Integration tests for all endpoints
- [ ] API rate limiting

### Planned Features
- [ ] WebSocket support (replace SSE)
- [ ] Refresh tokens
- [ ] Password reset flow
- [ ] Email verification
- [ ] Mobile-responsive UI

### Future Enhancements
- [ ] PostgreSQL support
- [ ] Horizontal scaling
- [ ] Spectator mode
- [ ] Game replay/history
- [ ] AI opponents
- [ ] Tournament mode
- [ ] Achievements & stats

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature`
3. **Make your changes** with tests
4. **Run tests**: `npm test`
5. **Commit**: `git commit -m "feat: add feature"`
6. **Push**: `git push origin feature/your-feature`
7. **Create Pull Request**

### Development Guidelines

- ✅ Write tests for new features
- ✅ Follow clean architecture principles
- ✅ Use meaningful commit messages ([Conventional Commits](https://www.conventionalcommits.org/))
- ✅ Add JSDoc comments for public APIs
- ✅ Update documentation

---

## 📄 License

This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **[cards](https://www.npmjs.com/package/cards)** - Card deck library
- **[deck-of-cards](https://www.npmjs.com/package/deck-of-cards)** - Visual card animations
- **[Express](https://expressjs.com/)** - Web framework
- **[Jest](https://jestjs.io/)** - Testing framework
- **[SQLite](https://www.sqlite.org/)** - Embedded database

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/vemore/zapzap/issues)
- **Documentation:** [.llmwiki/INDEX.md](.llmwiki/INDEX.md), [CLAUDE.md](CLAUDE.md)

---

**Made with ❤️ and Clean Architecture**

*Happy ZapZapping! 🃏⚡*
