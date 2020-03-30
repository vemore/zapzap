
class Round {
    constructor(nb_cards_in_hand, first_player, deck) {
        console.log("Create a new round : shuffle the deck");
        this._nb_cards_in_hand = nb_cards_in_hand;
        this._selected_card = undefined;
        this._deck = deck;
        this._turn = first_player;
        this._deck.shuffleAll();
        this._last_cards_played = this._deck.draw();
        this._cards_played = [];
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
        var draw_card;

        // case draw from deck
        if (card==undefined) {
            draw_card = this._deck.draw()[0];
        } else {
            // case draw from last cards played
            const index = this._last_cards_played.indexOf(card);
            if (index > -1) {
                this._last_cards_played.splice(index, 1)[0];
                draw_card = card;
            } else {
                console.log("ERROR : drawn card is not in last played cards");
                return undefined;
            }
        }
        
        this._last_cards_played.forEach(discarded_card => {
            this._deck.discard(discarded_card);
        });
        this._last_cards_played = this._cards_played;
        this._cards_played = [];
        return draw_card;
    }

    play_cards(cards) {
        //this._last_cards_played = this._cards_played;
        this._cards_played = cards;
    }

    next_turn() {
        this._turn++;
    }
}

exports.Round = Round;