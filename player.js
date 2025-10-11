const { str_cards, get_card_id, get_card_points } = require('./utils.js');
const { InvalidPlayerError, InvalidPlayError, ErrorCodes } = require('./gameError');
const logger = require('./logger');

class Player {
    constructor(name, id) {
        if (name === null || name === undefined || name.trim() === '') {
            throw new InvalidPlayerError('Invalid player name', {
                code: ErrorCodes.INVALID_PLAYER_COUNT,
                name: name,
                reason: 'Name cannot be empty or null'
            });
        }
        if (typeof id !== 'number' || id < 0) {
            throw new InvalidPlayerError('Invalid player ID', {
                code: ErrorCodes.INVALID_PLAYER_COUNT,
                id: id,
                reason: 'Player ID must be a non-negative number'
            });
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
        if (!Array.isArray(cards)) {
            throw new InvalidPlayError('Invalid hand', {
                code: ErrorCodes.INVALID_PLAYER_HAND,
                received: typeof cards,
                expected: 'array of cards'
            });
        }
        this._hand = cards;
    }

    play(cards) {
        if (!Array.isArray(cards) || cards.length === 0) {
            throw new InvalidPlayError('Invalid cards to play', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                received: typeof cards,
                cardsCount: Array.isArray(cards) ? cards.length : 0,
                expected: 'non-empty array of cards'
            });
        }

        const notInHand = [];
        cards.forEach(card => {
            const index = this._hand.indexOf(card);
            if (index > -1) {
                this._hand.splice(index, 1);
            } else {
                notInHand.push(card);
            }
        });

        if (notInHand.length > 0) {
            throw new InvalidPlayError('Attempted to play cards not in hand', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                invalidCards: notInHand.map(card => ({
                    card: str_cards([card]),
                    cardId: get_card_id(card)
                })),
                playerName: this._name,
                playerId: this._id,
                currentHand: str_cards(this._hand)
            });
        }
    }

    draw(card) {
        if (!card) {
            throw new InvalidPlayError('Cannot draw undefined card', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                playerName: this._name,
                playerId: this._id
            });
        }
        this._hand.push(card);
    }

    zapzap() {
        if (this._hand.length === 0) {
            throw new InvalidPlayError('Cannot zapzap with empty hand', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                playerName: this._name,
                playerId: this._id
            });
        }
        // TODO: implement zapzap logic
    }


}

exports.Player = Player;