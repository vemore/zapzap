/**
 * SelectHandSize Use Case
 * Handles selecting the number of cards to deal at the start of a round
 */

const logger = require('../../../logger');

class SelectHandSize {
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
     * @param {Object} request - Select hand size request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @param {number} request.handSize - Number of cards to deal
     * @returns {Promise<Object>} Result
     */
    async execute({ userId, partyId, handSize }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            if (typeof handSize !== 'number' || !Number.isInteger(handSize)) {
                throw new Error('Hand size must be an integer');
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

            // Get player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);
            if (!player) {
                throw new Error('User is not in this party');
            }

            // Get current game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                throw new Error('Game state not found');
            }

            // Check current action is selectHandSize
            if (gameState.currentAction !== 'selectHandSize') {
                throw new Error('Not in hand size selection phase');
            }

            // Verify it's this player's turn
            if (gameState.currentTurn !== player.playerIndex) {
                throw new Error('Not your turn to select hand size');
            }

            // Count active players (not eliminated)
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            const activePlayerCount = players.filter(p => !eliminatedPlayers.includes(p.playerIndex)).length;

            // Validate hand size based on player count
            // Golden Score (2 players): 4-10 cards
            // Normal (3+ players): 4-7 cards
            const isGoldenScore = activePlayerCount === 2;
            const minHandSize = 4;
            const maxHandSize = isGoldenScore ? 10 : 7;

            if (handSize < minHandSize || handSize > maxHandSize) {
                throw new Error(`Hand size must be between ${minHandSize} and ${maxHandSize} for ${activePlayerCount} players`);
            }

            // Get current deck
            const deck = [...gameState.deck];

            // Deal cards to active players only
            const hands = {};
            for (let i = 0; i < players.length; i++) {
                if (eliminatedPlayers.includes(i)) {
                    // Eliminated players get no cards
                    hands[i] = [];
                } else {
                    // Active players get cards
                    hands[i] = deck.splice(0, handSize);
                }
            }

            // Flip first card from deck to discard pile
            const firstDiscardCard = deck.pop();

            // Update game state - move to play phase
            const newGameState = gameState.with({
                deck: deck,
                hands: hands,
                lastCardsPlayed: [firstDiscardCard],
                cardsPlayed: [],
                currentAction: 'play',
                lastAction: {
                    type: 'selectHandSize',
                    playerIndex: player.playerIndex,
                    handSize: handSize
                }
            });

            // Save updated game state
            await this.partyRepository.saveGameState(partyId, newGameState);

            logger.info('Hand size selected', {
                userId: userId,
                username: user.username,
                partyId: partyId,
                handSize: handSize,
                activePlayerCount: activePlayerCount,
                isGoldenScore: isGoldenScore
            });

            return {
                success: true,
                handSize: handSize,
                gameState: {
                    currentTurn: newGameState.currentTurn,
                    currentAction: newGameState.currentAction,
                    deckSize: newGameState.deck.length,
                    handSizes: Object.keys(hands).reduce((acc, idx) => {
                        acc[idx] = hands[idx].length;
                        return acc;
                    }, {})
                }
            };
        } catch (error) {
            logger.error('Select hand size error', {
                userId,
                partyId,
                handSize,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = SelectHandSize;
