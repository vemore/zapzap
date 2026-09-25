-- The ZapZap SQLite schema, the one source of truth for it. It started as the Node
-- backend's DDL verbatim (createSchema() plus the two users indexes of runMigrations(), at
-- the end of this file), so production's database, which Node built, already has it.
--
-- Every statement is IF NOT EXISTS, so running it on that database is a no-op:
-- tests/schema_tests.rs checks it against tests/fixtures/node_built_schema.sql, a frozen
-- copy of a Node-built schema.

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT,
    user_type TEXT NOT NULL DEFAULT 'human' CHECK(user_type IN ('human', 'bot')),
    bot_difficulty TEXT CHECK(bot_difficulty IN ('easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm', 'thibot')),
    is_admin INTEGER NOT NULL DEFAULT 0,
    last_login_at INTEGER,
    total_play_time_seconds INTEGER NOT NULL DEFAULT 0,
    google_id TEXT,
    email TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Parties table
CREATE TABLE IF NOT EXISTS parties (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    invite_code TEXT UNIQUE NOT NULL,
    visibility TEXT NOT NULL CHECK(visibility IN ('public', 'private')),
    status TEXT NOT NULL CHECK(status IN ('waiting', 'playing', 'finished')),
    settings_json TEXT NOT NULL,
    current_round_id TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Party players table
CREATE TABLE IF NOT EXISTS party_players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    player_index INTEGER NOT NULL,
    joined_at INTEGER NOT NULL,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(party_id, user_id),
    UNIQUE(party_id, player_index)
);

-- Rounds table
CREATE TABLE IF NOT EXISTS rounds (
    id TEXT PRIMARY KEY,
    party_id TEXT NOT NULL,
    round_number INTEGER NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active', 'finished')),
    current_turn INTEGER NOT NULL,
    current_action TEXT NOT NULL CHECK(current_action IN ('draw', 'play', 'zapzap')),
    created_at INTEGER NOT NULL,
    finished_at INTEGER,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    UNIQUE(party_id, round_number)
);

-- Game state table
CREATE TABLE IF NOT EXISTS game_state (
    party_id TEXT PRIMARY KEY,
    state_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_parties_owner ON parties(owner_id);
CREATE INDEX IF NOT EXISTS idx_parties_status ON parties(status);
CREATE INDEX IF NOT EXISTS idx_parties_visibility ON parties(visibility, status);
CREATE INDEX IF NOT EXISTS idx_party_players_user ON party_players(user_id);
CREATE INDEX IF NOT EXISTS idx_party_players_party ON party_players(party_id);
CREATE INDEX IF NOT EXISTS idx_rounds_party ON rounds(party_id);
CREATE INDEX IF NOT EXISTS idx_rounds_status ON rounds(party_id, status);

-- Round scores table (archives scores at end of each round)
CREATE TABLE IF NOT EXISTS round_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL,
    round_number INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    player_index INTEGER NOT NULL,
    score_this_round INTEGER NOT NULL,
    total_score_after INTEGER NOT NULL,
    hand_points INTEGER NOT NULL,
    is_zapzap_caller INTEGER NOT NULL DEFAULT 0,
    zapzap_success INTEGER NOT NULL DEFAULT 0,
    was_counteracted INTEGER NOT NULL DEFAULT 0,
    hand_cards TEXT,
    is_lowest_hand INTEGER NOT NULL DEFAULT 0,
    is_eliminated INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(party_id, round_number, user_id)
);

CREATE INDEX IF NOT EXISTS idx_round_scores_party ON round_scores(party_id);
CREATE INDEX IF NOT EXISTS idx_round_scores_user ON round_scores(user_id);
CREATE INDEX IF NOT EXISTS idx_round_scores_party_round ON round_scores(party_id, round_number);

-- Game results table (stores final game results)
CREATE TABLE IF NOT EXISTS game_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT UNIQUE NOT NULL,
    winner_user_id TEXT NOT NULL,
    winner_final_score INTEGER NOT NULL,
    total_rounds INTEGER NOT NULL,
    was_golden_score INTEGER NOT NULL DEFAULT 0,
    player_count INTEGER NOT NULL,
    finished_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (winner_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_game_results_winner ON game_results(winner_user_id);
CREATE INDEX IF NOT EXISTS idx_game_results_finished ON game_results(finished_at);

-- Player game results table (per-player results for each finished game)
CREATE TABLE IF NOT EXISTS player_game_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    final_score INTEGER NOT NULL,
    finish_position INTEGER NOT NULL,
    rounds_played INTEGER NOT NULL,
    total_zapzap_calls INTEGER NOT NULL DEFAULT 0,
    successful_zapzaps INTEGER NOT NULL DEFAULT 0,
    failed_zapzaps INTEGER NOT NULL DEFAULT 0,
    lowest_hand_count INTEGER NOT NULL DEFAULT 0,
    is_winner INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(party_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_player_results_user ON player_game_results(user_id);
CREATE INDEX IF NOT EXISTS idx_player_results_party ON player_game_results(party_id);

-- Game actions table (records all game actions for training/analytics)
CREATE TABLE IF NOT EXISTS game_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL,
    round_number INTEGER NOT NULL,
    turn_number INTEGER NOT NULL,
    player_index INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    is_human INTEGER NOT NULL DEFAULT 0,
    action_type TEXT NOT NULL CHECK(action_type IN ('hand_size', 'play', 'draw', 'zapzap')),
    action_data TEXT NOT NULL,
    hand_before TEXT NOT NULL,
    hand_value_before INTEGER NOT NULL,
    scores_before TEXT NOT NULL,
    opponent_hand_sizes TEXT NOT NULL,
    deck_size INTEGER NOT NULL,
    last_cards_played TEXT NOT NULL,
    hand_after TEXT,
    hand_value_after INTEGER,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_game_actions_party ON game_actions(party_id);
CREATE INDEX IF NOT EXISTS idx_game_actions_user ON game_actions(user_id);
CREATE INDEX IF NOT EXISTS idx_game_actions_human ON game_actions(is_human);
CREATE INDEX IF NOT EXISTS idx_game_actions_type ON game_actions(action_type);
CREATE INDEX IF NOT EXISTS idx_game_actions_party_round ON game_actions(party_id, round_number);

-- Indexes for Google OAuth (runMigrations)
CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
