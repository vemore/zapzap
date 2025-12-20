# CLAUDE.md

Guide for Claude Code working with ZapZap repository.

## Project Overview

ZapZap is a multiplayer card game (rummy-style) with Node.js/Express backend, vanilla JS frontend, and a Rust native engine for bot training.

**Stack:** Node.js, Express, SQLite, Vanilla JS (Vite), Rust (native engine)

## Quick Start

```bash
# Development
npm start                    # Backend on :9999
cd frontend && npm run dev   # Frontend on :5173

# Initialize data
npm run init-demo            # Create demo users (password: demo123)
npm run init-bots            # Create bot users

# Testing
npm test                     # Jest tests
node scripts/test-api.js     # API integration tests
```

## Architecture

```
src/
├── domain/entities/         # User, Party, Round, Player
├── domain/value-objects/    # GameState, PartySettings
├── use-cases/              # auth/, party/, game/, bot/
├── infrastructure/         # database/, services/, bot/
└── api/                    # routes/, middleware/

frontend/src/               # Vanilla JS + Vite

native/                     # Rust native engine
├── src/
│   ├── headless_engine.rs  # Fast game simulation
│   ├── game_state.rs       # Game state representation
│   ├── card_analyzer.rs    # Card validation/scoring
│   ├── strategies/         # Bot strategies (hard, thibot, drl)
│   └── training/           # DRL training (DuelingDQN, replay buffer)
```

## Key Files

| Purpose | File |
|---------|------|
| Game logic | `src/use-cases/game/CallZapZap.js`, `PlayCards.js`, `DrawCard.js` |
| Game state | `src/domain/value-objects/GameState.js` |
| Bot strategies | `src/infrastructure/bot/strategies/` |
| Card validation | `src/infrastructure/bot/CardAnalyzer.js` |
| Native engine | `native/src/headless_engine.rs` |
| DRL training | `native/src/training/trainer.rs` |

## API Endpoints

```
POST /api/auth/login, /register     # Authentication
GET  /api/party                     # List parties
POST /api/party                     # Create party
POST /api/party/:id/join, /leave, /start
GET  /api/game/:partyId/state       # Game state
POST /api/game/:partyId/play, /draw, /zapzap
GET  /api/bots                      # List available bots
GET  /suscribeupdate                # SSE real-time updates
```

## Card System

- **IDs:** 0-12 Spades, 13-25 Hearts, 26-38 Clubs, 39-51 Diamonds, 52-53 Jokers
- **Values:** A=1, 2-10=face, J=11, Q=12, K=13, Joker=0 (play) / 25 (score)
- **ZapZap:** Hand ≤5 points to call. If counteracted: +hand + (players-1)×5

## Bot Types

| Type | Difficulty | Description |
|------|------------|-------------|
| easy, medium, hard | Bot | Rule-based strategies |
| hard_vince | Bot | Enhanced hard strategy |
| thibot | Bot | Thibot strategy |
| drl | Bot | Deep RL (DuelingDQN) |
| llm | Bot | LLM-based (requires Ollama) |

## Native Engine (Rust)

```bash
cd native
cargo build --release        # Build
cargo test                   # Run tests
cargo test golden_score      # Specific tests
```

**Training:**
```bash
node scripts/train-native.js              # Train DRL bot
node scripts/run-simulation.js            # Run simulations
node scripts/genetic-optimize-hard.js     # Optimize hard bot
```

## Production

**Server:** `vemore@192.168.1.147` (Synology NAS)
**URL:** `https://zapzap.ombivince.synology.me/`

**Containers:**
- `zapzap-backend` - Node.js backend
- `zapzap-frontend` - Nginx serving frontend
- `zapzap-proxy` - Reverse proxy

**Deploy changes:**
```bash
# Copy file to production
scp <file> vemore@192.168.1.147:/tmp/
ssh vemore@192.168.1.147 "docker cp /tmp/<file> zapzap-backend:/app/<path>"
ssh vemore@192.168.1.147 "docker restart zapzap-backend"

# Check logs
ssh vemore@192.168.1.147 "docker logs --tail 50 zapzap-backend"
```

## Database

**SQLite:** `data/zapzap.db`

**Key tables:** `users`, `parties`, `party_players`, `rounds`, `game_state`, `round_scores`, `game_results`, `game_actions`

```bash
sqlite3 data/zapzap.db "SELECT * FROM users;"
sqlite3 data/zapzap.db ".schema"
```

## Testing Workflow

1. Test backend changes with direct API calls first
2. Test with browser for full integration
3. Fix any bugs before committing
4. Commit to local git repo

## Dangerous Commands - NEVER RUN

```bash
# NEVER - kills VSCode WSL connection
pkill -9 -f "node"
killall -9 node
```

**Safe alternatives:**
```bash
lsof -ti:9999 | xargs kill 2>/dev/null   # Kill port 9999
pkill -f "nodemon"                        # Kill specific process
```

## Environment Variables

```env
PORT=9999
NODE_ENV=development
DB_PATH=./data/zapzap.db
JWT_SECRET=your-secret-key
LOG_LEVEL=info
```

## Game Rules

See [GAME_RULES.md](GAME_RULES.md) for complete game rules including:
- Card values and valid combinations
- Turn flow (play → draw)
- ZapZap eligibility and scoring
- Golden Score rules (lowest hand wins, caller loses on tie)
