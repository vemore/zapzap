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
     * @param {Object} services - External services (optional)
     */
    constructor(useCases, repositories, services = {}) {
        this.playCards = useCases.playCards;
        this.drawCard = useCases.drawCard;
        this.callZapZap = useCases.callZapZap;
        this.selectHandSize = useCases.selectHandSize;
        this.partyRepository = repositories.partyRepository;
        this.userRepository = repositories.userRepository;
        this.bedrockService = services.bedrockService || null;
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
            const botHand = gameState.hands[botPlayer.playerIndex] || [];

            // Get bot strategy (pass botUserId for LLM memory)
            const strategy = BotStrategyFactory.create(botUser.botDifficulty, {
                bedrockService: this.bedrockService,
                botUserId: botUser.id
            });

            // Execute action based on current action state
            if (gameState.currentAction === 'selectHandSize') {
                // Bot needs to select hand size at start of round
                return await this.executeBotSelectHandSize(partyId, botUser, gameState, strategy);
            } else if (gameState.currentAction === 'play') {
                // Bot needs cards to play
                if (botHand.length === 0) {
                    throw new Error('Bot has no cards to play');
                }
                return await this.executeBotPlay(partyId, botUser, botHand, gameState, strategy);
            } else if (gameState.currentAction === 'draw') {
                // Bot can draw even with empty hand (will get a card from deck/discard)
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
     * Execute bot select hand size action
     * @private
     */
    async executeBotSelectHandSize(partyId, botUser, gameState, strategy) {
        try {
            // Get players to count active ones
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            const activePlayerCount = players.filter(p => !eliminatedPlayers.includes(p.playerIndex)).length;
            const isGoldenScore = activePlayerCount === 2;

            // Get hand size from strategy
            const handSize = strategy.selectHandSize(activePlayerCount, isGoldenScore);

            logger.info('Bot selecting hand size', {
                botId: botUser.id,
                handSize,
                activePlayerCount,
                isGoldenScore
            });

            const result = await this.selectHandSize.execute({
                userId: botUser.id,
                partyId,
                handSize
            });

            return {
                success: true,
                action: 'selectHandSize',
                handSize,
                result
            };
        } catch (error) {
            logger.error('Bot select hand size action error', {
                botId: botUser.id,
                error: error.message
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
            // Support both sync and async strategies
            const shouldCall = strategy.isAsync?.()
                ? await strategy.shouldZapZapAsync(botHand, gameState)
                : strategy.shouldZapZap(botHand, gameState);

            if (shouldCall) {
                const handValue = CardAnalyzer.calculateHandValue(botHand);
                logger.info('Bot calling zapzap', {
                    botId: botUser.id,
                    handValue
                });

                const result = await this.callZapZap.execute({
                    userId: botUser.id,
                    partyId
                });

                // Track decision for LLM bot memory
                this._trackLLMDecision(strategy, gameState, {
                    type: 'zapzap',
                    details: {
                        handValue,
                        success: result.zapzapSuccess
                    }
                });

                return {
                    success: true,
                    action: 'zapzap',
                    result
                };
            }

            // Otherwise, select cards to play
            // Support both sync and async strategies
            const cardsToPlay = strategy.isAsync?.()
                ? await strategy.selectPlayAsync(botHand, gameState)
                : strategy.selectPlay(botHand, gameState);

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

            const handBefore = CardAnalyzer.calculateHandValue(botHand);
            const remainingHand = botHand.filter(c => !cardsToPlay.includes(c));
            const handAfter = CardAnalyzer.calculateHandValue(remainingHand);

            logger.info('Bot playing cards', {
                botId: botUser.id,
                cardIds: cardsToPlay,
                cardsCount: cardsToPlay.length
            });

            // Track decision for LLM bot memory
            this._trackLLMDecision(strategy, gameState, {
                type: 'play',
                details: {
                    cards: cardsToPlay,
                    handBefore,
                    handAfter
                }
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
            const lastCardsPlayed = gameState.lastCardsPlayed || [];
            const deckSize = gameState.deck ? gameState.deck.length : 0;

            // Decide draw source
            // Support both sync and async strategies
            let drawSource = strategy.isAsync?.()
                ? await strategy.selectDrawSourceAsync(botHand, lastCardsPlayed, gameState)
                : strategy.selectDrawSource(botHand, lastCardsPlayed, gameState);

            let cardId = undefined;

            // Handle empty deck: check if we should reshuffle or draw from visible cards
            const discardPileSize = gameState.discardPile ? gameState.discardPile.length : 0;

            if (drawSource === 'deck' && deckSize === 0) {
                // If discardPile has cards, keep drawing from deck to trigger reshuffle
                if (discardPileSize > 0) {
                    logger.info('Bot drawing from deck to trigger reshuffle', {
                        botId: botUser.id,
                        discardPileSize
                    });
                    // Keep drawSource as 'deck' - DrawCard will reshuffle discardPile
                } else if (lastCardsPlayed.length > 0) {
                    // No discardPile to reshuffle, must draw from visible cards
                    drawSource = 'played';
                    cardId = lastCardsPlayed[0];
                    logger.info('Bot forced to draw from visible cards (no deck/discardPile)', {
                        botId: botUser.id,
                        cardId
                    });
                }
                // If both lastCardsPlayed and discardPile are empty, DrawCard.execute()
                // will throw an error - this shouldn't happen in normal gameplay
            }

            // When drawing from discard pile, select a card
            if (drawSource === 'played' && cardId === undefined) {
                if (lastCardsPlayed.length > 0) {
                    // Pick the first available card from discard
                    cardId = lastCardsPlayed[0];
                } else {
                    // Fallback to deck if discard is empty
                    drawSource = 'deck';
                }
            }

            logger.info('Bot drawing card', {
                botId: botUser.id,
                source: drawSource,
                cardId
            });

            const drawParams = {
                userId: botUser.id,
                partyId,
                source: drawSource
            };

            // Add cardId only when drawing from discard
            if (drawSource === 'played' && cardId !== undefined) {
                drawParams.cardId = cardId;
            }

            const result = await this.drawCard.execute(drawParams);

            // Track decision for LLM bot memory
            this._trackLLMDecision(strategy, gameState, {
                type: 'draw',
                details: {
                    source: drawSource,
                    cardDrawn: cardId
                }
            });

            return {
                success: true,
                action: 'draw',
                source: drawSource,
                cardId,
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

    /**
     * Track decision for LLM bot memory
     * @private
     * @param {Object} strategy - Bot strategy instance
     * @param {Object} gameState - Current game state
     * @param {Object} decision - Decision to track
     */
    _trackLLMDecision(strategy, gameState, decision) {
        try {
            // Only track for LLM bots with memory
            if (strategy.isLLMBot?.() && strategy.getMemory?.()) {
                const memory = strategy.getMemory();
                memory.trackDecision({
                    roundNumber: gameState.roundNumber,
                    ...decision
                });
            }
        } catch (error) {
            // Don't fail the action if tracking fails
            logger.warn('Failed to track LLM decision', {
                error: error.message,
                decision: decision.type
            });
        }
    }
}

module.exports = BotActionService;
