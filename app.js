
const morgan = require('morgan');
const logger = require('./logger');
const { decks } = require('cards');
const { Party } = require('./party.js');
const { Round } = require('./round.js');
const { print_players_hands, str_cards, json_hand, check_play, get_card_from_id, get_card_id, get_cards_from_ids } = require('./utils.js');

// Create a standard 52 card deck + 2 jokers
const deck = new decks.StandardDeck({ jokers: 2 });

// Create party
const party = new Party(deck);

// Add players
party.add_player("Vincent");
party.add_player("Thibaut");
party.add_player("Simon  ");
party.add_player("Lyo    ");
party.add_player("Laurent");

// Start new round with 5 cards
var round = party.start_round(10, 0);

// print party status
print_players_hands(party.players);
logger.info('Game initialized', {
    turn: party.current_round.turn,
    players: party.nb_players
});

const express = require('express');
const events = require('events');
var emitter = new events.EventEmitter();
var app = express();
app.use('/node_modules/deck-of-cards', express.static('node_modules/deck-of-cards'));
app.use('/node_modules/jquery/dist', express.static('node_modules/jquery/dist'));
app.use('/public', express.static('public'));
app.use(morgan('dev')); // Use morgan HTTP logger

// =============================================================================
// VALIDATION HELPERS
// =============================================================================

/**
 * Validate player ID is within valid range
 * @param {string|number} id - Player ID from request
 * @returns {{valid: boolean, playerId?: number, error?: object}}
 */
function validatePlayerId(id) {
    const playerId = parseInt(id, 10);

    if (isNaN(playerId)) {
        return {
            valid: false,
            error: {
                status: 400,
                body: {
                    error: 'Invalid player ID format',
                    code: 'INVALID_PLAYER_ID_FORMAT',
                    details: { provided: id, expected: 'integer 0-4' }
                }
            }
        };
    }

    if (playerId < 0 || playerId >= party.nb_players) {
        return {
            valid: false,
            error: {
                status: 400,
                body: {
                    error: 'Player ID out of bounds',
                    code: 'INVALID_PLAYER_ID',
                    details: {
                        provided: playerId,
                        valid_range: `0-${party.nb_players - 1}`
                    }
                }
            }
        };
    }

    return { valid: true, playerId };
}

/**
 * Validate it's the player's turn
 * @param {number} playerId - Player ID
 * @returns {{valid: boolean, error?: object}}
 */
function validatePlayerTurn(playerId) {
    const currentPlayer = party.current_round.turn % party.nb_players;

    if (currentPlayer !== playerId) {
        return {
            valid: false,
            error: {
                status: 403,
                body: {
                    error: 'Not your turn',
                    code: 'INVALID_TURN',
                    details: {
                        your_id: playerId,
                        current_player: currentPlayer,
                        current_turn: party.current_round.turn
                    }
                }
            }
        };
    }

    return { valid: true };
}

/**
 * Validate action state allows the requested action
 * @param {string} expectedAction - Expected action state (Round.ACTION_DRAW or Round.ACTION_PLAY)
 * @returns {{valid: boolean, error?: object}}
 */
function validateActionState(expectedAction) {
    const currentAction = party.current_round.action;

    if (currentAction !== expectedAction) {
        return {
            valid: false,
            error: {
                status: 403,
                body: {
                    error: 'Invalid action for current state',
                    code: 'INVALID_ACTION_STATE',
                    details: {
                        current_state: currentAction,
                        expected_state: expectedAction
                    }
                }
            }
        };
    }

    return { valid: true };
}

/**
 * Validate card IDs from query parameter
 * @param {*} cardsParam - Cards parameter from req.query
 * @returns {{valid: boolean, cardIds?: number[], error?: object}}
 */
function validateCardIds(cardsParam) {
    if (!cardsParam) {
        return {
            valid: false,
            error: {
                status: 400,
                body: {
                    error: 'Missing cards parameter',
                    code: 'MISSING_CARDS'
                }
            }
        };
    }

    // Parse card IDs
    let cardIds;
    try {
        if (Array.isArray(cardsParam)) {
            cardIds = cardsParam.map(id => parseInt(id, 10));
        } else {
            cardIds = [parseInt(cardsParam, 10)];
        }
    } catch (err) {
        return {
            valid: false,
            error: {
                status: 400,
                body: {
                    error: 'Invalid cards format',
                    code: 'INVALID_CARDS_FORMAT',
                    details: { message: err.message }
                }
            }
        };
    }

    // Validate all IDs are valid numbers in range 0-53
    const invalidCards = cardIds.filter(id => isNaN(id) || id < 0 || id > 53);
    if (invalidCards.length > 0) {
        return {
            valid: false,
            error: {
                status: 400,
                body: {
                    error: 'Invalid card IDs',
                    code: 'INVALID_CARD_IDS',
                    details: {
                        invalid: invalidCards,
                        valid_range: '0-53'
                    }
                }
            }
        };
    }

    return { valid: true, cardIds };
}

