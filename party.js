
const { Player } = require('./player.js');
const { Round } = require('./round.js');
const { json_hand } = require('./utils.js');

class Party {
    constructor(deck) {
        this._players = [];
        this._rounds = [];
        this._deck = deck;
    }

    get rounds() {
        return this._rounds;
    }

    get current_round() {
        return this._rounds[this._rounds.length - 1];
    }

    get players() {
        return this._players;
    }

    get deck() {
        return this._deck;
    }

    get nb_players() {
        return this._players.length;
    }

    start_round(nb_cards_in_hand, first_player) {
        const logger = require('./logger');

        // Validate input parameters
        if (nb_cards_in_hand < 1) {
            logger.error('Invalid number of cards', { nb_cards_in_hand });
            return null;
        }

        if (first_player < 0 || first_player >= this._players.length) {
            logger.error('Invalid first player', { first_player, nb_players: this._players.length });
            return null;
        }

        if (this._deck.remainingLength < nb_cards_in_hand * this._players.length) {
            logger.error('Not enough cards in deck', { 
                needed: nb_cards_in_hand * this._players.length,
                available: this._deck.remainingLength 
            });
            return null;
        }

        // start the new round
        var round = new Round(nb_cards_in_hand, first_player, this._deck);
        this._rounds.push(round);

        // draw new hand for each player
        this._players.forEach(player => {
            var cards = this._deck.draw(nb_cards_in_hand);
            logger.debug('Drawing cards for player', { 
                player: player.name,
                nb_cards: cards.length 
            });
            player.sethand(cards);
        });

        return round;
    }

    add_player(name) {
        var player = new Player(name, this._players.length);
        this._players.push(player);
        return player;
    }

    get json_string() {
        var players_array = [];
        this._players.forEach(player => {
            var json_player = {name: player.name, nb_cards: player.hand.length};
            if (this.current_round.action==Round.ACTION_ZAPZAP) {
                json_player.hand = json_hand(player.hand, this._deck);
                json_player.score = this.current_round.score[player.id];
            }
            players_array.push(json_player);
        });
        var json = {
            "nb_players": this.nb_players,
            "current_turn": this.current_round.turn,
            "card_in_deck": this._deck.remainingLength,
            "last_cards_played": json_hand(this.current_round.last_cards_played, this._deck),
            "cards_played": json_hand(this.current_round.cards_played, this._deck),
            "players": players_array,
            "action": this.current_round.action
        }


        return JSON.stringify(json);
    }
}

exports.Party = Party;