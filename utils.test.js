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

        it('should handle invalid input types', () => {
            expect(() => str_cards(null)).toThrow();
            expect(() => str_cards(undefined)).toThrow();
            expect(() => str_cards('not an array')).toThrow();
            expect(() => str_cards(42)).toThrow();
        });

        it('should handle invalid card objects', () => {
            expect(() => str_cards([{ not: 'a card' }])).toThrow();
            expect(() => str_cards([null])).toThrow();
            expect(() => str_cards([undefined])).toThrow();
            expect(() => str_cards([{ rank: null, suit: null }])).toThrow();
        });

        it('should handle empty arrays', () => {
            expect(str_cards([])).toBe('');
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

        it('should handle invalid input types', () => {
            expect(get_card_from_id(null, deck)).toBeUndefined();
            expect(get_card_from_id(undefined, deck)).toBeUndefined();
            expect(get_card_from_id('not a number', deck)).toBeUndefined();
            expect(get_card_from_id(NaN, deck)).toBeUndefined();
        });

        it('should handle missing deck', () => {
            expect(get_card_from_id(0)).toBeUndefined();
            expect(get_card_from_id(52)).toBeUndefined();
        });

        it('should handle out of range IDs', () => {
            expect(get_card_from_id(-1, deck)).toBeUndefined();
            expect(get_card_from_id(54, deck)).toBeUndefined();
            expect(get_card_from_id(100, deck)).toBeUndefined();
        });

        it('should handle deck without jokers', () => {
            const nojokerdeck = new decks.StandardDeck({ jokers: 0 });
            expect(get_card_from_id(52, nojokerdeck)).toBeUndefined();
            expect(get_card_from_id(53, nojokerdeck)).toBeUndefined();
        });
    });

    describe('get_cards_from_ids', () => {
        it('should return correct cards for valid IDs', () => {
            const cards = get_cards_from_ids(['0', '25', '52'], deck);
            expect(cards.length).toBe(3);
            expect(cards[0].rank.shortName).toBe('A');
            expect(cards[0].suit.unicode).toBe('♠');
            expect(cards[1].rank.shortName).toBe('K');
            expect(cards[1].suit.unicode).toBe('♥');
            expect(cards[2].rank.shortName).toBe('Joker');
        });

        it('should handle invalid input types', () => {
            expect(get_cards_from_ids(null, deck)).toEqual([]);
            expect(get_cards_from_ids(undefined, deck)).toEqual([]);
            expect(get_cards_from_ids('not an array', deck)).toEqual([]);
            expect(get_cards_from_ids([], null)).toEqual([]);
        });

        it('should handle invalid card IDs', () => {
            const cards = get_cards_from_ids(['invalid', '999', '-1'], deck);
            expect(cards).toEqual([]);
        });

        it('should handle mixed valid and invalid IDs', () => {
            const cards = get_cards_from_ids(['0', 'invalid', '52'], deck);
            expect(cards.length).toBe(2);
            expect(cards[0].rank.shortName).toBe('A');
            expect(cards[1].rank.shortName).toBe('Joker');
        });

        it('should handle empty array', () => {
            expect(get_cards_from_ids([], deck)).toEqual([]);
        });

        it('should handle non-numeric strings', () => {
            expect(get_cards_from_ids(['abc', 'def'], deck)).toEqual([]);
        });
    });

    describe('json_hand', () => {
        it('should convert hand to array of card IDs', () => {
            const hand = [
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'K' }, suit: { unicode: '♥' } },
                { rank: { shortName: 'Joker' }, suit: { unicode: null } }
            ];
            const ids = json_hand(hand, deck);
            expect(ids).toEqual([0, 25, 52]);
        });

        it('should handle empty hand', () => {
            expect(json_hand([], deck)).toEqual([]);
        });

        it('should handle invalid input types', () => {
            expect(() => json_hand(null, deck)).toThrow();
            expect(() => json_hand(undefined, deck)).toThrow();
            expect(() => json_hand('not an array', deck)).toThrow();
        });

        it('should handle invalid cards in hand', () => {
            const hand = [
                { rank: { shortName: 'X' }, suit: { unicode: '?' } },
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } }
            ];
            expect(() => json_hand(hand, deck)).toThrow();
        });

        it('should handle missing deck', () => {
            const hand = [{ rank: { shortName: 'A' }, suit: { unicode: '♠' } }];
            const result = json_hand(hand);
            expect(result).toEqual([0]);
        });

        it('should handle deck without jokers', () => {
            const nojokerdeck = new decks.StandardDeck({ jokers: 0 });
            const hand = [
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'Joker' }, suit: { unicode: null } }
            ];
            expect(() => json_hand(hand, nojokerdeck)).toThrow();
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

        it('should handle invalid input', () => {
            expect(get_card_points(null)).toBe(0);
            expect(get_card_points(undefined)).toBe(0);
            expect(get_card_points({})).toBe(0);
            expect(get_card_points({ rank: {} })).toBe(0);
            expect(get_card_points({ rank: { shortName: null } })).toBe(0);
        });

        it('should handle invalid ranks', () => {
            const invalidCard = { rank: { shortName: 'X' } };
            const invalidNumber = { rank: { shortName: '11' } };
            expect(get_card_points(invalidCard)).toBe(0);
            expect(get_card_points(invalidNumber)).toBe(0);
        });

        it('should handle errors in points calculation', () => {
            const badCard = { rank: { shortName: { toString: () => { throw new Error(); } } } };
            expect(get_card_points(badCard)).toBe(0);
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

        it('should handle invalid input types', () => {
            expect(check_play(null, { hand: [] })).toBe(false);
            expect(check_play(undefined, { hand: [] })).toBe(false);
            expect(check_play('not an array', { hand: [] })).toBe(false);
            expect(check_play([], null)).toBe(false);
            expect(check_play([], undefined)).toBe(false);
        });

        it('should handle invalid player hands', () => {
            const cards = [{ rank: { shortName: 'A' }, suit: { unicode: '♠' } }];
            expect(check_play(cards, {})).toBe(false);
            expect(check_play(cards, { hand: null })).toBe(false);
            expect(check_play(cards, { hand: 'not an array' })).toBe(false);
        });

        it('should handle invalid card objects in play', () => {
            const cards = [
                { rank: { shortName: 'A' }, suit: { unicode: '♠' } },
                null,
                { rank: null, suit: null }
            ];
            expect(check_play(cards, { hand: cards })).toBe(false);
        });

        it('should handle all jokers play', () => {
            const cards = [
                { rank: { shortName: 'Joker' }, suit: { unicode: null } },
                { rank: { shortName: 'Joker' }, suit: { unicode: null } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(true);
        });

        it('should handle invalid suit sequences', () => {
            const cards = [
                { rank: { shortName: '7' }, suit: { unicode: '♠' } },
                { rank: { shortName: '8' }, suit: { unicode: '♥' } },
                { rank: { shortName: '9' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(false);
        });

        it('should handle too many gaps in sequence', () => {
            const cards = [
                { rank: { shortName: '2' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'Joker' }, suit: { unicode: null } },
                { rank: { shortName: '9' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(false);
        });

        it('should handle invalid points in sequence', () => {
            const cards = [
                { rank: { shortName: '7' }, suit: { unicode: '♠' } },
                { rank: { shortName: 'X' }, suit: { unicode: '♠' } },
                { rank: { shortName: '9' }, suit: { unicode: '♠' } }
            ];
            expect(check_play(cards, { hand: cards })).toBe(false);
        });
    });
});