/**
 * Game Routes
 * Handles game action operations (play, draw, zapzap)
 */

const express = require('express');
const logger = require('../../../logger');

/**
 * Create game router
 * @param {DIContainer} container - DI container
 * @param {Function} authMiddleware - Authentication middleware
 * @param {EventEmitter} emitter - Event emitter for SSE
 * @returns {express.Router}
 */
function createGameRouter(container, authMiddleware, emitter) {
    const router = express.Router();

    const playCards = container.resolve('playCards');
    const drawCard = container.resolve('drawCard');
    const callZapZap = container.resolve('callZapZap');
    const getGameState = container.resolve('getGameState');
    const nextRound = container.resolve('nextRound');
    const selectHandSize = container.resolve('selectHandSize');

    /**
     * GET /api/game/:partyId/state
     * Get current game state
     */
    router.get('/:partyId/state', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await getGameState.execute({
                userId: req.user.id,
                partyId
            });

            res.json({
                success: true,
                party: result.party,
                players: result.players,
                round: result.round,
                gameState: result.gameState
            });
        } catch (error) {
            logger.error('Get game state error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            res.status(500).json({
                error: 'Failed to get game state',
                code: 'GET_STATE_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/selectHandSize
     * Select hand size at the start of a round
     */
    router.post('/:partyId/selectHandSize', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;
            const { handSize } = req.body;

            if (typeof handSize !== 'number' || !Number.isInteger(handSize)) {
                return res.status(400).json({
                    error: 'Hand size must be an integer',
                    code: 'INVALID_HAND_SIZE'
                });
            }

            const result = await selectHandSize.execute({
                userId: req.user.id,
                partyId,
                handSize
            });

            logger.info('Hand size selected', {
                userId: req.user.id,
                partyId,
                handSize
            });

            // Emit SSE event
            if (emitter) {
                emitter.emit('event', { partyId, userId: req.user.id, action: 'selectHandSize', handSize });
            }

            res.json({
                success: true,
                handSize: result.handSize,
                gameState: result.gameState
            });
        } catch (error) {
            logger.error('Select hand size error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Not your turn to select hand size') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_YOUR_TURN'
                });
            }

            if (error.message === 'Not in hand size selection phase') {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_ACTION_STATE'
                });
            }

            if (error.message.includes('Hand size must be between')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_HAND_SIZE'
                });
            }

            res.status(500).json({
                error: 'Failed to select hand size',
                code: 'SELECT_HAND_SIZE_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/play
     * Play cards
     */
    router.post('/:partyId/play', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;
            const { cardIds } = req.body;

            if (!cardIds || !Array.isArray(cardIds) || cardIds.length === 0) {
                return res.status(400).json({
                    error: 'Card IDs are required',
                    code: 'MISSING_CARDS'
                });
            }

            const result = await playCards.execute({
                userId: req.user.id,
                partyId,
                cardIds
            });

            logger.info('Cards played', {
                userId: req.user.id,
                partyId,
                cardIds
            });

            // Emit SSE event
            if (emitter) {
                emitter.emit('event', { partyId, userId: req.user.id, action: 'play' });
            }

            res.json({
                success: true,
                cardsPlayed: result.cardsPlayed,
                remainingCards: result.remainingCards,
                gameState: result.gameState
            });
        } catch (error) {
            logger.error('Play cards error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Not your turn') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_YOUR_TURN'
                });
            }

            if (error.message === 'Current action is not PLAY') {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_ACTION_STATE'
                });
            }

            if (error.message.includes('not in hand')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_CARDS'
                });
            }

            if (error.message.includes('Must play at least 2 cards')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_PLAY'
                });
            }

            res.status(500).json({
                error: 'Failed to play cards',
                code: 'PLAY_CARDS_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/draw
     * Draw a card
     */
    router.post('/:partyId/draw', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;
            const { source, cardId } = req.body;

            if (!source || (source !== 'deck' && source !== 'played')) {
                return res.status(400).json({
                    error: 'Source must be "deck" or "played"',
                    code: 'INVALID_SOURCE'
                });
            }

            const result = await drawCard.execute({
                userId: req.user.id,
                partyId,
                source,
                cardId
            });

            logger.info('Card drawn', {
                userId: req.user.id,
                partyId,
                source,
                cardId: result.cardDrawn
            });

            // Emit SSE event
            if (emitter) {
                emitter.emit('event', { partyId, userId: req.user.id, action: 'draw' });
            }

            res.json({
                success: true,
                cardDrawn: result.cardDrawn,
                source: result.source,
                handSize: result.handSize,
                gameState: result.gameState
            });
        } catch (error) {
            logger.error('Draw card error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Not your turn') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_YOUR_TURN'
                });
            }

            if (error.message === 'Current action is not DRAW') {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_ACTION_STATE'
                });
            }

            if (error.message === 'Deck is empty') {
                return res.status(400).json({
                    error: error.message,
                    code: 'DECK_EMPTY'
                });
            }

            if (error.message.includes('No cards available')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'NO_CARDS_AVAILABLE'
                });
            }

            if (error.message.includes('not available in played cards')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'CARD_NOT_AVAILABLE'
                });
            }

            res.status(500).json({
                error: 'Failed to draw card',
                code: 'DRAW_CARD_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/zapzap
     * Call zapzap
     */
    router.post('/:partyId/zapzap', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await callZapZap.execute({
                userId: req.user.id,
                partyId
            });

            logger.info('ZapZap called', {
                userId: req.user.id,
                partyId,
                zapzapSuccess: result.zapzapSuccess,
                counteracted: result.counteracted
            });

            // Emit SSE event
            if (emitter) {
                emitter.emit('event', { partyId, userId: req.user.id, action: 'zapzap' });
            }

            res.json({
                success: true,
                zapzapSuccess: result.zapzapSuccess,
                counteracted: result.counteracted,
                counteractedBy: result.counteractedBy,
                scores: result.scores,
                handPoints: result.handPoints,
                callerPoints: result.callerPoints
            });
        } catch (error) {
            logger.error('Call zapzap error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Not your turn') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_YOUR_TURN'
                });
            }

            if (error.message.includes('Hand value too high')) {
                return res.status(400).json({
                    error: error.message,
                    code: 'HAND_TOO_HIGH'
                });
            }

            if (error.message === 'Cannot call zapzap at this time') {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_ACTION_STATE'
                });
            }

            res.status(500).json({
                error: 'Failed to call zapzap',
                code: 'ZAPZAP_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/nextRound
     * Start the next round after a round ends
     */
    router.post('/:partyId/nextRound', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await nextRound.execute({
                userId: req.user.id,
                partyId
            });

            logger.info('Next round', {
                userId: req.user.id,
                partyId,
                gameFinished: result.gameFinished,
                roundNumber: result.round?.roundNumber
            });

            // Emit SSE event
            if (emitter) {
                if (result.gameFinished) {
                    emitter.emit('event', {
                        partyId,
                        userId: req.user.id,
                        action: 'gameFinished',
                        winner: result.winner
                    });
                } else {
                    emitter.emit('event', {
                        partyId,
                        userId: req.user.id,
                        action: 'roundStarted',
                        roundNumber: result.round.roundNumber
                    });
                }
            }

            res.json({
                success: true,
                gameFinished: result.gameFinished,
                winner: result.winner,
                round: result.round,
                startingPlayer: result.startingPlayer,
                scores: result.scores,
                eliminatedPlayers: result.eliminatedPlayers,
                finalScores: result.finalScores
            });
        } catch (error) {
            logger.error('Next round error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Party is not in playing state') {
                return res.status(400).json({
                    error: error.message,
                    code: 'INVALID_PARTY_STATE'
                });
            }

            if (error.message === 'Current round is not finished') {
                return res.status(400).json({
                    error: error.message,
                    code: 'ROUND_NOT_FINISHED'
                });
            }

            res.status(500).json({
                error: 'Failed to start next round',
                code: 'NEXT_ROUND_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/game/:partyId/trigger-bot
     * Manually trigger bot turn (useful for stuck games)
     */
    router.post('/:partyId/trigger-bot', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            logger.info('Manual bot trigger requested', {
                partyId,
                userId: req.user.id
            });

            // Emit event to trigger bot orchestrator
            if (emitter) {
                emitter.emit('event', {
                    partyId,
                    userId: req.user.id,
                    action: 'roundStarted',
                    manual: true
                });
            }

            res.json({
                success: true,
                message: 'Bot trigger event emitted'
            });
        } catch (error) {
            logger.error('Trigger bot error', {
                error: error.message,
                partyId: req.params.partyId
            });

            res.status(500).json({
                error: 'Failed to trigger bot',
                code: 'TRIGGER_BOT_ERROR',
                details: error.message
            });
        }
    });

    return router;
}

module.exports = createGameRouter;