// =============================================================================
// ROUTES
// =============================================================================

app.get('/suscribeupdate', function(req, res){
	res.writeHead(200, {
		'Content-Type': 'text/event-stream',
		'Cache-Control': 'no-cache',
		Connection: 'keep-alive'
	});

	// Heartbeat
	const nln = function() {
		res.write('\n');
	};
    const hbt = setInterval(nln, 15000);
    
    var onEvent = function(data) {
        res.write('retry: 500\n');
		res.write('event: event\n');
		res.write(`data: ${JSON.stringify(data)}\n\n`);
    }

    emitter.on('event', onEvent);
    
    // Clear heartbeat and listener
    req.on('close', function() {
		clearInterval(hbt);
		emitter.removeListener('event', onEvent);
	});
});

// VIEW
app.get('/', function(req, res) {
    // Validate player ID
    const validation = validatePlayerId(req.query.id);
    if (!validation.valid) {
        return res.status(validation.error.status).send(
            `Invalid player ID. Please use: http://localhost:9999/?id=0 (valid IDs: 0-${party.nb_players - 1})`
        );
    }

    res.render('hand.ejs', {"player": validation.playerId});
});



// HAND
app.get('/player/:id/hand', function(req, res) {
    // Validate player ID
    const validation = validatePlayerId(req.params.id);
    if (!validation.valid) {
        return res.status(validation.error.status).json(validation.error.body);
    }

    const player = party.players[validation.playerId];

    res.json(json_hand(player.hand, party.deck));
});

// PLAY
app.get('/player/:id/play', function(req, res) {
    // Validate player ID
    const playerValidation = validatePlayerId(req.params.id);
    if (!playerValidation.valid) {
        return res.status(playerValidation.error.status).json(playerValidation.error.body);
    }
    const playerId = playerValidation.playerId;
    const player = party.players[playerId];

    // Validate it's player's turn
    const turnValidation = validatePlayerTurn(playerId);
    if (!turnValidation.valid) {
        logger.warn('Play attempt on wrong turn', {
            player: player.name,
            playerId,
            currentTurn: party.current_round.turn
        });
        return res.status(turnValidation.error.status).json(turnValidation.error.body);
    }

    // Validate action state (must be in DRAW state to play cards)
    const stateValidation = validateActionState(Round.ACTION_DRAW);
    if (!stateValidation.valid) {
        logger.warn('Play attempt in wrong state', {
            player: player.name,
            currentState: party.current_round.action
        });
        return res.status(stateValidation.error.status).json(stateValidation.error.body);
    }

    // Validate cards parameter
    const cardsValidation = validateCardIds(req.query.cards);
    if (!cardsValidation.valid) {
        logger.warn('Invalid cards parameter', {
            player: player.name,
            cards: req.query.cards
        });
        return res.status(cardsValidation.error.status).json(cardsValidation.error.body);
    }

    // Get card objects from IDs
    const cards = get_cards_from_ids(cardsValidation.cardIds, party.deck);

    // Validate card combination
    if (!check_play(cards, player)) {
        logger.warn('Invalid card combination', {
            turn: party.current_round.turn,
            player: player.name,
            cards: str_cards(cards)
        });
        return res.status(400).json({
            error: 'Invalid card combination',
            code: 'INVALID_PLAY',
            details: {
                cards_attempted: cardsValidation.cardIds,
                hint: 'Must be: single card, 2+ same rank, or 3+ same suit sequence'
            }
        });
    }

    // Execute play
    player.play(cards);
    party.current_round.play_cards(cards);

    logger.info('Player played cards', {
        turn: party.current_round.turn,
        player: player.name,
        cards: str_cards(cards)
    });

    // Emit event for SSE update
    emitter.emit('event', {id: req.params.id});

    // Return updated hand
    res.json({
        success: true,
        hand: json_hand(player.hand, party.deck)
    });
});


