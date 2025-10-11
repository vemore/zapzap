const { str_cards, print_players_hands, get_card_id, get_card_from_id, json_hand, get_cards_from_ids, get_card_points, check_play } = require('./utils.js');
const { decks } = require('cards');

describe('Utils', () => {
    let deck;

    beforeEach(() => {
        deck = new decks.StandardDeck({ jokers: 2 });
    });

    describe('str_cards', () => {
        it('should format cards as string', () => {
            const cards = [
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'K' }, suit: { unicode: '♥' } }
            ];
            expect(str_cards(cards)).toBe('A♠\tK♥\t');
        });

        it('should handle jokers', () => {
            const cards = [
                { rank: { shortName: 'Joker' }, suit: { unicode: null } }
            ];
            expect(str_cards(cards)).toBe('Joker\t');
        });
    });

    describe('get_card_id', () => {
        it('should return correct ID for regular cards', () => {
            const aceSpades = { rank: { shortName: 'A' }, suit: { unicode: '♠' } };
            const kingHearts = { rank: { shortName: 'K' }, suit: { unicode: '♥' } };
            const twoClubs = { rank: { shortName: '2' }, suit: { unicode: '♣' } };
            
            expect(get_card_id(aceSpades)).toBe(0);
            expect(get_card_id(kingHearts)).toBe(25);
            expect(get_card_id(twoClubs)).toBe(27);
        });

        it('should return correct ID for jokers', () => {
            const jokers = deck.findCards((card) => card.rank.shortName === 'Joker');
            expect(get_card_id(jokers[0], deck)).toBe(52);
            expect(get_card_id(jokers[1], deck)).toBe(53);
        });

        it('should return -1 for undefined card', () => {
            expect(get_card_id(undefined)).toBe(-1);
        });

        it('should handle invalid suits and ranks', () => {
            const invalidSuit = { rank: { shortName: 'A' }, suit: { unicode: '?' } };
            const invalidRank = { rank: { shortName: 'X' }, suit: { unicode: '♠' } };
            
            expect(get_card_id(invalidSuit)).toBe(-1);
            expect(get_card_id(invalidRank)).toBe(-1);
        });
    });

    describe('get_card_from_id', () => {
        it('should return correct card for regular IDs', () => {
            const card0 = get_card_from_id(0, deck); // Ace of Spades
            const card25 = get_card_from_id(25, deck); // King of Hearts
            
            expect(card0.rank.shortName).toBe('A');
            expect(card0.suit.unicode).toBe('♠');
            expect(card25.rank.shortName).toBe('K');
            expect(card25.suit.unicode).toBe('♥');
        });

        it('should return correct jokers', () => {
            const joker1 = get_card_from_id(52, deck);
            const joker2 = get_card_from_id(53, deck);
            
            expect(joker1.rank.shortName).toBe('Joker');
            expect(joker2.rank.shortName).toBe('Joker');
        });

        it('should return undefined for invalid ID', () => {
            expect(get_card_from_id(-1, deck)).toBeUndefined();
        });
    });

    describe('get_card_points', () => {
        it('should return correct points for number cards', () => {
            for (let i = 2; i <= 10; i++) {
                const card = { rank: { shortName: i.toString() } };
                expect(get_card_points(card, false)).toBe(i);
            }
        });

        it('should return correct points for face cards', () => {
            const jack = { rank: { shortName: 'J' } };
            const queen = { rank: { shortName: 'Q' } };
            const king = { rank: { shortName: 'K' } };
            const ace = { rank: { shortName: 'A' } };

            expect(get_card_points(jack, false)).toBe(11);
            expect(get_card_points(queen, false)).toBe(12);
            expect(get_card_points(king, false)).toBe(13);
            expect(get_card_points(ace, false)).toBe(1);
        });

        it('should handle jokers correctly', () => {
            const joker = { rank: { shortName: 'Joker' } };
            expect(get_card_points(joker, true)).toBe(25);
            expect(get_card_points(joker, false)).toBe(0);
        });
    });

    describe('check_play', () => {
        it('should validate same rank combinations', () => {
            const cards = [
                { rank: { shortName: 'K' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'K' }, suit: { unicode: '♥' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(true);
        });

        it('should validate suit sequences', () => {
            const cards = [
                { rank: { shortName: '7' }, suit: { unicode: '♠' } },
                { rank: { shortName: '8' }, suit: { unicode: '♠' } },
                { rank: { shortName: '9' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(true);
        });

        it('should validate sequences with jokers', () => {
            const cards = [
                { rank: { shortName: '7' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'Joker' }, suit: { unicode: null } },
                { rank: { shortName: '9' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(true);
        });

        it('should reject invalid plays', () => {
            const cards = [
                { rank: { shortName: '7' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'K' }, suit: { unicode: '♥' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(false);
        });

        it('should validate single card plays', () => {
            const cards = [
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(true);
        });

        it('should reject empty plays', () => {
            expect(check_play([], { hand: [] })).toBe(false);
        });
    });
});