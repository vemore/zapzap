# ZapZap Project Audit Report

**Date:** 2025-11-06
**Coverage:** 93% overall
**Status:** Production-Ready with Critical Security Fixes Needed

---

## Executive Summary

The ZapZap codebase demonstrates **solid engineering fundamentals** with recent quality improvements including error handling, validation, logging, and comprehensive testing. Test coverage is excellent at 93%, with player.js, party.js, and core game logic thoroughly tested.

**However, critical security vulnerabilities exist in the API layer** that must be addressed before production deployment. The app.js file has zero test coverage and lacks essential validation, making the game exploitable by malicious users.

**Bottom Line:** With 1-2 days of focused security work, this codebase can be production-ready.

---

## 🔴 CRITICAL ISSUES (Fix Immediately)

### 1. No Turn Validation in API Endpoints

**Severity:** 🔴 Critical
**Files:** app.js:79-159
**Effort:** Low (2-3 hours)

**Problem:**
```javascript
// Current code - NO validation
app.get('/player/:id/play', function(req, res) {
    var player = party.players[req.params.id];
    // ANY player can play cards for ANY other player!
```

**Attack Scenario:**
```bash
# Player 4's turn, but Player 0 makes the request:
curl "http://localhost:9999/player/0/play?cards=1,2,3"
# Server accepts it! No turn checking.
```

**Impact:**
- Complete game manipulation by malicious players
- Players can cheat by playing on others' turns
- Game state corruption possible

**Fix Required:**
```javascript
app.get('/player/:id/play', function(req, res) {
    const playerId = parseInt(req.params.id);

    // Validate it's this player's turn
    if (party.current_round.turn % party.nb_players !== playerId) {
        return res.status(403).json({
            error: 'Not your turn',
            code: 'INVALID_TURN',
            current_turn: party.current_round.turn % party.nb_players
        });
    }

    // Validate action state
    if (party.current_round.action !== Round.ACTION_DRAW) {
        return res.status(403).json({
            error: 'Cannot play cards now',
            code: 'INVALID_ACTION_STATE',
            expected: Round.ACTION_DRAW
        });
    }

    // Proceed with validated request...
```

**Affected Endpoints:**
- `/player/:id/play` (line 79)
- `/player/:id/draw` (line 115)
- `/player/:id/zapzap` (line 141)

---

### 2. Array Index Out of Bounds

**Severity:** 🔴 Critical
**Files:** app.js:75, 81, 110, 122, 137, 145
**Effort:** Low (1 hour)

**Problem:**
```javascript
// No bounds checking
var player = party.players[req.params.id];
// If id = 999 → player = undefined → crash on player.hand
```

**Attack Scenario:**
```bash
curl "http://localhost:9999/player/999/hand"
# TypeError: Cannot read property 'hand' of undefined
# Server crashes or returns 500 error
```

**Impact:**
- Server crashes on invalid player IDs
- Easy denial-of-service attack
- Poor user experience

**Fix Required:**
```javascript
app.get('/player/:id/hand', function(req, res) {
    const playerId = parseInt(req.params.id);

    // Validate player ID
    if (isNaN(playerId) || playerId < 0 || playerId >= party.nb_players) {
        return res.status(400).json({
            error: 'Invalid player ID',
            code: 'INVALID_PLAYER_ID',
            valid_range: `0-${party.nb_players - 1}`
        });
    }

    var player = party.players[playerId];
    // Safe to proceed...
```

---

### 3. XSS Vulnerability in Template

**Severity:** 🔴 Critical
**Files:** views/hand.ejs:19
**Effort:** Low (5 minutes)

**Problem:**
```ejs
<!-- Unescaped player ID from query parameter -->
var id_player = <%- player %>;
```

**Attack Scenario:**
```bash
# Malicious URL
http://localhost:9999/?id=0;alert(document.cookie);/*

# Resulting JavaScript execution:
var id_player = 0;alert(document.cookie);/*;
```

**Impact:**
- Cross-site scripting (XSS) attack vector
- Session hijacking possible
- Malicious script injection

**Fix Required:**
```ejs
<!-- Use escaped output -->
var id_player = <%= player %>;
<!-- OR validate in controller -->
```

