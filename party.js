
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
        // draw new hand for each player
        this._players.forEach(player => {
            var cards = this._deck.draw(nb_cards_in_hand);
            console.log()
            player.sethand(cards);
        });
        // start the new round
        var round = new Round(nb_cards_in_hand, first_player, this._deck);
        this._rounds.push(round);

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
            players_array.push({"name": player.name, "nb_cards": player.hand.length});
        });
        var json = {
            "nb_players": this.nb_players,
            "current_turn": this.current_round.turn,
            "card_in_deck": this._deck.remainingLength,
            "last_card_played": json_hand(this.current_round.last_cards_played),
            "players": players_array
        }
        return JSON.stringify(json);
    }
}

exports.Party = Party;