# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZapZap is a multiplayer card game web application built with Node.js/Express backend and vanilla JavaScript frontend. The game implements a rummy-style card game where players can draw, play, and "zapzap" when their hand value is low enough.

## Development Commands

### Running the Application
```bash
# Development mode with auto-reload
npm start

# Production mode
node app.js
```

The server runs on port 9999. Access the game at `http://localhost:9999/?id=<player_id>` where player_id is 0-4 for the 5 hardcoded players.

### Testing
```bash
# Run tests with coverage
npm test

# Run specific test file
npx jest player.test.js
```

Tests are configured with coverage reporting (see `jest.config.js`). Coverage reports are generated in the `coverage/` directory.

## Architecture

### Core Game Flow

The application follows a **3-tier architecture**: Game State (Party/Round/Player) → Express API → Client View Updates

**Game State Management:**
- `party.js` - Top-level game container managing players, rounds, and deck
- `round.js` - Manages single round state including turn order, played cards, and scoring
- `player.js` - Represents individual players with hand management and point calculation
- `utils.js` - Card manipulation utilities (ID conversion, validation, point calculation)

**Key Game Concepts:**
- Each `Party` can have multiple `Round` instances but only one is active (`current_round`)
- Each `Round` tracks `last_cards_played` (drawable cards) vs `cards_played` (just played this turn)
- Card validation in `utils.js:check_play()` enforces either same rank (2+ cards) or suit sequences (3+ cards with consecutive values, jokers as wildcards)
- ZapZap mechanic: Player with ≤5 points can call "zapzap" to end round. Counteract occurs if any other player has equal/lower points.

### API Endpoints

**State Queries:**
- `GET /party` - Full game state JSON (players, deck, cards played, current turn, action state)
- `GET /player/:id/hand` - Specific player's hand as card ID array

**Player Actions:**
- `GET /player/:id/play?cards=[ids]` - Play cards from hand (validated via `check_play()`)
- `GET /player/:id/draw?card=<id|"deck">` - Draw from deck or last played cards
- `GET /player/:id/zapzap` - Declare zapzap (only valid if hand_points ≤ 5)

**Real-time Updates:**
- `GET /suscribeupdate` - Server-Sent Events (SSE) endpoint for live game updates

All actions emit `event` via EventEmitter which triggers SSE updates to all connected clients.

### Frontend Structure

**Card Rendering:**
Uses `deck-of-cards` library for visual card manipulation. Cards are indexed 0-51 (standard deck) + 52-53 (jokers).

**Key Functions in `public/app_view.js`:**
- `build_game()` / `update_game()` - Renders common deck area with draw pile and played cards
- `build_player_hand()` / `update_player_hand()` - Renders player's personal hand as fanned cards
- `update_common_deck()` - Positions cards in three zones: deck (back), cards_played (y:90), last_cards_played (y:0)
- `show_players_hand()` - ZapZap end-of-round reveal showing all players' cards with scores

**Turn Management:**
Buttons (`$play`, `$draw`, `$zapzap`) are dynamically enabled/disabled based on:
- Current player turn (`data.current_turn % data.nb_players == player_id`)
- Round action state (`Round.ACTION_DRAW`, `Round.ACTION_PLAY`, `Round.ACTION_ZAPZAP`)

### Card ID System

The application uses numeric card IDs (0-53) for frontend/backend communication:
- 0-12: Spades (A-K)
- 13-25: Hearts (A-K)
- 26-38: Clubs (A-K)
- 39-51: Diamonds (A-K)
- 52-53: Jokers

**Conversion Functions:**
- `get_card_id(card, deck)` - Card object → ID (handles joker disambiguation via deck reference)
- `get_card_from_id(id, deck)` - ID → Card object (uses deck.findCards() for object identity)
- `json_hand(cards, deck)` - Card array → ID array for API responses

## Common Development Patterns

### Adding New Game Actions

1. Add action constant to `round.js` (e.g., `Round.ACTION_NEWACTION = "newaction"`)
2. Implement state change method in `Round` class
3. Add Express endpoint in `app.js` with player validation
4. Emit `event` via emitter to trigger SSE updates
5. Update `update_game()` in `app_view.js` to handle new action state
6. Add button/UI control in `build_topbar()` with appropriate enable/disable logic

### Player Hand Validation

Before modifying player state, always:
1. Validate turn order (current_turn % nb_players == player_id in production code)
2. Check action state (e.g., can't play during ACTION_DRAW)
3. Use `check_play()` for card combination validation
4. Verify cards exist in player.hand before removal

### Working with the Deck

The `cards` library deck has two states:
- `deck.draw(n)` - Returns array of n cards and moves them to drawn state
- `deck.discard(card)` - Moves card to discard pile
- `deck.shuffleDiscard()` - Moves discard pile back to draw pile when `deck.remainingLength < 1`

Round manages deck recycling: `last_cards_played` are discarded when new cards are drawn, keeping `cards_played` as the new drawable cards.

## Testing Strategy

Tests exist for `player.js` in `player.test.js`. When adding tests:
- Mock card objects with `{ rank: { shortName: 'A' }, suit: { unicode: '♠' } }` structure
- Test hand manipulation: `draw()`, `play()`, `sethand()`
- Test point calculations: `hand_points` (jokers = 0) vs `hand_points_with_joker` (jokers = 25)
- Validate error cases (empty names, invalid plays)

## Code Organization Notes

- Entry point: `app.js` initializes deck, creates party, adds 5 hardcoded players, starts first round
- Views use EJS templating (`views/hand.ejs`) with player ID injection
- Static assets served from `/node_modules/` (deck-of-cards, jquery) and `/public/` (app.css, app_view.js)
- Morgan logger configured in dev mode for HTTP request logging

## Known Limitations

- Player list is hardcoded in `app.js:15-19` (5 players)
- No authentication or session management
- Game state is in-memory only (restarting server resets game)
- Initial round always deals 10 cards to each player (`app.js:22`)
- SSE heartbeat is 15 seconds (`app.js:48`)
