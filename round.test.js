const { Round } = require('./round.js');
const { decks } = require('cards');
const { Player } = require('./player.js');

describe('Round', () => {
    let deck;
    let round;
    let player1;
    let player2;

    beforeEach(() => {
        deck = new decks.StandardDeck({ jokers: 2 });
        round = new Round(5, 0, deck);
        player1 = new Player('Player 1', 0);
        player2 = new Player('Player 2', 1);
    });

    describe('#constructor', () => {
        it('should initialize with correct values', () => {
            expect(round.turn).toBe(0);
            expect(round.action).toBe(Round.ACTION_DRAW);
            expect(round.last_cards_played).toBeDefined();
            expect(round.cards_played).toEqual([]);
        });
    });

    describe('#draw', () => {
        it('should draw a card from deck', () => {
            const initialDeckSize = deck.remainingLength;
            const card = round.draw();
            expect(card).toBeDefined();
            expect(deck.remainingLength).toBe(initialDeckSize - 1);
        });

        it('should draw a specific card from last_cards_played', () => {
            const targetCard = round.last_cards_played[0];
            const drawnCard = round.draw(targetCard);
            expect(drawnCard).toBe(targetCard);
            expect(round.last_cards_played).not.toContain(targetCard);
        });
    });

    describe('#play_cards', () => {
        it('should add cards to cards_played array', () => {
            const cards = deck.draw(2);
            round.play_cards(cards);
            expect(round.cards_played).toEqual(cards);
            expect(round.action).toBe(Round.ACTION_PLAY);
        });
    });

    describe('#zapzap', () => {
        it('should calculate correct scores when player calls zapzap', () => {
            const players = [player1, player2];
            player1.sethand(deck.draw(2)); // Draw some cards for testing
            player2.sethand(deck.draw(2));
            
            round.zapzap(players, 0);
            expect(round.action).toBe(Round.ACTION_ZAPZAP);
            expect(round.score).toBeDefined();
        });

        it('should handle counteract when another player has lower points', () => {
            // Setup players with specific hands for testing
            const cards1 = deck.draw(2);
            const cards2 = deck.draw(1); // Less points than player1
            player1.sethand(cards1);
            player2.sethand(cards2);

            const players = [player1, player2];
            round.zapzap(players, 0);
            
            expect(round.score[0]).toBeGreaterThan(0); // Player1 should get penalty
            expect(round.score[1]).toBe(0); // Player2 should get 0 points
        });
    });

    describe('#next_turn', () => {
        it('should increment turn counter', () => {
            const initialTurn = round.turn;
            round.next_turn();
            expect(round.turn).toBe(initialTurn + 1);
        });
    });
});