```javascript
// In app.js route
app.get('/', function(req, res) {
    const playerId = parseInt(req.query.id);

    if (isNaN(playerId) || playerId < 0 || playerId >= party.nb_players) {
        return res.status(400).send('Invalid player ID');
    }

    res.render('hand.ejs', {"player": playerId});
});
```

---

### 4. Missing Input Validation

**Severity:** 🔴 Critical
**Files:** app.js:86
**Effort:** Medium (2 hours)

**Problem:**
```javascript
// No validation of req.query.cards format
var cards = get_cards_from_ids(req.query.cards, party.deck);
// Crashes on malformed input
```

**Attack Scenarios:**
```bash
# Malformed arrays
curl "http://localhost:9999/player/0/play?cards=abc"
curl "http://localhost:9999/player/0/play?cards=[[[1,2,3]]]"
curl "http://localhost:9999/player/0/play?cards=-1,-2,-3"

# SQL injection attempt (doesn't apply here but shows lack of validation)
curl "http://localhost:9999/player/0/play?cards=1';DROP TABLE--"
```

**Impact:**
- Server crashes on malformed input
- Undefined behavior with negative IDs
- Poor error messages for users

**Fix Required:**
```javascript
app.get('/player/:id/play', function(req, res) {
    // ... turn validation ...

    // Validate cards parameter
    if (!req.query.cards) {
        return res.status(400).json({
            error: 'Missing cards parameter',
            code: 'MISSING_CARDS'
        });
    }

    // Parse and validate card IDs
    let cardIds;
    try {
        cardIds = Array.isArray(req.query.cards)
            ? req.query.cards.map(id => parseInt(id, 10))
            : [parseInt(req.query.cards, 10)];
    } catch (err) {
        return res.status(400).json({
            error: 'Invalid cards format',
            code: 'INVALID_CARDS_FORMAT'
        });
    }

    // Validate card ID range
    const invalidCards = cardIds.filter(id => isNaN(id) || id < 0 || id > 53);
    if (invalidCards.length > 0) {
        return res.status(400).json({
            error: 'Invalid card IDs',
            code: 'INVALID_CARD_IDS',
            invalid: invalidCards
        });
    }

    var cards = get_cards_from_ids(cardIds, party.deck);
    // Proceed...
```

---

## 🟡 HIGH PRIORITY ISSUES (Fix Soon)

### 5. Silent Failures in API Endpoints

**Severity:** 🟡 High
**Files:** app.js:96-110
**Effort:** Low (2 hours)

**Problem:**
```javascript
// Invalid play just logs error, returns 200 OK
if (check_play(cards, player)) {
    // success
} else {
    console.log("incorrect play");
    ret = false; // NEVER USED
}
res.send(JSON.stringify(json_hand(...))); // Always 200 OK
```

**Impact:**
- Client cannot distinguish success from failure
- No error feedback to users
- `ret` variable is completely unused

**Fix Required:**
```javascript
if (check_play(cards, player)) {
    player.play(cards);
    party.current_round.play_cards(cards);
    emitter.emit('event', {id: req.params.id});

    res.json({
        success: true,
        hand: json_hand(player.hand, party.deck)
    });
} else {
    logger.warn(`Invalid play attempt by ${player.name}`, {
        cards: str_cards(cards),
        turn: party.current_round.turn
    });

    res.status(400).json({
        error: 'Invalid card combination',
        code: 'INVALID_PLAY',
        cards_attempted: req.query.cards
    });
}
```

---

### 6. No Integration Tests for app.js

**Severity:** 🟡 High
**Files:** app.js (0% coverage)
**Effort:** High (1-2 days)

**Problem:**
- app.js has **ZERO test coverage**
- API endpoints completely untested
- No validation that endpoints work correctly
- Regressions go unnoticed

**Coverage Stats:**
```
File         | % Stmts | % Branch | % Funcs | % Lines
-------------|---------|----------|---------|--------
app.js       |   0     |    0     |    0    |   0     ← CRITICAL
party.js     | 100     |  100     |  100    | 100
player.js    | 100     |  100     |  100    | 100
round.js     | 97.46   | 94.44    |  100    | 97.46
utils.js     | 86.87   | 82.61    | 90.48   | 86.87
-------------|---------|----------|---------|--------
All files    | 93.06   | 92.86    | 97.22   | 93.06
```

