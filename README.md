# ZapZap 🃏

A real-time multiplayer card game: a Rust backend (axum + SQLite), a React + Vite frontend, a Flutter client in the making (Android + PWA), and a Rust simulation engine for bot training. Production runs the Rust backend. ZapZap is a rummy-style game where players race to minimize their hand value and call "ZapZap" when they reach 5 points or less.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
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
- 🏗️ **Layered backend**: domain, application (use cases), infrastructure and API layers in `zapzap-rust/`
- 🔐 **JWT Authentication**: Secure token-based user management
- 💾 **Database Persistence**: SQLite for game state and user data
- 🎪 **Multi-Party Support**: Multiple concurrent games
- 📡 **RESTful API**: Well-designed API with proper HTTP methods
- ✅ **Tested**: Rust unit and API integration tests, vitest, Flutter tests and an end-to-end round, all in CI

---

## 🚀 Quick Start

### Prerequisites

- **Rust**, the toolchain `zapzap-rust/rust-toolchain.toml` pins (rustup installs it)
- **Node.js** and **npm**, for the React frontend (`frontend/`)

### Installation

```bash
# Clone the repository
git clone https://github.com/vemore/zapzap.git
cd zapzap

# Seed the bot accounts and the 5 demo users into data/zapzap.db (the Rust backend's
# seed command; idempotent, creates the file and its tables when missing)
(cd zapzap-rust && cargo run -- seed --demo)
```

### Running the Game

```bash
# The backend (JWT_SECRET is required)
cd zapzap-rust && JWT_SECRET=$(openssl rand -hex 32) cargo run

# The React frontend, in another shell: http://localhost:5173, proxies /api to :9999
cd frontend && npm ci && npm run dev
```

The backend listens on **port 9999** by default (`PORT`).

### Demo Login Credentials

After a `seed --demo`, you can login with:
- **Usernames**: Vincent, Thibaut, Simon, Lyo, Laurent
- **Password**: `demo123` (for all users)

### Quick Test

```bash
curl -s http://localhost:9999/api/health     # {"status":"ok",...}
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
openssl rand -hex 32

# 4. Edit .env and set JWT_SECRET to the generated value (required: the backend
#    refuses to start without it, or with the placeholder of .env.example)
nano .env

# 4b. The backend opens data/zapzap.db and never creates the file itself (it creates
#     the tables): create it once, writable by the image's user (uid 1000)
mkdir -p data && touch data/zapzap.db

# 5. Start all services
docker-compose up -d

# 6. Seed the bot accounts and, with --demo, the demo users (idempotent)
docker-compose exec backend /app/zapzap-backend seed --demo
```

The application will be available at **http://localhost** (port 80).

### Docker Services

The Docker setup includes four services:

- **nginx** (Reverse Proxy) - Routes requests to appropriate services
  - Port 80 → Frontend, Flutter PWA and API
- **backend** (Rust API, `zapzap-rust/`) - axum API server, built with the AWS Bedrock client
  of the LLM bots (`CARGO_FEATURES=bedrock`)
  - Internal port 9999, database `./data/zapzap.db` mounted at `/app/data`
- **frontend** (React App) - Vite-built React application
  - Internal port 80, served at `/`
- **frontend-flutter** (Flutter PWA) - the Flutter web bundle, built with `--base-href /app/`
  - Internal port 80, served at `/app/`

### Configuration

Environment variables in `.env`:

```env
# Required
JWT_SECRET=your-secure-random-string-here

# Optional
RUST_LOG=info
PROXY_PORT=80
GOOGLE_OAUTH_CLIENT_ID=...          # Google sign-in; VITE_GOOGLE_OAUTH_CLIENT_ID for the clients
BOT_ACTION_DELAY_MS=1000
AWS_BEDROCK_ENABLED=true            # LLM bots, with AWS_BEDROCK_REGION, AWS_BEDROCK_MODEL_ID,
                                    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
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

# Seed the bots and the demo users (idempotent)
docker-compose exec backend /app/zapzap-backend seed --demo

# Access backend shell
docker-compose exec backend sh

# Check service health
docker-compose ps
```

### Volume Persistence

The following directories are persisted:

- `./data/` - the SQLite database and the LLM bots' memory (`data/bot-strategies/`)

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
docker-compose exec backend /app/zapzap-backend seed --demo
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

### Deploying to production

Production does not build from a clone: `scripts/deploy_nas.sh` builds the four images from a
clean `HEAD` on the dev machine, tags them with the commit's 12-character sha and `latest`, pushes them to the LAN
registry, and has the NAS deploy directory pull and start them from
`docker-compose.prod.yml` (registry images only), waiting until the site answers.
`scripts/deploy_nas.sh --rollback <sha>` redeploys an earlier deploy's images with the compose file it ran with; `--build-only` builds and pushes without touching the NAS. Configuration:
`scripts/deploy.env` (copy `scripts/deploy.env.example`). The procedure is the `deploy`
skill (`.claude/skills/deploy/SKILL.md`), the facts `.llmwiki/Deployment.md`. The root
`docker-compose.yml` above is for local use.

### Production Considerations

For production deployment:

1. **Use a strong JWT secret** (required; `docker-compose` refuses to start without one)
   ```bash
   openssl rand -hex 32
   ```

2. **Configure proper logging** (the backend logs to stdout: `docker-compose logs backend`)
   ```env
   RUST_LOG=warn
   ```

