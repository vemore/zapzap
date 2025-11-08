/**
 * BotActionService
 * Service for executing bot actions during their turns
 */

const BotStrategyFactory = require('./strategies/BotStrategyFactory');
const CardAnalyzer = require('./CardAnalyzer');
const logger = require('../../../logger');

class BotActionService {
    /**
     * @param {Object} useCases - Use cases for game actions
     * @param {Object} repositories - Repositories
     */
    constructor(useCases, repositories) {
        this.playCards = useCases.playCards;
        this.drawCard = useCases.drawCard;
        this.callZapZap = useCases.callZapZap;
        this.partyRepository = repositories.partyRepository;
        this.userRepository = repositories.userRepository;
    }

    /**
     * Execute bot turn
     * @param {string} partyId - Party ID
     * @param {User} botUser - Bot user entity
     * @returns {Promise<Object>} Result of bot action
     */
    async executeBotTurn(partyId, botUser) {
        try {
            if (!botUser.isBot()) {
                throw new Error('User is not a bot');
            }

            logger.info('Bot turn starting', {
                botId: botUser.id,
                botName: botUser.username,
                difficulty: botUser.botDifficulty,
                partyId
            });

            // Get game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                throw new Error('Game state not found');
            }

            // Get bot's player info
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const botPlayer = players.find(p => p.userId === botUser.id);
            if (!botPlayer) {
                throw new Error('Bot not in party');
            }

            // Verify it's bot's turn
            if (gameState.currentTurn !== botPlayer.playerIndex) {
                logger.warn('Not bot turn', {
                    botIndex: botPlayer.playerIndex,
                    currentTurn: gameState.currentTurn
                });
                return { success: false, reason: 'not_bot_turn' };
            }

            // Get bot's hand
            const botHand = gameState.hands[botPlayer.playerIndex];
            if (!botHand || botHand.length === 0) {
                throw new Error('Bot has no cards');
            }

            // Get bot strategy
            const strategy = BotStrategyFactory.create(botUser.botDifficulty);

            // Execute action based on current action state
            if (gameState.currentAction === 'play') {
                return await this.executeBotPlay(partyId, botUser, botHand, gameState, strategy);
            } else if (gameState.currentAction === 'draw') {
                return await this.executeBotDraw(partyId, botUser, botHand, gameState, strategy);
            } else {
                logger.warn('Unknown action state', { action: gameState.currentAction });
                return { success: false, reason: 'unknown_action' };
            }
        } catch (error) {
            logger.error('Bot turn execution error', {
                botId: botUser.id,
                partyId,
                error: error.message,
                stack: error.stack
            });
            throw error;
        }
    }

    /**
     * Execute bot play action (play cards or call zapzap)
     * @private
     */
    async executeBotPlay(partyId, botUser, botHand, gameState, strategy) {
        try {
            // Check if bot should call zapzap
            if (strategy.shouldZapZap(botHand, gameState)) {
                logger.info('Bot calling zapzap', {
                    botId: botUser.id,
                    handValue: CardAnalyzer.calculateHandValue(botHand)
                });

                const result = await this.callZapZap.execute({
                    userId: botUser.id,
                    partyId
                });

                return {
                    success: true,
                    action: 'zapzap',
                    result
                };
            }

            // Otherwise, select cards to play
            const cardsToPlay = strategy.selectPlay(botHand, gameState);

            if (!cardsToPlay || cardsToPlay.length === 0) {
                logger.warn('Bot strategy returned no cards to play', {
                    botId: botUser.id,
                    handSize: botHand.length
                });
                // Fallback: play a random valid card
                const fallbackPlay = CardAnalyzer.findRandomPlay(botHand);
                if (!fallbackPlay) {
                    throw new Error('No valid plays available');
                }
                return await this.playBotCards(partyId, botUser, fallbackPlay);
            }

            logger.info('Bot playing cards', {
                botId: botUser.id,
                cardIds: cardsToPlay,
                cardsCount: cardsToPlay.length
            });

            return await this.playBotCards(partyId, botUser, cardsToPlay);
        } catch (error) {
            logger.error('Bot play action error', {
                botId: botUser.id,
                error: error.message
            });
            throw error;
        }
    }

    /**
     * Execute bot draw action
     * @private
     */
    async executeBotDraw(partyId, botUser, botHand, gameState, strategy) {
        try {
            // Decide draw source
            const drawSource = strategy.selectDrawSource(
                botHand,
                gameState.lastCardsPlayed || [],
                gameState
            );

            logger.info('Bot drawing card', {
                botId: botUser.id,
                source: drawSource
            });

            const result = await this.drawCard.execute({
                userId: botUser.id,
                partyId,
                source: drawSource
            });

            return {
                success: true,
                action: 'draw',
                source: drawSource,
                result
            };
        } catch (error) {
            logger.error('Bot draw action error', {
                botId: botUser.id,
                error: error.message
            });
            throw error;
        }
    }

    /**
     * Play cards using PlayCards use case
     * @private
     */
    async playBotCards(partyId, botUser, cardIds) {
        const result = await this.playCards.execute({
            userId: botUser.id,
            partyId,
            cardIds
        });

        return {
            success: true,
            action: 'play',
            cardIds,
            result
        };
    }
}

module.exports = BotActionService;
