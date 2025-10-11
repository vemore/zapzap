const { Party } = require('./party.js');
const { decks } = require('cards');
const { InvalidGameStateError, InvalidPlayerError } = require('./gameError');

describe('Party', () => {
    let deck;
    let party;
    let logger;

    beforeEach(() => {
        deck = new decks.StandardDeck({ jokers: 2 });
        party = new Party(deck);
    });

    describe('#constructor', () => {
        it('should initialize with empty players and rounds', () => {
            expect(party.players).toEqual([]);
            expect(party.rounds).toEqual([]);
            expect(party.deck).toBe(deck);
        });
    });

    describe('#add_player', () => {
        it('should add a player to the party', () => {
            const player = party.add_player('Test Player');
            expect(party.players.length).toBe(1);
            expect(player.name).toBe('Test Player');
            expect(player.id).toBe(0);
        });

        it('should assign incremental IDs to players', () => {
            const player1 = party.add_player('Player 1');
            const player2 = party.add_player('Player 2');
            expect(player1.id).toBe(0);
            expect(player2.id).toBe(1);
        });
    });

    describe('#start_round', () => {
        beforeEach(() => {
            party.add_player('Player 1');
            party.add_player('Player 2');
            logger = require('./logger');
            jest.spyOn(logger, 'error');
            jest.spyOn(logger, 'info');
        });

        it('should create a new round', () => {
            const round = party.start_round(5, 0);
            expect(party.rounds.length).toBe(1);
            expect(party.current_round).toBe(round);
        });

        it('should deal correct number of cards to players', () => {
            const cardsPerHand = 5;
            party.start_round(cardsPerHand, 0);
            party.players.forEach(player => {
                expect(player.hand.length).toBe(cardsPerHand);
            });
        });

        it('should set the correct first player', () => {
            const round = party.start_round(5, 1);
            expect(round.turn).toBe(1);
        });

        it('should throw InvalidGameStateError for invalid number of cards', () => {
            expect(() => {
                party.start_round(-1, 0);
            }).toThrow('Invalid number of cards in hand');
            expect(() => {
                party.start_round(-1, 0);
            }).toThrow(InvalidGameStateError);
        });

        it('should throw InvalidPlayerError for invalid first player', () => {
            expect(() => {
                party.start_round(5, 99);
            }).toThrow('Invalid first player index');
            expect(() => {
                party.start_round(5, 99);
            }).toThrow(InvalidPlayerError);
        });

        it('should throw InvalidGameStateError for empty deck', () => {
            // Draw all cards from deck
            while(deck.remainingLength > 0) {
                deck.draw();
            }
            expect(() => {
                party.start_round(5, 0);
            }).toThrow('Not enough cards in deck');
            expect(() => {
                party.start_round(5, 0);
            }).toThrow(InvalidGameStateError);
        });
    });

    describe('#json_string', () => {
        beforeEach(() => {
            party.add_player('Player 1');
            party.add_player('Player 2');
            party.start_round(5, 0);
        });

        it('should return valid JSON string with game state', () => {
            const json = JSON.parse(party.json_string);
            expect(json.nb_players).toBe(2);
            expect(json.players.length).toBe(2);
            expect(json.current_turn).toBeDefined();
            expect(json.card_in_deck).toBeDefined();
            expect(json.action).toBeDefined();
        });

        it('should include hand information during zapzap', () => {
            party.current_round.zapzap(party.players, 0);
            const json = JSON.parse(party.json_string);
            expect(json.players[0].hand).toBeDefined();
            expect(json.players[0].score).toBeDefined();
        });
    });
});