/**
 * PlayCards Use Case
 * Handles playing cards from a player's hand
 */

const CardAnalyzer = require('../../infrastructure/bot/CardAnalyzer');
const logger = require('../../../logger');

class PlayCards {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     * @param {IUserRepository} userRepository - User repository
     */
    constructor(partyRepository, userRepository) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Play cards request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @param {number[]} request.cardIds - Array of card IDs to play
     * @returns {Promise<Object>} Play result with updated game state
     */
    async execute({ userId, partyId, cardIds }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            if (!Array.isArray(cardIds) || cardIds.length === 0) {
                throw new Error('Card IDs are required');
            }

            // Verify user exists
            const user = await this.userRepository.findById(userId);
            if (!user) {
                throw new Error('User not found');
            }

            // Find party
            const party = await this.partyRepository.findById(partyId);
            if (!party) {
                throw new Error('Party not found');
            }

            // Check party is playing
            if (party.status !== 'playing') {
                throw new Error('Party is not in playing state');
            }

            // Get current round
            if (!party.currentRoundId) {
                throw new Error('No active round');
            }

            const round = await this.partyRepository.getRoundById(party.currentRoundId);
            if (!round) {
                throw new Error('Round not found');
            }

            // Get game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                throw new Error('Game state not found');
            }

            // Get player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);
            if (!player) {
                throw new Error('User is not in this party');
            }

            // Check if it's player's turn
            if (gameState.currentTurn !== player.playerIndex) {
                throw new Error('Not your turn');
            }

            // Check current action is PLAY
            if (gameState.currentAction !== 'play') {
                throw new Error('Current action is not PLAY');
            }

            // Check if player is eliminated
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            if (eliminatedPlayers.includes(player.playerIndex)) {
                throw new Error('Player is eliminated and cannot play');
            }

            // Get player's hand
            const playerHand = gameState.hands[player.playerIndex];
            if (!playerHand) {
                throw new Error('Player hand not found');
            }

            // Verify all cards are in player's hand
            for (const cardId of cardIds) {
                if (!playerHand.includes(cardId)) {
                    throw new Error(`Card ${cardId} not in hand`);
                }
            }

            // Validate card play (basic validation - could use utils.check_play from existing code)
            this.validateCardPlay(cardIds);

            // Remove cards from hand
            const newHand = playerHand.filter(id => !cardIds.includes(id));

            // Update game state
            const newHands = { ...gameState.hands };
            newHands[player.playerIndex] = newHand;

            // Add old lastCardsPlayed to discard pile (they're no longer pickable)
            const newDiscardPile = [...(gameState.discardPile || []), ...gameState.lastCardsPlayed];

            const newGameState = gameState.withUpdates({
                hands: newHands,
                cardsPlayed: cardIds,
                lastCardsPlayed: gameState.cardsPlayed,
                discardPile: newDiscardPile,
                currentAction: 'draw',
                lastAction: {
                    type: 'play',
                    playerIndex: player.playerIndex,
                    cardIds: cardIds,
                    timestamp: Date.now()
                }
            });

            // Save game state
            await this.partyRepository.saveGameState(partyId, newGameState);

            logger.info('Cards played', {
                userId: userId,
                username: user.username,
                partyId: partyId,
                roundId: round.id,
                cardIds: cardIds,
                cardsCount: cardIds.length
            });

            return {
                success: true,
                gameState: newGameState.toPublicObject(),
                cardsPlayed: cardIds,
                remainingCards: newHand.length
            };
        } catch (error) {
            logger.error('Play cards error', {
                userId,
                partyId,
                cardIds,
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Validate card play
     * @param {number[]} cardIds - Card IDs to validate
     * @private
     */
    validateCardPlay(cardIds) {
        // Validate using CardAnalyzer
        if (!CardAnalyzer.isValidPlay(cardIds)) {
            throw new Error(
                'Invalid card play. Cards must be:\n' +
                '- Single card, OR\n' +
                '- 2+ cards of same rank (with optional jokers), OR\n' +
                '- 3+ cards in sequence of same suit (with optional jokers)'
            );
        }
    }
}

module.exports = PlayCards;
