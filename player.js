const { str_cards, get_card_id, get_card_points } = require('./utils.js');

class Player {
    constructor(name, id) {
        if (name === null || name.trim() === '') {
            throw new Error('Name cannot be empty or null');
        }
        this._name = name;
        this._id = id;
        this._hand = [];
    }

    get hand() {
        return this._hand;
    }

    get id() {
        return this._id;
    }

    get name() {
        return this._name;
    }

    get hand_points_with_joker() {
        var points = 0;
        this._hand.forEach(card => {
            points += get_card_points(card, true);
        });
        return points;
    }

    get hand_points() {
        var points = 0;
        this._hand.forEach(card => {
            points += get_card_points(card, false);
        });
        return points;
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
                const logger = require('./logger');
                logger.error('Attempted to play card not in hand', {
                    card: str_cards([card]),
                    cardId: get_card_id(card),
                    playerName: this._name,
                    playerId: this._id
                });
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