
class Round {
    constructor(nb_cards_in_hand, first_player, deck) {
        deck.shuffleAll();
        this._nb_cards_in_hand = nb_cards_in_hand;
        this._last_cards_played = deck.draw();
        this._selected_card = undefined;
        this._cards_played = undefined;
        this._deck = deck;
        this._turn = first_player;
    }

    get turn() {
        return this._turn;
    }

    get last_cards_played() {
        return this._last_cards_played;
    }

    get selected_card() {
        return this._selected_card;
    }

    get cards_played() {
        return this._cards_played;
    }

    select_card(card = undefined) {
        this._selected_card = card;
    }

    draw(card=undefined) {
        // case draw from deck
        if (card==undefined) {
            return this._deck.draw()[0];
        }
        // case draw from last cards played
        const index = array.indexOf(card);
        if (index > -1) {
            this._last_cards_played.splice(index, 1)[0];
        } else {
            console.log("ERROR : drawn card is not in last played cards");
            return undefined;
        }
        return card;
    }

    play_cards(cards) {
        this._last_cards_played = this._cards_played;
        this._cards_played = [];
    }

    next_turn() {
        this._turn++;
    }
}

exports.Round = Round;