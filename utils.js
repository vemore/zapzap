const { ranks, suits, Card } = require('cards');
const logger = require('./logger');

function str_cards(hand) {
    let str_hand = "";
    hand.forEach(card => {
        str_hand += card.rank.shortName + (card.suit.unicode != null ? card.suit.unicode : "") + "\t";
    });
    return str_hand;
}

function print_players_hands(players) {
    players.forEach(player => {
        logger.debug('Player hand', {
            player: player.name,
            hand: str_cards(player.hand)
        });
    });
}

function get_card_id(card, deck = null) {
    if (!card) {
        return -1;
    }

    if (card.rank.shortName == 'Joker') {
        if (!deck) {
            return 54;
        }
        const jokers = deck.findCards((card) => card.rank.shortName === "Joker");
        if (card == jokers[0]) {
            return 52;
        } else if (card == jokers[1]) {
            return 53;
        } else {
            logger.error('Unknown joker');
            return -1;
        }
    }

    let card_id = 0;
    switch (card.suit.unicode) {
        case '♠': card_id = 0; break;
        case '♥': card_id = 13; break;
        case '♣': card_id = 2*13; break;
        case '♦': card_id = 3*13; break;
        default:
            logger.error('Invalid card suit', { suit: card.suit.unicode });
            return -1;
    }

    switch (card.rank.shortName) {
        case 'A': card_id += 0; break;
        case 'J': card_id += 10; break;
        case 'Q': card_id += 11; break;
        case 'K': card_id += 12; break;
        default:
            const value = parseInt(card.rank.shortName, 10);
            if (isNaN(value)) {
                logger.error('Invalid card rank', { rank: card.rank.shortName });
                return -1;
            }
            card_id += value - 1;
    }

    return card_id;
}

function json_hand(hand, deck) {
    const json_ret = [];
    hand.forEach(card => {
        json_ret.push(get_card_id(card, deck));
    });
    return json_ret;
}

function get_card_from_id(card_id, deck) {
    if (card_id == -1) {
        return undefined;
    }
    if (card_id >= 52) {
        const jokers = deck.findCards((card) => card.rank.shortName === "Joker");
        return jokers[card_id - 52];
    }

    let suit;
    let rank;

    switch (Math.trunc(card_id/13)) {
        case 0: suit = suits.spades; break;
        case 1: suit = suits.hearts; break;
        case 2: suit = suits.clubs; break;
        case 3: suit = suits.diamonds; break;
        default:
            logger.error('Invalid card ID', { id: card_id });
            return undefined;
    }

    switch (card_id % 13) {
        case 0: rank = ranks.ace; break;
        case 1: rank = ranks.two; break;
        case 2: rank = ranks.three; break;
        case 3: rank = ranks.four; break;
        case 4: rank = ranks.five; break;
        case 5: rank = ranks.six; break;
        case 6: rank = ranks.seven; break;
        case 7: rank = ranks.eight; break;
        case 8: rank = ranks.nine; break;
        case 9: rank = ranks.ten; break;
        case 10: rank = ranks.jack; break;
        case 11: rank = ranks.queen; break;
        case 12: rank = ranks.king; break;
        default:
            logger.error('Invalid card ID remainder', { remainder: card_id % 13 });
            return undefined;
    }

    return deck.findCards((card) => card.rank === rank && card.suit === suit)[0];
}

function get_cards_from_ids(ids, deck) {
    const cards = [];
    ids.forEach(id => {
        const card = get_card_from_id(parseInt(id, 10), deck);
        if (card) {
            cards.push(card);
        } else {
            logger.error('Invalid card ID', { id });
        }
    });
    return cards;
}

function get_card_points(card, withJoker) {
    if (card.rank.shortName == 'Joker') {
        return withJoker ? 25 : 0;
    }
    switch (card.rank.shortName) {
        case 'A': return 1;
        case 'J': return 11;
        case 'Q': return 12;
        case 'K': return 13;
        default: return parseInt(card.rank.shortName, 10);
    }
}

function check_play(cards, player) {
    if (cards.length < 1 || cards.length > player.hand.length) {
        logger.debug('Invalid play: bad card number', { length: cards.length });
        return false;
    }

    if (cards.length == 1) {
        logger.debug('Valid play: single card');
        return true;
    }

    let sameRankCheck = true;
    let suitSequenceCheck = cards.length >= 3;
    let firstNonJoker = cards.find(card => card.rank.shortName !== 'Joker');
    
    if (!firstNonJoker) {
        logger.debug('Valid play: all jokers');
        return true;
    }

    let suit = firstNonJoker.suit;
    let rank = firstNonJoker.rank;

    let jokerCount = cards.filter(card => card.rank.shortName === 'Joker').length;
    let normalCards = cards.filter(card => card.rank.shortName !== 'Joker');

    sameRankCheck = normalCards.every(card => card.rank.shortName === rank.shortName);

    if (suitSequenceCheck && !sameRankCheck) {
        let cardValues = normalCards
            .map(card => get_card_points(card, false))
            .sort((a, b) => a - b);

        let expectedValue = cardValues[0];
        let gapsToFill = 0;

        for (let i = 1; i < cardValues.length; i++) {
            let diff = cardValues[i] - expectedValue - 1;
            if (diff > 0) {
                gapsToFill += diff;
            }
            expectedValue = cardValues[i];
        }

        suitSequenceCheck = (gapsToFill <= jokerCount) && 
                          normalCards.every(card => card.suit.unicode === suit.unicode);
    }

    logger.debug('Play validation result', {
        sameRank: sameRankCheck,
        suitSequence: suitSequenceCheck,
        jokers: jokerCount
    });

    return sameRankCheck || suitSequenceCheck;
}

module.exports = {
    str_cards,
    print_players_hands,
    get_card_id,
    get_card_from_id,
    json_hand,
    get_cards_from_ids,
    get_card_points,
    check_play
};
