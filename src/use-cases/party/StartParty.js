/**
 * StartParty Use Case
 * Handles starting a party game
 */

const Round = require('../../domain/entities/Round');
const GameState = require('../../domain/value-objects/GameState');
const logger = require('../../../logger');

class StartParty {
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
     * @param {Object} request - Start party request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @returns {Promise<Object>} Start result
     */
    async execute({ userId, partyId }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
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

            // Check if user is the owner
            if (party.ownerId !== userId) {
                throw new Error('Only the party owner can start the game');
            }

            // Check party status
            if (party.status === 'playing') {
                throw new Error('Party is already playing');
            }

            if (party.status === 'finished') {
                throw new Error('Party has finished');
            }

            // Get players
            const players = await this.partyRepository.getPlayers(partyId);

            if (players.length < 2) {
                throw new Error('At least 2 players required to start');
            }

            // Start the party
            party.start();

            // Create first round
            const round = Round.create(partyId, 1);

            // Create initial game state
            const gameState = GameState.createInitial(players.length);

            // Initialize deck with 54 cards (52 + 2 jokers)
            const deck = Array.from({ length: 54 }, (_, i) => i);

            // Shuffle deck (Fisher-Yates)
            for (let i = deck.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [deck[i], deck[j]] = [deck[j], deck[i]];
            }

            // Deal cards to players
            const handSize = party.settings.handSize || 10;
            const hands = {};

            for (let i = 0; i < players.length; i++) {
                hands[i] = deck.splice(0, handSize);
            }

            // Create game state with dealt cards
            const initialGameState = gameState.with({
                deck: deck,
                hands: hands,
                currentTurn: 0,
                currentAction: 'draw',
                roundNumber: 1
            });

            // Save round
            await this.partyRepository.saveRound(round);

            // Save game state
            await this.partyRepository.saveGameState(partyId, initialGameState);

            // Update party with round ID
            party.startNewRound(round.id);
            await this.partyRepository.save(party);

            logger.info('Party started', {
                userId: userId,
                username: user.username,
                partyId: partyId,
                roundId: round.id,
                playerCount: players.length
            });

            return {
                success: true,
                party: {
                    id: party.id,
                    status: party.status,
                    currentRoundId: party.currentRoundId
                },
                round: {
                    id: round.id,
                    roundNumber: round.roundNumber,
                    status: round.status
                },
                gameState: {
                    currentTurn: initialGameState.currentTurn,
                    currentAction: initialGameState.currentAction,
                    deckSize: initialGameState.deck.length,
                    handSizes: Object.keys(hands).reduce((acc, idx) => {
                        acc[idx] = hands[idx].length;
                        return acc;
                    }, {})
                }
            };
        } catch (error) {
            logger.error('Start party error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = StartParty;
