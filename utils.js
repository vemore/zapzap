//const { Card } = require('./node_modules/cards/src/card/card.js');
//const { ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, joker } = require('./node_modules/cards/src/ranks/standard.js');
//const { spades, hearts, diamonds, clubs, none } = require('./node_modules/cards/src/suits.js');
const { ranks, suits, Card } = require('cards');

str_cards = function(hand) {
    var str_hand = "";
    hand.forEach(card => {
        str_hand += card.rank.shortName + (card.suit.unicode!=null?card.suit.unicode:"") + "\t";
    });
    return str_hand;
}
exports.str_cards = str_cards;

print_players_hands = function(players) {
    players.forEach(player => {
        console.log("Player " + player.name + " : " + str_cards(player.hand));
    });
}
exports.print_players_hands = print_players_hands;

get_card_id = function(card, deck=null) {
    if (card == undefined) {
        return -1;
    }
    if (card.rank.shortName=='Joker') {
        if (deck==null)
            return 54;
        var jokers = deck.findCards((card) => card.rank.shortName==="Joker");
        if (card==jokers[0])
            return 52;
        else if (card==jokers[1])
            return 53;
        else
            console.log("ERROR : unknown joker");
            return -1;
    }
    var card_id = 0;
    switch (card.suit.unicode) {
        case '♠': card_id = 0; break;
        case '♥': card_id = 13; break;
        case '♣': card_id = 2*13; break;
        case '♦': card_id = 3*13; break;
        default : console.log("ERROR : bad suit : " + card.suit.unicode); return -1;
    }
    switch (card.rank.shortName) {
        case 'A': card_id += 0; break;
        case 'J': card_id += 10; break;
        case 'Q': card_id += 11; break;
        case 'K': card_id += 12; break;
        default : card_id += parseInt(card.rank.shortName,10)-1; 
    }
    return card_id;
}
exports.get_card_id = get_card_id;

json_hand = function(hand, deck) {
    var json_ret = [];
    hand.forEach(card => {
        json_ret.push(get_card_id(card, deck));
    });
    //console.log(json_ret);
    return json_ret;
}
exports.json_hand = json_hand;

get_card_from_id = function(card_id, deck) {
    if (card_id==-1) {
        return undefined;
    }
    if (card_id>=52) {
        var jokers = deck.findCards((card) => card.rank.shortName==="Joker");
        return jokers[card_id-52];
    }

    var suit = undefined;
    var rank = undefined;
    //console.log("card_id: "+card_id+", card_id/13:"+(card_id/13));
    switch (Math.trunc(card_id/13)) {
        case 0: suit = suits.spades; break;
        case 1: suit = suits.hearts; break;
        case 2: suit = suits.clubs; break;
        case 3: suit = suits.diamonds; break;
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

    return deck.findCards((card) => card.rank===rank && card.suit===suit)[0];
}
exports.get_card_from_id = get_card_from_id;
 /*   
    return new Card(suit, rank);
*/



get_cards_from_ids = function(ids, deck) {
    var cards = [];
    ids.forEach(id => {
        cards.push(get_card_from_id(parseInt(id,10), deck));
    });
    return cards;
}
exports.get_cards_from_ids = get_cards_from_ids;

get_card_points = function(card, withJoker) {
    if (card.rank.shortName=='Joker') {
        if (withJoker)
            return 25;
        else
            return 0;
    }
    switch (card.rank.shortName) {
        case 'A': return 1;
        case 'J': return 11;
        case 'Q': return 12;
        case 'K': return 13;
        default : return parseInt(card.rank.shortName,10); 
    }
}
exports.get_card_points = get_card_points;

exports.check_play = function(cards, player) {
    // check size
    if (cards.length<1 || cards.length>player.hand.length) {
        console.log("check_play: bad card number "+cards.length);
        return false;
    } 
    // TODO check in cards belong to the player hand
    
    if (cards.length==1) {
        console.log("check_play: ok only one card");
        return true;
    }

    // check suit and rank
    var suit_check = true;
    if (cards.length<3) {
        suit_check = false;
    }
    var rank_check = true;
    var suit = undefined;
    var rank = undefined;
    
    cards.forEach(function(card){
        console.log("check card: rank="+card.rank+", suit="+card.suit);
        if (card.rank.shortName!="Joker") {
            if (suit == undefined) {
                suit = card.suit;
                rank = card.rank;
            } else {
                if (card.rank!=rank)
                    rank_check = false;
                if (card.suit!=suit)
                    suit_check = false;
            }
        }
    });

    // Check suit
    if (suit_check) {
        
        var card_value_list = [];
        var nb_joker = 0;
        cards.forEach(function(card){
            if (card.rank.shortName!="Joker") {
                card_value_list.push(get_card_points(card));
            } else {
                nb_joker++;
            }
        });
        card_value_list.sort((a, b) => (a - b));
        console.log("Check suit "+nb_joker+" Jokers, "+card_value_list);
        var value = card_value_list[0];
        for (var i = 1; i < card_value_list.length; i++) {
            value++;
            if (card_value_list[i]!=value) {
                if (nb_joker>0) {
                    nb_joker--;
                } else {
                    suit_check = false;
                    break;
                }
            }
        }
    }
    
    console.log("check_play: suit_check="+suit_check+", rank_check="+rank_check);
    return suit_check || rank_check;
}