// DRAW
app.get('/player/:id/draw', function(req, res) {
    // Validate player ID
    const playerValidation = validatePlayerId(req.params.id);
    if (!playerValidation.valid) {
        return res.status(playerValidation.error.status).json(playerValidation.error.body);
    }
    const playerId = playerValidation.playerId;
    const player = party.players[playerId];

    // Validate it's player's turn
    const turnValidation = validatePlayerTurn(playerId);
    if (!turnValidation.valid) {
        logger.warn('Draw attempt on wrong turn', {
            player: player.name,
            playerId,
            currentTurn: party.current_round.turn
        });
        return res.status(turnValidation.error.status).json(turnValidation.error.body);
    }

    // Validate action state (must be in PLAY state to draw)
    const stateValidation = validateActionState(Round.ACTION_PLAY);
    if (!stateValidation.valid) {
        logger.warn('Draw attempt in wrong state', {
            player: player.name,
            currentState: party.current_round.action
        });
        return res.status(stateValidation.error.status).json(stateValidation.error.body);
    }

    // Validate card parameter
    if (!req.query.card) {
        return res.status(400).json({
            error: 'Missing card parameter',
            code: 'MISSING_CARD',
            details: {
                hint: 'Use card=deck or card=<cardId>'
            }
        });
    }

    // Parse card to draw
    let cardToDraw = undefined;
    if (req.query.card !== "deck") {
        const cardId = parseInt(req.query.card, 10);
        if (isNaN(cardId) || cardId < 0 || cardId > 53) {
            return res.status(400).json({
                error: 'Invalid card ID',
                code: 'INVALID_CARD_ID',
                details: {
                    provided: req.query.card,
                    valid_range: '0-53 or "deck"'
                }
            });
        }
        cardToDraw = get_card_from_id(cardId, party.deck);
    }

    // Execute draw (will validate card is in last_cards_played)
    const drawnCard = party.current_round.draw(cardToDraw);

    if (!drawnCard) {
        logger.error('Draw failed', {
            player: player.name,
            requestedCard: req.query.card
        });
        return res.status(400).json({
            error: 'Card not available to draw',
            code: 'CARD_NOT_AVAILABLE',
            details: {
                requested: req.query.card,
                available: json_hand(party.current_round.last_cards_played, party.deck)
            }
        });
    }

    player.draw(drawnCard);

    // Reshuffle discard pile if deck is empty
    if (party.deck.remainingLength < 1) {
        party.deck.shuffleDiscard();
        logger.info('Deck reshuffled');
    }

    logger.info('Player drew card', {
        turn: party.current_round.turn,
        player: player.name,
        card: str_cards([drawnCard])
    });

    // Advance turn
    party.current_round.next_turn();

    // Emit event for SSE update
    emitter.emit('event', {id: req.params.id});

    // Return drawn card and updated hand
    res.json({
        draw: get_card_id(drawnCard, party.deck),
        hand: json_hand(player.hand, party.deck)
    });
});

// ZAPZAP
app.get('/player/:id/zapzap', function(req, res) {
    // Validate player ID
    const playerValidation = validatePlayerId(req.params.id);
    if (!playerValidation.valid) {
        return res.status(playerValidation.error.status).json(playerValidation.error.body);
    }
    const playerId = playerValidation.playerId;
    const player = party.players[playerId];

    // Validate hand points
    if (player.hand_points > 5) {
        logger.warn('ZapZap attempt with high hand', {
            player: player.name,
            hand_points: player.hand_points
        });
        return res.status(400).json({
            error: 'Hand value too high for ZapZap',
            code: 'INVALID_ZAPZAP',
            details: {
                your_hand_points: player.hand_points,
                max_allowed: 5
            }
        });
    }

    // Execute ZapZap
    party.current_round.zapzap(party.players, req.params.id);

    logger.info('Player called ZapZap', {
        turn: party.current_round.turn,
        player: player.name,
        hand_points: player.hand_points
    });
    print_players_hands(party.players);

    // Emit event for SSE update
    emitter.emit('event', {id: req.params.id});

    res.json({
        success: true,
        hand_points: player.hand_points
    });
});



app.get('/party', function(req, res) {
    res.setHeader('Content-Type', 'text/json');
    res.send(party.json_string);
});

// 404 handler
app.use(function(req, res, next){
    res.status(404).json({
        error: 'Not Found',
        code: 'ROUTE_NOT_FOUND',
        path: req.path,
        message: 'The requested endpoint does not exist'
    });
});

const PORT = process.env.PORT || 9999;
app.listen(PORT, () => {
    logger.info('ZapZap server started', {
        port: PORT,
        environment: process.env.NODE_ENV || 'development',
        players: party.nb_players
    });
    console.log(`\n🃏 ZapZap Game Server Running`);
    console.log(`   Port: ${PORT}`);
    console.log(`   Players: ${party.nb_players}`);
    console.log(`\n   Access URLs:`);
    for (let i = 0; i < party.nb_players; i++) {
        console.log(`   Player ${i}: http://localhost:${PORT}/?id=${i}`);
    }
    console.log('');
});
