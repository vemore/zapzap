-- ZapZap Game Database Schema
-- SQLite database for user management, party system, and game state

-- ============================================================================
-- USERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_created_at ON users(created_at);

-- ============================================================================
-- PARTIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS parties (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    visibility TEXT NOT NULL CHECK(visibility IN ('public', 'private')),
    status TEXT NOT NULL CHECK(status IN ('waiting', 'playing', 'finished')),
    settings_json TEXT NOT NULL, -- JSON: {playerCount, handSize, etc.}
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_parties_owner ON parties(owner_id);
CREATE INDEX idx_parties_invite_code ON parties(invite_code);
CREATE INDEX idx_parties_visibility_status ON parties(visibility, status);
CREATE INDEX idx_parties_created_at ON parties(created_at DESC);

-- ============================================================================
-- PARTY_PLAYERS TABLE (Junction table for users in parties)
-- ============================================================================
CREATE TABLE IF NOT EXISTS party_players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    player_index INTEGER NOT NULL, -- 0, 1, 2, etc. (turn order)
    joined_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(party_id, user_id),
    UNIQUE(party_id, player_index)
);

CREATE INDEX idx_party_players_party ON party_players(party_id);
CREATE INDEX idx_party_players_user ON party_players(user_id);
CREATE INDEX idx_party_players_joined ON party_players(joined_at);

-- ============================================================================
-- ROUNDS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS rounds (
    id TEXT PRIMARY KEY,
    party_id TEXT NOT NULL,
    round_number INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL CHECK(status IN ('active', 'finished')),
    current_turn INTEGER NOT NULL DEFAULT 0,
    current_action TEXT NOT NULL CHECK(current_action IN ('draw', 'play', 'zapzap')),
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    finished_at INTEGER,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    UNIQUE(party_id, round_number)
);

CREATE INDEX idx_rounds_party ON rounds(party_id);
CREATE INDEX idx_rounds_status ON rounds(status);
CREATE INDEX idx_rounds_created ON rounds(created_at DESC);

-- ============================================================================
-- GAME_STATE TABLE (Stores deck, hands, played cards - JSON)
-- ============================================================================
CREATE TABLE IF NOT EXISTS game_state (
    party_id TEXT PRIMARY KEY,
    state_json TEXT NOT NULL, -- JSON: {deck, hands, last_cards_played, cards_played, scores}
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE
);

CREATE INDEX idx_game_state_updated ON game_state(updated_at);

-- ============================================================================
-- DATABASE METADATA
-- ============================================================================
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

INSERT INTO schema_version (version) VALUES (1);

-- ============================================================================
-- TRIGGERS FOR UPDATED_AT
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS update_users_timestamp
AFTER UPDATE ON users
BEGIN
    UPDATE users SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_parties_timestamp
AFTER UPDATE ON parties
BEGIN
    UPDATE parties SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_game_state_timestamp
AFTER UPDATE ON game_state
BEGIN
    UPDATE game_state SET updated_at = strftime('%s', 'now') WHERE party_id = NEW.party_id;
END;
