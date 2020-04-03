
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
        this._player_action = Round.ACTION_DRAW;
        this._score = [];
    }



    get turn() {
        return this._turn;
    }

    get action() {
        return this._player_action;
    }

    get score() {
        return this._score;
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
        this._player_action = Round.ACTION_DRAW;
        return draw_card;
    }

    play_cards(cards) {
        //this._last_cards_played = this._cards_played;
        this._cards_played = cards;
        this._player_action = Round.ACTION_PLAY;
    }

    zapzap(players, id_zapzap) {
        this._player_action = Round.ACTION_ZAPZAP;
        this._score = [];

        var zapzap_score = players[id_zapzap].hand_points;
        var counteract = false;

        // Test zapzap counteract
        players.forEach(player => {
            if (player.hand_points <= zapzap_score && player.id != id_zapzap) {
                zapzap_score = player.hand_points;
                counteract = true;
            }
        });

        // Compute scores
        players.forEach(player => {
            if (player.hand_points == zapzap_score) {
                this._score[player.id] == 0;
            } else {
                this._score[player.id] = player.hand_points_with_joker;
            }
        });
        if (counteract) {
            this._score[id_zapzap] = player[id_zapzap].hand_points_with_joker + (players.length*4);
        }
    }

    next_turn() {
        this._turn++;
    }
}


Round.ACTION_DRAW = "draw";
Round.ACTION_PLAY = "play";
Round.ACTION_ZAPZAP = "zapzap";

exports.Round = Round;