**Tests Needed:**
```javascript
// tests/app.test.js
describe('API Endpoints', () => {
  describe('GET /party', () => {
    it('returns full game state');
    it('includes all players');
    it('shows current turn');
  });

  describe('GET /player/:id/hand', () => {
    it('returns player hand as card IDs');
    it('returns 400 for invalid player ID');
    it('returns 400 for negative ID');
  });

  describe('GET /player/:id/play', () => {
    it('accepts valid card play');
    it('returns 403 when not player turn');
    it('returns 403 during wrong action state');
    it('returns 400 for invalid card combo');
    it('returns 400 for cards not in hand');
    it('updates game state correctly');
    it('emits SSE event');
  });

  describe('GET /player/:id/draw', () => {
    it('draws from deck when card=deck');
    it('draws specific card from last_cards_played');
    it('returns 400 for card not in last_cards_played');
    it('reshuffles deck when empty');
    it('advances turn after draw');
  });

  describe('GET /player/:id/zapzap', () => {
    it('ends round when hand_points <= 5');
    it('returns 400 when hand_points > 5');
    it('calculates scores correctly');
    it('handles counteract correctly');
  });

  describe('GET /suscribeupdate', () => {
    it('establishes SSE connection');
    it('sends heartbeat every 15s');
    it('cleans up on disconnect');
  });
});
```

---

### 7. Non-RESTful API Design

**Severity:** 🟡 High
**Files:** app.js:79, 115, 141
**Effort:** Medium (4 hours)

**Problem:**
```javascript
// Using GET with side effects (violates HTTP semantics)
GET /player/:id/play?cards=[1,2,3]  ← Mutates game state
GET /player/:id/draw?card=5          ← Mutates game state
GET /player/:id/zapzap               ← Mutates game state
```

**Issues:**
- GET should be idempotent (no side effects)
- Query parameters for complex data is awkward
- Cannot use HTTP methods for semantic meaning
- Caching proxies may cache mutating requests

**Fix Required:**
```javascript
// Use POST for mutations
POST /players/:id/actions
{
  "type": "play",
  "cards": [1, 2, 3]
}

POST /players/:id/actions
{
  "type": "draw",
  "source": "deck"  // or card ID
}

POST /players/:id/actions
{
  "type": "zapzap"
}
```

**Migration Path:**
1. Add new POST endpoints
2. Support both GET (deprecated) and POST
3. Log warnings when GET is used
4. Update frontend to use POST
5. Remove GET endpoints in v2.0

---

### 8. Missing Logger in app.js

**Severity:** 🟡 High
**Files:** app.js (uses console.log throughout)
**Effort:** Low (1 hour)

**Problem:**
```javascript
// app.js:26, 97, 101, 105, 129, 130, 152, 153
console.log("Turn "+ party.current_round.turn + " : "+ player.name + " play " + str_cards(cards));
```

**Issues:**
- Inconsistent with other files using logger
- No structured logging
- Cannot configure log levels
- Cannot route to log files in production

**Fix Required:**
```javascript
// Add at top of app.js
const logger = require('./logger');

// Replace console.log calls
logger.info('Player action', {
  turn: party.current_round.turn,
  player: player.name,
  action: 'play',
  cards: str_cards(cards)
});

logger.warn('Invalid play attempt', {
  turn: party.current_round.turn,
  player: player.name,
  cards: str_cards(cards)
});

logger.error('Draw failed', {
  turn: party.current_round.turn,
  player: player.name,
  reason: 'card not in last_cards_played'
});
```

---

### 9. No AJAX Error Handlers

**Severity:** 🟡 High
**Files:** public/app_view.js:201, 270, 280, 290
**Effort:** Low (2 hours)

**Problem:**
```javascript
// No error handlers on AJAX calls
$.getJSON('/player/'+id_player+'/hand', function( data ) {
    update_player_hand(data);
}); // What if network fails? Server returns 500?
```

**Impact:**
- Silent failures confuse users
- No feedback when actions fail
- Cannot retry on transient failures
- Poor user experience

**Fix Required:**
```javascript
$.getJSON('/player/'+id_player+'/hand')
  .done(function(data) {
    update_player_hand(data);
  })
  .fail(function(jqXHR, textStatus, errorThrown) {
    const error = jqXHR.responseJSON || {error: 'Network error'};

    // Show user-friendly error
    showError(error.error || 'Failed to load hand');

    // Log for debugging
    console.error('API call failed:', {
      url: '/player/'+id_player+'/hand',
      status: jqXHR.status,
      error: error
    });

    // Retry logic for transient failures
    if (jqXHR.status >= 500 || textStatus === 'timeout') {
      setTimeout(() => loadHand(id_player), 2000);
    }
  });

// Helper function
function showError(message) {
  const $error = $('<div class="error-toast">')
    .text(message)
    .appendTo('body')
    .delay(3000)
    .fadeOut();
}
```

