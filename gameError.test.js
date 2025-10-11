const {
    GameError,
    InvalidCardError,
    InvalidPlayError,
    InvalidGameStateError,
    InvalidPlayerError,
    ErrorCodes
} = require('./gameError');

describe('GameError', () => {
    it('should create a basic game error', () => {
        const error = new GameError('Test error', 'TEST_001', { detail: 'test' });
        expect(error.message).toBe('Test error');
        expect(error.code).toBe('TEST_001');
        expect(error.details).toEqual({ detail: 'test' });
        expect(error instanceof Error).toBe(true);
    });
});

describe('InvalidCardError', () => {
    it('should create an invalid card error', () => {
        const error = new InvalidCardError('Invalid card', { suit: '♠', rank: 'X' });
        expect(error.message).toBe('Invalid card');
        expect(error.code).toBe('CARD_001');
        expect(error.details).toEqual({ suit: '♠', rank: 'X' });
        expect(error instanceof GameError).toBe(true);
    });
});

describe('InvalidPlayError', () => {
    it('should create an invalid play error', () => {
        const error = new InvalidPlayError('Invalid play', { playedCards: [1, 2] });
        expect(error.message).toBe('Invalid play');
        expect(error.code).toBe('PLAY_001');
        expect(error.details).toEqual({ playedCards: [1, 2] });
        expect(error instanceof GameError).toBe(true);
    });
});

describe('InvalidGameStateError', () => {
    it('should create an invalid game state error', () => {
        const error = new InvalidGameStateError('Invalid state', { currentState: 'FINISHED' });
        expect(error.message).toBe('Invalid state');
        expect(error.code).toBe('GAME_001');
        expect(error.details).toEqual({ currentState: 'FINISHED' });
        expect(error instanceof GameError).toBe(true);
    });
});

describe('InvalidPlayerError', () => {
    it('should create an invalid player error', () => {
        const error = new InvalidPlayerError('Invalid player', { playerId: 5 });
        expect(error.message).toBe('Invalid player');
        expect(error.code).toBe('PLAYER_001');
        expect(error.details).toEqual({ playerId: 5 });
        expect(error instanceof GameError).toBe(true);
    });
});

describe('ErrorCodes', () => {
    it('should have unique error codes', () => {
        const codes = Object.values(ErrorCodes);
        const uniqueCodes = new Set(codes);
        expect(codes.length).toBe(uniqueCodes.size);
    });

    it('should have properly formatted error codes', () => {
        Object.values(ErrorCodes).forEach(code => {
            expect(code).toMatch(/^[A-Z]+_\d{3}$/);
        });
    });
});