# ZapZap 🃏

A real-time multiplayer card game built with Node.js, Express, and vanilla JavaScript. ZapZap is a rummy-style game where players race to minimize their hand value and call "ZapZap" when they reach 5 points or less.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Test Coverage](https://img.shields.io/badge/coverage-93%25-brightgreen.svg)](coverage/)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D16.0.0-brightgreen.svg)](https://nodejs.org/)

---

## ✨ Features

- 🎮 **Real-time Multiplayer**: 5-player game with Server-Sent Events (SSE)
- 🃏 **Rummy-Style Gameplay**: Play sequences, pairs, and strategic card combinations
- ⚡ **ZapZap Mechanic**: Call ZapZap when your hand is ≤5 points to win the round
- 🎭 **Counteract System**: Opponents can counteract your ZapZap if they have equal/lower points
- 🎨 **Visual Card Interface**: Beautiful card animations using deck-of-cards library
- 📊 **Live Updates**: Real-time game state synchronization across all players

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
```

### Running the Game

```bash
# Development mode (with auto-reload)
npm start

# Production mode
node app.js
```

The server will start on **port 9999** by default.

### Accessing the Game

Open **5 browser tabs/windows** with the following URLs (one per player):

```
Player 0: http://localhost:9999/?id=0
Player 1: http://localhost:9999/?id=1
Player 2: http://localhost:9999/?id=2
Player 3: http://localhost:9999/?id=3
Player 4: http://localhost:9999/?id=4
```

> **Note:** All 5 players must be present to start playing. The game uses hardcoded player names (see [Known Limitations](#-known-limitations)).

---

## 🎮 How to Play

### Objective

Be the first player to call **"ZapZap"** when your hand value is **5 points or less**. But beware: if another player has an equal or lower hand value, you'll be **counteracted** and receive a penalty!

### Game Setup

- **Players:** 3 to 8 players (5 hardcode for now)
- **Deck:** Standard 52-card deck + 2 Jokers (54 cards total)
- **Starting Hand:** 5 to 7 cards per player. No limit when there is only 2 player alive. The first player to play choose number.
- **Turn Order:** Players take turns in sequence (Player 0 → 1 → 2 → 3 → 4 → 0...)

### Card Values

| Card | Points |
|------|--------|
| Ace (A) | 1 |
| 2-10 | Face value |
| Jack (J) | 11 |
| Queen (Q) | 12 |
| King (K) | 13 |
| Joker (in play) | 0 |
| Joker (penalty) | 25 |

### Turn Structure

Each turn has two phases:

1. **PLAY Phase** (required)
   - Play a valid combination of cards from your hand
   - Valid combinations:
     - **Single card**: Any card
     - **Pair/Triple/etc.**: 2+ cards of the same rank (e.g., 3 Kings)
     - **Sequence**: 3+ cards of the same suit in order (e.g., 5♠ 6♠ 7♠)
     - **Jokers**: Can substitute any card in sequences or Pair/Triple/etc.

2. **DRAW Phase** (required)
   - Draw a card from the **deck** (unknown card), OR
   - Draw a specific card from the **last cards played** (visible cards from previous player)

### Valid Card Combinations

#### ✅ Valid Plays

```
Single Card:
  5♠

Pairs (Same Rank):
  K♠ K♥
  A♠ A♥ A♣ A♦
  6♠ 6♠ 🃏

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

### ZapZap Rules

When your hand value is **5 points or less**, you can call **"ZapZap"** at the beginning of your turn:

1. **Click the "ZapZap" button**
2. **All hands are revealed**
3. **Scoring occurs:**
   - If you have the **lowest** hand → You score **0 points** ✅
   - If someone has **equal or lower** → **Counteract!** You get **penalized** ⚠️

### Scoring System

At the end of each round:

```
Standard Scoring:
  - Player with lowest hand: 0 points (Jokers value is 0)
  - All other players: Sum of their hand values (Jokers value is 25)

Counteract Penalty:
  - If counteracted: Your hand value + (number of other players × 5) (Jokers value is 25)
  - Example with 5 players: Your hand (e.g., 5) + 20 = 25 points

If one or more player is above 100 points (100 points is still ok) these players are "dead". They don't participate to the next rounds.
If there is only 2 player left. This is the last turn with a "golden score": the player who win this turn, win the game so the last player "in life" (<=100points) is the winner.
```

### Strategy Tips

- 💡 **Balance risk and reward**: Don't ZapZap too early!
- 🎯 **Watch the discard pile**: Draw strategically from last played cards
- 🃏 **Save Jokers**: They're worth 0 points until you get caught
- 📊 **Count cards**: Track what others have played to estimate their hands
- ⚡ **Timing matters**: ZapZap when you're confident you have the lowest hand

---

## 🛠️ Development

### Project Structure

```
zapzap/
├── app.js                 # Express server & API routes
├── party.js               # Game party management (players, rounds, deck)
├── round.js               # Round state & turn mechanics
├── player.js              # Player hand & point calculation
├── utils.js               # Card utilities & validation logic
├── logger.js              # Winston logger configuration
├── gameError.js           # Custom error classes
├── public/                # Frontend assets
│   ├── app_view.js        # UI logic & DOM manipulation
│   └── app.css            # Styles
├── views/                 # EJS templates
│   └── hand.ejs           # Player view template
├── tests/                 # Jest tests
│   ├── player.test.js     # Player class tests
│   ├── party.test.js      # Party class tests
│   ├── round.test.js      # Round class tests
│   └── utils.test.js      # Utility function tests
├── coverage/              # Test coverage reports
├── logs/                  # Application logs (gitignored)
├── CLAUDE.md              # Claude Code developer guide
├── BACKEND_API.md         # Complete API documentation
└── AUDIT_REPORT.md        # Project quality audit

Architecture: 3-tier
  Game State (Party/Round/Player) → Express API → Client View Updates
```

### Running Tests

```bash
# Run all tests with coverage
npm test

# Run specific test file
npx jest player.test.js

# Run tests in watch mode
npx jest --watch

# View coverage report
open coverage/lcov-report/index.html
```

**Current Test Coverage:** 93% overall

| File | Statements | Branches | Functions | Lines |
|------|-----------|----------|-----------|-------|
| party.js | 100% | 100% | 100% | 100% |
| player.js | 100% | 100% | 100% | 100% |
| round.js | 97.46% | 94.44% | 100% | 97.46% |
| utils.js | 86.87% | 82.61% | 90.48% | 86.87% |
| app.js | ⚠️ 0% | ⚠️ 0% | ⚠️ 0% | ⚠️ 0% |

> **Note:** API integration tests are planned (see [AUDIT_REPORT.md](AUDIT_REPORT.md))

### Code Quality

```bash
# Check for eslint errors (requires eslint setup)
npm run lint

# Auto-fix linting issues
npm run lint:fix

# Format code with Prettier (requires prettier setup)
npm run format
```

### Environment Variables

Create a `.env` file in the project root (optional):

```env
# Server Configuration
PORT=9999
NODE_ENV=development

# Logging
LOG_LEVEL=info
LOG_DIR=./logs

# Game Configuration
INITIAL_HAND_SIZE=10
SSE_HEARTBEAT_INTERVAL=15000
```

### Development Workflow

1. **Start development server:**
   ```bash
   npm start
   ```

2. **Make your changes** to backend (`.js` files) or frontend (`public/*.js`, `views/*.ejs`)

3. **Run tests:**
   ```bash
   npm test
   ```

4. **Check code quality** (when linting is configured)

5. **Commit your changes:**
   ```bash
   git add .
   git commit -m "feat: your feature description"
   ```

### Architecture Overview

**Game State Flow:**
```
┌─────────┐     ┌─────────┐     ┌────────┐
│  Party  │────▶│  Round  │────▶│ Player │
│ (deck)  │     │ (turn)  │     │ (hand) │
└────┬────┘     └────┬────┘     └────┬───┘
     │               │               │
     └───────────────┴───────────────┘
                     │
              ┌──────▼───────┐
              │  Express API │
              └──────┬───────┘
                     │
              ┌──────▼───────┐
              │   SSE Events │
              └──────┬───────┘
                     │
              ┌──────▼───────┐
              │  Client View │
              └──────────────┘
```

**Key Design Patterns:**
- **State Machine**: Round manages game state (DRAW → PLAY → ZAPZAP)
- **Observer Pattern**: EventEmitter for SSE updates
- **Factory Pattern**: Deck creation and card generation
- **Value Objects**: Card IDs (0-53) for serialization

### Card ID System

The application uses numeric IDs (0-53) for frontend/backend communication:

| Range | Suit | Cards |
|-------|------|-------|
| 0-12 | Spades ♠ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 13-25 | Hearts ♥ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 26-38 | Clubs ♣ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 39-51 | Diamonds ♦ | A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K |
| 52-53 | Jokers 🃏 | Joker 1, Joker 2 |

**Conversion Utilities:**
- `get_card_id(card, deck)`: Card object → ID
- `get_card_from_id(id, deck)`: ID → Card object
- `json_hand(cards, deck)`: Card array → ID array

---

## 📚 API Documentation

See **[BACKEND_API.md](BACKEND_API.md)** for complete API documentation including:
- All endpoints with request/response examples
- Error codes and handling
- Game state machine
- Card ID system reference
- WebSocket/SSE event structure

---

## 🐛 Known Issues & Limitations

### Current Limitations

1. **Fixed Player List**
   - 5 players are hardcoded in `app.js`
   - Player names: Vincent, Thibaut, Simon, Lyo, Laurent
   - Cannot add/remove players dynamically

2. **No Authentication**
   - No player authentication or session management
   - Anyone with the URL can join any player slot
   - No turn enforcement on client side

3. **In-Memory State Only**
   - Game state is stored in memory
   - Restarting server resets the game
   - No game persistence or recovery

4. **Single Game Instance**
   - Only one game can run per server
   - No support for multiple concurrent games
   - No room/lobby system

5. **No Mobile Optimization**
   - UI designed for desktop browsers
   - Touch interactions may be awkward

### Known Bugs

See [GitHub Issues](https://github.com/vemore/zapzap/issues) for current bugs and feature requests.

---

## 🧪 Testing

The project uses **Jest** for testing with **93% code coverage**.

### Test Categories

1. **Unit Tests**
   - Player class (`player.test.js`)
   - Party class (`party.test.js`)
   - Round class (`round.test.js`)
   - Utility functions (`utils.test.js`)
   - Error classes (`gameError.test.js`)

2. **Integration Tests** (planned)
   - API endpoints
   - Game flow scenarios
   - Multi-player interactions

### Writing Tests

```javascript
// Example: Testing player actions
describe('Player', () => {
  it('should draw a card', () => {
    const player = new Player('Alice', 0);
    const card = { rank: { shortName: 'A' }, suit: { unicode: '♠' } };

    player.draw(card);

    expect(player.hand).toContain(card);
    expect(player.hand.length).toBe(1);
  });
});
```

### Mocking Cards

```javascript
// Mock card object structure
const mockCard = {
  rank: {
    shortName: 'A',  // 'A', '2'-'10', 'J', 'Q', 'K', 'Joker'
  },
  suit: {
    unicode: '♠'     // '♠', '♥', '♣', '♦', null (for Joker)
  }
};
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style
   - Add tests for new functionality
   - Update documentation as needed

4. **Run tests**
   ```bash
   npm test
   ```

5. **Commit your changes**
   ```bash
   git commit -m "feat: add your feature description"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create a Pull Request**

### Development Guidelines

- ✅ Write tests for all new features
- ✅ Maintain test coverage above 90%
- ✅ Follow existing naming conventions
- ✅ Add JSDoc comments for public APIs
- ✅ Update documentation for user-facing changes
- ✅ Use meaningful commit messages ([Conventional Commits](https://www.conventionalcommits.org/))

---

## 📄 License

This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **[cards](https://www.npmjs.com/package/cards)** - Card deck library
- **[deck-of-cards](https://www.npmjs.com/package/deck-of-cards)** - Visual card animations
- **[Express](https://expressjs.com/)** - Web framework
- **[Jest](https://jestjs.io/)** - Testing framework

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/vemore/zapzap/issues)
- **Discussions:** [GitHub Discussions](https://github.com/vemore/zapzap/discussions)

---

## 🗺️ Roadmap

### v1.1 (In Progress)
- [ ] API integration tests
- [ ] Security hardening (turn validation, input sanitization)
- [ ] Proper error handling and responses

### v2.0 (Planned)
- [ ] Player authentication
- [ ] Multiple game rooms
- [ ] Game state persistence (database)
- [ ] Mobile-responsive UI

### v3.0 (Future)
- [ ] Spectator mode
- [ ] Replay/history system
- [ ] AI opponents
- [ ] Tournament mode

---

**Made with ❤️ by the ZapZap Team**

*Happy ZapZapping! 🃏⚡*