---

### 10. Hardcoded Player List

**Severity:** 🟡 High
**Files:** app.js:15-19
**Effort:** Medium (3 hours)

**Problem:**
```javascript
// Fixed player list
party.add_player("Vincent");
party.add_player("Thibaut");
party.add_player("Simon  ");  // Trailing spaces!
party.add_player("Lyo    ");
party.add_player("Laurent");
```

**Issues:**
- Cannot add/remove players
- Name inconsistency (trailing spaces)
- No flexibility for different game sizes
- Configuration mixed with code

**Fix Required:**
```javascript
// Load from environment or config
const PLAYERS = (process.env.PLAYER_NAMES ||
  'Vincent,Thibaut,Simon,Lyo,Laurent').split(',').map(n => n.trim());

PLAYERS.forEach(name => party.add_player(name));

// OR: Allow dynamic players via API
app.post('/players', function(req, res) {
  const { name } = req.body;

  if (!name || name.trim() === '') {
    return res.status(400).json({error: 'Name required'});
  }

  if (party.nb_players >= 8) {
    return res.status(400).json({error: 'Max players reached'});
  }

  const player = party.add_player(name.trim());
  res.json({id: player.id, name: player.name});
});
```

---

## 🟢 MEDIUM PRIORITY ISSUES

### 11. Code Smells & Magic Numbers

**Severity:** 🟢 Medium
**Effort:** Low (2 hours)

**Examples:**
```javascript
// app.js:22 - Magic number
var round = party.start_round(10, 0);  // Why 10 cards?

// Should be:
const INITIAL_HAND_SIZE = 10;
var round = party.start_round(INITIAL_HAND_SIZE, 0);

// app.js:48 - Magic number
const hbt = setInterval(nln, 15000);  // Why 15 seconds?

// Should be:
const SSE_HEARTBEAT_INTERVAL = 15000;
const hbt = setInterval(nln, SSE_HEARTBEAT_INTERVAL);

// round.js:104 - Magic number
this._score[id_zapzap] = player.hand_points_with_joker + (players.length*4);

// Should be:
const COUNTERACT_PENALTY_PER_PLAYER = 4;
this._score[id_zapzap] = player.hand_points_with_joker +
  (players.length * COUNTERACT_PENALTY_PER_PLAYER);
```

---

### 12. Missing Development Tooling

**Severity:** 🟢 Medium
**Effort:** Low (1 hour)

**Missing:**
- ❌ No `npm run lint` script
- ❌ No Prettier configuration
- ❌ No pre-commit hooks (husky)
- ❌ No lint-staged
- ❌ eslintrc exists but not enforced

**Add to package.json:**
```json
{
  "scripts": {
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write '**/*.{js,json,md}'",
    "format:check": "prettier --check '**/*.{js,json,md}'",
    "precommit": "lint-staged",
    "prepare": "husky install"
  },
  "lint-staged": {
    "*.js": ["eslint --fix", "prettier --write"],
    "*.{json,md}": ["prettier --write"]
  },
  "devDependencies": {
    "husky": "^8.0.0",
    "lint-staged": "^13.0.0",
    "prettier": "^3.0.0"
  }
}
```

---

### 13. Poor Error Messages

**Severity:** 🟢 Medium
**Effort:** Low (1 hour)

**Example:**
```javascript
// app.js:170 - French message, no details
res.status(404).send('Page introuvable !');

// Should be:
res.status(404).json({
  error: 'Not Found',
  code: 'ROUTE_NOT_FOUND',
  path: req.path,
  message: 'The requested resource does not exist'
});
```

---

### 14. No Environment Configuration

**Severity:** 🟢 Medium
**Effort:** Low (30 minutes)

**Missing:**
- No `.env` file support
- Port hardcoded to 9999
- No production/development mode
- No configurable log levels

