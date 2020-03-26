//const { Card } = require('./node_modules/cards/src/card/card.js');
//const { ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, joker } = require('./node_modules/cards/src/ranks/standard.js');
//const { spades, hearts, diamonds, clubs, none } = require('./node_modules/cards/src/suits.js');
const { ranks, suits, Card } = require('cards');

print_hand = function(hand) {
    var str_hand = "";
    hand.forEach(card => {
        str_hand += card.rank.shortName + (card.suit.unicode!=null?card.suit.unicode:"") + "\t";
    });
    return str_hand;
}
exports.print_hand = print_hand;

print_players_hands = function(players) {
    players.forEach(player => {
        console.log("Player " + player.name + " : " + print_hand(player.hand));
    });
}
exports.print_players_hands = print_players_hands;

get_card_id = function(card) {
    if (card == undefined) {
        return -1;
    }
    var card_id = 0;
    switch (card.suit.unicode) {
        case '♠': card_id = 0; break;
        case '♥': card_id = 13; break;
        case '♣': card_id = 2*13; break;
        case '♦': card_id = 3*13; break;
        default : card_id = 4*13; 
    }
    switch (card.rank.shortName) {
        case 'A': card_id += 0; break;
        case 'J': card_id += 10; break;
        case 'Q': card_id += 11; break;
        case 'K': card_id += 12; break;
        case 'Jocker': card_id += 1; break;
        default : card_id += card.rank.shortName-1; 
    }
    return card_id;
}
exports.get_card_id = get_card_id;

exports.json_hand = function(hand) {
    var json_ret = []
    hand.forEach(card => {
        json_ret.push(get_card_id(card));
    });
    console.log(json_ret);
    return json_ret;
}

get_card_from_id = function(card_id) {
    if (card_id==-1) {
        return undefined;
    }

    var suit = undefined;
    var rank = undefined;
    switch (card_id/13) {
        case 0: suit = suits.spades; break;
        case 1: suit = suits.hearts; break;
        case 2: suit = suits.diamonds; break;
        case 3: suit = suits.clubs; break;
        default: suit = suits.none;
    }
    switch (card_id%13) {
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
        default : rank = ranks.joker; break;
    }
    return new Card(suit, rank);
}
exports.get_card_from_id = get_card_from_id;

get_cards_from_ids = function(ids) {
    var cards = [];
    ids.forEach(id => {
        cards.push(get_card_from_id(id));
    });
    return cards;
}
exports.get_cards_from_ids = get_cards_from_ids;

exports.check_play = function(cards, player) {
    // check size
    if (cards.length<1 || cards.length>player.hand.length) {
        return false;
    } 
    // TODO check in cards belong to the player hand
    
    if (cards.length<1) {
        return true;
    }

    // check suit and rank
    var suit_check = true;
    var rank_check = true;
    var suit = cards[0].suit;
    var rank = cards[0].rank;
    cards.forEach(function(card){
        if (card.rank!=rank && card.rank!=ranks.jocker)
            rank_check = false;
        if (card.suit!=suit && card.rank!=ranks.jocker)
            suit_check = false;
    });

    // TODO check suit

    return suit_check || rank_check;
}

exports.get_cards_from_player_hand = function(player, cards) {

}