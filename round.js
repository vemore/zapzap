
const { InvalidGameStateError, InvalidPlayError, ErrorCodes } = require('./gameError');
const logger = require('./logger');

class Round {
    constructor(nb_cards_in_hand, first_player, deck) {
        logger.info('Creating new round and shuffling deck');

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
            if (this._deck.remainingLength === 0) {
                throw new InvalidGameStateError('Cannot draw from empty deck', {
                    code: ErrorCodes.INVALID_DECK_STATE,
                    action: 'draw',
                    deckSize: this._deck.remainingLength
                });
            }
            draw_card = this._deck.draw()[0];
        } else {
            // case draw from last cards played
            const index = this._last_cards_played.indexOf(card);
            if (index > -1) {
                this._last_cards_played.splice(index, 1)[0];
                draw_card = card;
            } else {
                throw new InvalidPlayError('Selected card is not in last played cards', {
                    code: ErrorCodes.INVALID_PLAY_CARDS,
                    selectedCard: card,
                    lastCardsPlayed: this._last_cards_played
                });
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
        if (!Array.isArray(cards) || cards.length === 0) {
            throw new InvalidPlayError('Invalid cards played', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                cards: cards,
                expected: 'non-empty array of cards'
            });
        }
        this._cards_played = cards;
        this._player_action = Round.ACTION_PLAY;
    }

    zapzap(players, id_zapzap) {
        if (!Array.isArray(players) || players.length === 0) {
            throw new InvalidGameStateError('Invalid players array', {
                code: ErrorCodes.INVALID_GAME_STATE,
                playersLength: players?.length
            });
        }

        if (id_zapzap < 0 || id_zapzap >= players.length) {
            throw new InvalidPlayError('Invalid zapzap player id', {
                code: ErrorCodes.INVALID_PLAY_CARDS,
                id: id_zapzap,
                validRange: `0-${players.length - 1}`
            });
        }

        this._player_action = Round.ACTION_ZAPZAP;
        this._score = [];

        var zapzap_score = players[id_zapzap].hand_points;
        var counteract = false;
        var lowest_score = Infinity;

        // Find lowest score and check for counteract
        players.forEach(player => {
            if (player.hand_points < lowest_score) {
                lowest_score = player.hand_points;
            }
        });

        // Check if someone has a lower score than zapzap player
        counteract = players.some(player => 
            player.id !== id_zapzap && player.hand_points <= zapzap_score
        );

        // Compute scores
        players.forEach(player => {
            if (player.hand_points === lowest_score) {
                this._score[player.id] = 0;
            } else if (player.id === id_zapzap && counteract) {
                // If counteracted, zapzap player gets penalty points
                this._score[player.id] = player.hand_points_with_joker + (players.length * 4);
            } else {
                // Other players just get their hand points
                this._score[player.id] = player.hand_points_with_joker;
            }
        });
    }

    next_turn() {
        this._turn++;
    }
}


Round.ACTION_DRAW = "draw";
Round.ACTION_PLAY = "play";
Round.ACTION_ZAPZAP = "zapzap";

exports.Round = Round;