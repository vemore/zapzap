const logger = require('./logger');

class GameError extends Error {
    constructor(message, code, details = {}) {
        super(message);
        this.name = this.constructor.name;
        this.code = code;
        this.details = details;
        
        // Log l'erreur avec les détails
        logger.error(message, {
            errorCode: code,
            errorType: this.name,
            ...details
        });
    }
}

class InvalidCardError extends GameError {
    constructor(message, details = {}) {
        super(message, 'CARD_001', details);
    }
}

class InvalidPlayError extends GameError {
    constructor(message, details = {}) {
        super(message, 'PLAY_001', details);
    }
}

class InvalidGameStateError extends GameError {
    constructor(message, details = {}) {
        super(message, 'GAME_001', details);
    }
}

class InvalidPlayerError extends GameError {
    constructor(message, details = {}) {
        super(message, 'PLAYER_001', details);
    }
}

// Codes d'erreur spécifiques pour chaque type de validation
const ErrorCodes = {
    // Erreurs liées aux cartes
    INVALID_CARD_SUIT: 'CARD_001',
    INVALID_CARD_RANK: 'CARD_002',
    INVALID_CARD_JOKER: 'CARD_003',

    // Erreurs liées au jeu
    INVALID_PLAY_SEQUENCE: 'PLAY_001',
    INVALID_PLAY_TURN: 'PLAY_002',
    INVALID_PLAY_CARDS: 'PLAY_003',

    // Erreurs liées à l'état du jeu
    INVALID_GAME_STATE: 'GAME_001',
    INVALID_ROUND_STATE: 'GAME_002',
    INVALID_DECK_STATE: 'GAME_003',

    // Erreurs liées aux joueurs
    INVALID_PLAYER_COUNT: 'PLAYER_001',
    INVALID_PLAYER_HAND: 'PLAYER_002',
    INVALID_PLAYER_ACTION: 'PLAYER_003'
};

module.exports = {
    GameError,
    InvalidCardError,
    InvalidPlayError,
    InvalidGameStateError,
    InvalidPlayerError,
    ErrorCodes
};