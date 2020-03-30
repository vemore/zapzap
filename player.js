const { str_cards, get_card_id } = require('./utils.js');

class Player {
    constructor(name, id) {
        this._name = name;
        this._id = id;
        this._hand = [];
    }

    get hand() {
        return this._hand;
    }

    get name() {
        return this._name;
    }

    sethand(cards) {
        this._hand = cards;
    }

    play(cards) {
        cards.forEach(card => {
            const index = this._hand.indexOf(card);
            if (index > -1) {
                this._hand.splice(index, 1)
            } else {
                console.log(
                    "ERROR : play card " + str_cards([card]) + " (" + get_card_id(card)+
                    ") which is not in player hand");
            }
        });
    }

    draw(card) {
        this._hand.push(card);
    }

    zapzap() {
        // TODO
    }


}

exports.Player = Player;