**Add:**
```javascript
// Load dotenv
require('dotenv').config();

const PORT = process.env.PORT || 9999;
const NODE_ENV = process.env.NODE_ENV || 'development';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

app.listen(PORT, () => {
  logger.info(`ZapZap server started`, {
    port: PORT,
    environment: NODE_ENV,
    url: `http://localhost:${PORT}`
  });
});
```

---

## 🟢 LOW PRIORITY ISSUES

### 15. jQuery Dependency

**Severity:** 🟢 Low
**Effort:** Medium (3 hours)

**Issue:**
- jQuery used only for `$.getJSON()`
- Adds ~30KB to bundle
- Can use native `fetch()` API

**Migration:**
```javascript
// Replace
$.getJSON('/party', function(data) { ... });

// With
fetch('/party')
  .then(res => res.json())
  .then(data => { ... })
  .catch(err => console.error(err));
```

---

### 16. No State Persistence

**Severity:** 🟢 Low
**Effort:** High (2-3 days)

**Issue:**
- Game state in memory only
- Restart server = lose game
- No recovery mechanism

**Solutions:**
- Option 1: SQLite for simple persistence
- Option 2: Redis for distributed state
- Option 3: PostgreSQL for full game history

---

### 17. Performance Issues

**Severity:** 🟢 Low
**Effort:** Medium (2 hours)

**Issues:**

1. **Broadcast all events to all clients:**
```javascript
// app.js:56 - Every client gets every event
emitter.on('event', onEvent);
// Should filter by room/game
```

2. **Re-render all cards on update:**
```javascript
// app_view.js:38-70 - Renders all 54 cards
for (var i = 54; i >= 0; i--) {
  // Heavy DOM manipulation
}
// Should use virtual DOM or diff-based rendering
```

---

## 📊 METRICS SUMMARY

### Test Coverage
| File | Statements | Branches | Functions | Lines |
|------|-----------|----------|-----------|-------|
| **app.js** | 🔴 0% | 🔴 0% | 🔴 0% | 🔴 0% |
| party.js | ✅ 100% | ✅ 100% | ✅ 100% | ✅ 100% |
| player.js | ✅ 100% | ✅ 100% | ✅ 100% | ✅ 100% |
| round.js | ✅ 97.46% | ✅ 94.44% | ✅ 100% | ✅ 97.46% |
| utils.js | ✅ 86.87% | ⚠️ 82.61% | ✅ 90.48% | ✅ 86.87% |
| **Total** | ✅ 93.06% | ✅ 92.86% | ✅ 97.22% | ✅ 93.06% |

### Security Vulnerabilities
- 🔴 **Critical:** 4 (turn validation, bounds checking, XSS, input validation)
- 🟡 **High:** 0
- 🟢 **Medium:** 0
- 🟢 **Low:** 0

### Code Quality Issues
- 🔴 **Critical:** 0
- 🟡 **High:** 6 (silent failures, no tests, REST violations, logger, AJAX, hardcoded)
- 🟢 **Medium:** 4 (magic numbers, tooling, errors, env config)
- 🟢 **Low:** 3 (jQuery, persistence, performance)

---

## 🎯 RECOMMENDED PRIORITY

### Week 1: Security & Stability
1. ✅ Fix all 4 critical security issues (1-2 days)
2. ✅ Add proper error responses (1 day)
3. ✅ Fix logger usage (2 hours)
4. ✅ Add AJAX error handlers (2 hours)

### Week 2: Quality & Testing
1. ✅ Write integration tests for app.js (2 days)
2. ✅ Remove hardcoded players (3 hours)
3. ✅ Add development tooling (1 hour)

### Week 3: Architecture & Polish
1. ⏭️ Implement REST standards (1 day)
2. ⏭️ Add environment configuration (2 hours)
3. ⏭️ Fix magic numbers (2 hours)
4. ⏭️ Improve error messages (1 hour)

### Future Enhancements
- State persistence (database)
- Performance optimizations
- Remove jQuery dependency
- Multiple game rooms
- Player authentication

---

## 📈 CONCLUSION

**Current State:**
- Strong core game logic with 93% test coverage
- Critical security gaps in API layer
- Good code organization and structure

**After Critical Fixes:**
- Production-ready security posture
- Robust error handling
- Comprehensive test coverage (95%+)
- Professional API design

**Effort Required:** 2-3 weeks to production-ready, 4-6 weeks for full quality overhaul

**Overall Assessment:** 🟡 **Good foundation, needs security hardening before production**
