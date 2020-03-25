
class Round {
    constructor(nb_cards_in_hand, first_player, deck) {
        deck.shuffleAll();
        this._nb_cards_in_hand = nb_cards_in_hand;
        this._last_cards_played = deck.draw();
        this._deck = deck;
        this._turn = first_player;
    }

    get turn() {
        return this._turn;
    }

    get last_cards_played() {
        return this._last_cards_played;
    }

    next_turn() {
        this._turn++;
    }
}

exports.Round = Round;