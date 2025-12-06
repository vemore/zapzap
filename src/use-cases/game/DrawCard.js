/**
 * DrawCard Use Case
 * Handles drawing cards from deck or last played cards
 */

const logger = require('../../../logger');

class DrawCard {
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
     * @param {Object} request - Draw card request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @param {string} request.source - 'deck' or 'played' (last played cards)
     * @param {number} [request.cardId] - Specific card ID when drawing from played
     * @returns {Promise<Object>} Draw result with updated game state
     */
    async execute({ userId, partyId, source, cardId }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            if (!source || !['deck', 'played'].includes(source)) {
                throw new Error('Source must be "deck" or "played"');
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

            // Check current action allows drawing (only 'draw' phase - after playing cards)
            if (gameState.currentAction !== 'draw') {
                throw new Error('Cannot draw at this time - you must play cards first');
            }

            // Check if player is eliminated
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            if (eliminatedPlayers.includes(player.playerIndex)) {
                throw new Error('Player is eliminated and cannot play');
            }

            let drawnCard;
            let newDeck = [...gameState.deck];
            let newLastCardsPlayed = [...gameState.lastCardsPlayed];

            if (source === 'deck') {
                // Draw from deck
                if (newDeck.length === 0) {
                    throw new Error('Deck is empty');
                }

                drawnCard = newDeck.pop();
            } else {
                // Draw from last played cards
                if (newLastCardsPlayed.length === 0) {
                    throw new Error('No cards available to draw from played cards');
                }

                if (cardId !== undefined) {
                    // Draw specific card
                    const cardIndex = newLastCardsPlayed.indexOf(cardId);
                    if (cardIndex === -1) {
                        throw new Error('Card not available in played cards');
                    }
                    drawnCard = newLastCardsPlayed.splice(cardIndex, 1)[0];
                } else {
                    // Draw top card
                    drawnCard = newLastCardsPlayed.pop();
                }
            }

            // Add card to player's hand
            const playerHand = gameState.hands[player.playerIndex] || [];
            const newHand = [...playerHand, drawnCard];

            // Update game state
            const newHands = { ...gameState.hands };
            newHands[player.playerIndex] = newHand;

            // Move to next turn (skip eliminated players)
            let nextTurn = (gameState.currentTurn + 1) % players.length;
            while (eliminatedPlayers.includes(nextTurn)) {
                nextTurn = (nextTurn + 1) % players.length;
            }

            const newGameState = gameState.withUpdates({
                hands: newHands,
                deck: newDeck,
                lastCardsPlayed: newLastCardsPlayed,
                currentTurn: nextTurn,
                currentAction: 'play',
                lastAction: {
                    type: 'draw',
                    playerIndex: player.playerIndex,
                    source: source,
                    cardId: drawnCard,
                    timestamp: Date.now()
                }
            });

            // Save game state
            await this.partyRepository.saveGameState(partyId, newGameState);

            logger.info('Card drawn', {
                userId: userId,
                username: user.username,
                partyId: partyId,
                roundId: round.id,
                source: source,
                cardId: drawnCard,
                newHandSize: newHand.length
            });

            return {
                success: true,
                gameState: newGameState.toPublicObject(),
                cardDrawn: drawnCard,
                source: source,
                handSize: newHand.length
            };
        } catch (error) {
            logger.error('Draw card error', {
                userId,
                partyId,
                source,
                cardId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = DrawCard;