3. **Consider adding HTTPS** (Modify nginx config for SSL)

4. **Set up proper monitoring and backups**
   - Database backups: `./data/`

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
| Backend | `zapzap-rust/` | Rust 1.92 (pinned), axum, sqlx/SQLite, JWT | **runs in production** (since 2026-09-24) |
| Frontend | `frontend/` | React, Vite, react-router | deployed |
| Flutter client | `frontend-flutter/` | Flutter 3.47 (Dart 3.13), Provider, go_router, gen-l10n fr/en | login, register (password or Google), the party list, create-party, the lobby, the game board, history and statistics, the admin screen (users, parties, statistics); Android (debug) + PWA deployed under `/app/` |
| Native engine | `native/` | Rust cdylib (napi), burn | offline bot training |

The Flutter client, from `frontend-flutter/`:

```bash
flutter pub get && dart format lib test && flutter analyze && flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999
flutter build web --base-href /app/          # the PWA, served under /app/
flutter build apk --debug                    # Android, needs the Android SDK
```

An end-to-end test plays a round through the client against a live backend and a
chromedriver (`integration_test/`, `flutter drive`). `scripts/flutter_e2e.sh` starts the
Rust backend on a fresh database and runs it, as CI does; the procedure is in
`.llmwiki/Testing.md`.

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
unit and API integration tests), native engine (fmt, tests), frontend (lint, vitest, build), images (the production
compose's Rust backend with the Bedrock feature, started until its health check passes; both
frontends), hooks (the Claude Code hooks self-test), Flutter client (analyze, tests, web and
debug apk builds), Flutter end to end (a round against the Rust backend). `master` accepts only
squash-merged pull requests with green checks. What CI does not run yet, and why:
[`.llmwiki/KnownLimits.md`](.llmwiki/KnownLimits.md).

---

## 🛠️ Development

### Available Scripts

```bash
# Backend (zapzap-rust/)
JWT_SECRET=$(openssl rand -hex 32) cargo run    # the API on :9999
cargo run -- seed --demo                        # the bot accounts and the demo users
cargo fmt && cargo clippy --all-targets -- -D warnings
cargo test

# Frontend (frontend/)
npm run dev && npm run lint && npx vitest run && npm run build
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

The complete list, with auth and failure codes: [`.llmwiki/Api.md`](.llmwiki/Api.md).

### Running Tests

```bash
(cd zapzap-rust && cargo test)                  # unit + API integration tests
(cd native && cargo test)                       # the simulation engine
(cd frontend && npx vitest run)                 # the React client
(cd frontend-flutter && flutter test)           # the Flutter client
scripts/flutter_e2e.sh                          # a round, Flutter client against the Rust backend
```

Every suite and what CI runs: [`.llmwiki/Testing.md`](.llmwiki/Testing.md).

### Demo Data

```bash
# The 8 bot accounts (EasyBot1/2, MediumBot1/2, HardBot1/2, Thibot1/2)
(cd zapzap-rust && cargo run -- seed)

# The bots and the 5 demo users, all with the password demo123:
# Vincent, Thibaut, Simon, Lyo, Laurent
(cd zapzap-rust && cargo run -- seed --demo)
```

The seed opens the database the server would (`DATABASE_URL`, else `DB_PATH`, else
`./data/zapzap.db`), creates it and its tables when missing, and creates only the accounts
whose username is free: run it twice, or on a database in use, and nothing is duplicated.
It needs no `JWT_SECRET` and no running server. It creates no demo party.

### Environment Variables

The backend reads them from its environment (`zapzap-rust/src/main.rs`, `zapzap-rust/src/infrastructure/app_state.rs`):

```env
PORT=9999                          # default 9999
DATABASE_URL=sqlite:./data/zapzap.db   # else DB_PATH, else ./data/zapzap.db
JWT_SECRET=...                     # required: openssl rand -hex 32
RUST_LOG=info                      # tracing filter
```

The complete list, Docker included: [`.llmwiki/Backend.md`](.llmwiki/Backend.md) and `.env.example`.

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
- bcrypt password hashing (Argon2 hashes still verify)
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
- [x] Layered backend (Rust)
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
4. **Run tests**: `cargo test` in `zapzap-rust/`, and the suites of what you changed ([Testing](.llmwiki/Testing.md))
5. **Commit**: `git commit -m "feat: add feature"`
6. **Push**: `git push origin feature/your-feature`
7. **Create Pull Request**

### Development Guidelines

- ✅ Write tests for new features
- ✅ Keep the backend's layers (domain, application, infrastructure, API)
- ✅ Use meaningful commit messages ([Conventional Commits](https://www.conventionalcommits.org/))
- ✅ Document public items (Rust doc comments, JSDoc in the frontend)
- ✅ Update documentation

---

## 📄 License

This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **[axum](https://github.com/tokio-rs/axum)** - Web framework of the backend
- **[SQLite](https://www.sqlite.org/)** - Embedded database
- **[deck-of-cards](https://www.npmjs.com/package/deck-of-cards)** - Visual card animations (React client)
- **[Flutter](https://flutter.dev/)** - The Android and PWA client

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/vemore/zapzap/issues)
- **Documentation:** [.llmwiki/INDEX.md](.llmwiki/INDEX.md), [CLAUDE.md](CLAUDE.md)

---

**Made with ❤️**

*Happy ZapZapping! 🃏⚡*
