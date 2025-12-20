/**
 * BotOrchestrator
 * Coordinates bot turns in response to game state changes
 */

const logger = require('../../../logger');

class BotOrchestrator {
    /**
     * @param {BotActionService} botActionService - Bot action service
     * @param {IPartyRepository} partyRepository - Party repository
     * @param {IUserRepository} userRepository - User repository
     * @param {EventEmitter} eventEmitter - Event emitter for game events
     * @param {Object} options - Configuration options
     * @param {number} options.actionDelayMs - Delay between bot actions in milliseconds (default: 1000)
     */
    constructor(botActionService, partyRepository, userRepository, eventEmitter, options = {}) {
        this.botActionService = botActionService;
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
        this.eventEmitter = eventEmitter;
        this.actionDelayMs = options.actionDelayMs || 1000; // Default 1 second
        this.isProcessing = new Set(); // Track parties currently processing bot turns
    }

    /**
     * Start listening for game events
     */
    start() {
        logger.info('BotOrchestrator started');

        // Listen for game state updates
        this.eventEmitter.on('event', async (data) => {
            try {
                await this.handleGameEvent(data);
            } catch (error) {
                logger.error('Error handling game event', {
                    event: data,
                    error: error.message,
                    stack: error.stack
                });
            }
        });

        // Recover pending bot turns after server restart
        this.recoverPendingBotTurns().catch(error => {
            logger.error('Error recovering pending bot turns', {
                error: error.message,
                stack: error.stack
            });
        });
    }

    /**
     * Recover pending bot turns after server restart
     * Finds all active parties where it's a bot's turn and triggers their action
     * @private
     */
    async recoverPendingBotTurns() {
        logger.info('Recovering pending bot turns...');

        try {
            // Find all parties currently playing
            const activeParties = await this.partyRepository.findAllParties('playing');

            if (!activeParties || activeParties.length === 0) {
                logger.info('No active parties found for recovery');
                return;
            }

            logger.info('Found active parties for recovery', {
                count: activeParties.length
            });

            let recoveredCount = 0;

            for (const party of activeParties) {
                try {
                    // Get game state
                    const gameState = await this.partyRepository.getGameState(party.id);
                    if (!gameState) {
                        continue;
                    }

                    // Get players
                    const players = await this.partyRepository.getPartyPlayers(party.id);
                    const currentPlayer = players.find(p => p.playerIndex === gameState.currentTurn);

                    if (!currentPlayer) {
                        continue;
                    }

                    // Get user
                    const user = await this.userRepository.findById(currentPlayer.userId);
                    if (!user || !user.isBot()) {
                        continue; // Human player's turn
                    }

                    // Check if bot is eliminated
                    const eliminatedPlayers = gameState.eliminatedPlayers || [];
                    if (eliminatedPlayers.includes(currentPlayer.playerIndex)) {
                        continue;
                    }

                    logger.info('Recovering bot turn', {
                        partyId: party.id,
                        partyName: party.name,
                        botId: user.id,
                        botName: user.username,
                        currentAction: gameState.currentAction
                    });

                    // Small delay to stagger recoveries and avoid overwhelming the system
                    await new Promise(resolve => setTimeout(resolve, 500));

                    // Emit a synthetic event to trigger the bot turn
                    this.eventEmitter.emit('event', {
                        partyId: party.id,
                        action: gameState.currentAction === 'selectHandSize' ? 'selectHandSize' : 'play',
                        recovered: true
                    });

                    recoveredCount++;
                } catch (error) {
                    logger.error('Error recovering party', {
                        partyId: party.id,
                        error: error.message
                    });
                }
            }

            logger.info('Bot turn recovery complete', {
                totalParties: activeParties.length,
                recoveredCount
            });
        } catch (error) {
            logger.error('Failed to recover pending bot turns', {
                error: error.message,
                stack: error.stack
            });
        }
    }

    /**
     * Handle game event
     * @param {Object} data - Event data
     * @private
     */
    async handleGameEvent(data) {
        if (!data || !data.partyId) {
            return; // Ignore invalid events
        }

        const { partyId, action } = data;

        // Only process on play, draw, zapzap, selectHandSize, or roundStarted actions
        // roundStarted is needed to trigger bots when a new round begins
        // selectHandSize is needed to trigger bots when hand size selection phase starts
        if (!['play', 'draw', 'zapzap', 'selectHandSize', 'roundStarted'].includes(action)) {
            return;
        }

        // Check if already processing this party
        if (this.isProcessing.has(partyId)) {
            logger.debug('Already processing party, skipping', { partyId });
            return;
        }

        try {
            this.isProcessing.add(partyId);

            // Get party
            const party = await this.partyRepository.findById(partyId);
            if (!party || party.status !== 'playing') {
                return; // Party not playing
            }

            // Get game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                return; // No game state
            }

            // Get current turn player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const currentPlayer = players.find(p => p.playerIndex === gameState.currentTurn);

            if (!currentPlayer) {
                logger.warn('Current player not found', {
                    partyId,
                    currentTurn: gameState.currentTurn
                });
                return;
            }

            // Get user
            const user = await this.userRepository.findById(currentPlayer.userId);
            if (!user) {
                logger.warn('User not found', {
                    partyId,
                    userId: currentPlayer.userId
                });
                return;
            }

            // Check if user is bot
            if (!user.isBot()) {
                return; // Human player's turn, no action needed
            }

            // Check if bot is eliminated
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            if (eliminatedPlayers.includes(currentPlayer.playerIndex)) {
                logger.info('Bot is eliminated, skipping turn', {
                    partyId,
                    botId: user.id,
                    playerIndex: currentPlayer.playerIndex
                });
                return;
            }

            logger.info('Bot turn detected', {
                partyId,
                botId: user.id,
                botName: user.username,
                difficulty: user.botDifficulty,
                currentAction: gameState.currentAction
            });

            // Execute bot turn (instant - no delay as per user preference)
            await this.executeBotTurnWithRetry(partyId, user);

        } finally {
            this.isProcessing.delete(partyId);
        }
    }

    /**
     * Execute bot turn with retry logic
     * Executes play action, waits 1s, then executes draw action
     * @param {string} partyId - Party ID
     * @param {User} botUser - Bot user
     * @param {number} retryCount - Current retry count
     * @private
     */
    async executeBotTurnWithRetry(partyId, botUser, retryCount = 0) {
        const maxRetries = 3;

        try {
            const result = await this.botActionService.executeBotTurn(partyId, botUser);

            if (result.success) {
                logger.info('Bot action executed successfully', {
                    partyId,
                    botId: botUser.id,
                    action: result.action
                });

                // Emit event for frontend updates
                this.eventEmitter.emit('event', {
                    partyId,
                    userId: botUser.id,
                    action: result.action,
                    bot: true
                });

                // If the bot just played cards, wait then execute draw action
                if (result.action === 'play') {
                    logger.info('Bot waiting before draw action', {
                        partyId,
                        botId: botUser.id,
                        delayMs: this.actionDelayMs
                    });

                    await new Promise(resolve => setTimeout(resolve, this.actionDelayMs));

                    // Check if it's still the bot's turn and needs to draw
                    const gameState = await this.partyRepository.getGameState(partyId);
                    if (gameState && gameState.currentAction === 'draw') {
                        const players = await this.partyRepository.getPartyPlayers(partyId);
                        const currentPlayer = players.find(p => p.playerIndex === gameState.currentTurn);

                        if (currentPlayer && currentPlayer.userId === botUser.id) {
                            // Execute draw action
                            const drawResult = await this.botActionService.executeBotTurn(partyId, botUser);

                            if (drawResult.success) {
                                logger.info('Bot draw action executed successfully', {
                                    partyId,
                                    botId: botUser.id,
                                    action: drawResult.action
                                });

                                // Emit event for frontend updates
                                this.eventEmitter.emit('event', {
                                    partyId,
                                    userId: botUser.id,
                                    action: drawResult.action,
                                    bot: true
                                });
                            }
                        }
                    }
                }

                // Check if another bot turn is needed (recursively handle multiple bots)
                // Wait before next bot's turn as well
                await new Promise(resolve => setTimeout(resolve, this.actionDelayMs));
                await this.checkForNextBotTurn(partyId);
            } else {
                logger.warn('Bot turn not successful', {
                    partyId,
                    botId: botUser.id,
                    result
                });
            }
        } catch (error) {
            logger.error('Bot turn execution failed', {
                partyId,
                botId: botUser.id,
                retryCount,
                error: error.message
            });

            // Retry on failure (up to maxRetries)
            if (retryCount < maxRetries) {
                logger.info('Retrying bot turn', {
                    partyId,
                    botId: botUser.id,
                    retryCount: retryCount + 1
                });

                // Small delay before retry (100ms)
                await new Promise(resolve => setTimeout(resolve, 100));
                await this.executeBotTurnWithRetry(partyId, botUser, retryCount + 1);
            } else {
                logger.error('Bot turn failed after max retries', {
                    partyId,
                    botId: botUser.id,
                    maxRetries
                });

                // Emit error event
                this.eventEmitter.emit('event', {
                    partyId,
                    userId: botUser.id,
                    action: 'error',
                    error: 'bot_turn_failed',
                    bot: true
                });
            }
        }
    }

    /**
     * Check if next turn is also a bot turn
     * @param {string} partyId - Party ID
     * @private
     */
    async checkForNextBotTurn(partyId) {
        try {
            // Get updated game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                return;
            }

            // Get current turn player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const currentPlayer = players.find(p => p.playerIndex === gameState.currentTurn);

            if (!currentPlayer) {
                return;
            }

            // Get user
            const user = await this.userRepository.findById(currentPlayer.userId);
            if (!user || !user.isBot()) {
                return; // Not a bot turn
            }

            // Another bot turn detected, execute it
            logger.info('Consecutive bot turn detected', {
                partyId,
                botId: user.id
            });

            // Small delay to avoid tight loop (50ms)
            await new Promise(resolve => setTimeout(resolve, 50));

            await this.executeBotTurnWithRetry(partyId, user);
        } catch (error) {
            logger.error('Error checking for next bot turn', {
                partyId,
                error: error.message
            });
        }
    }

    /**
     * Stop listening for events
     */
    stop() {
        this.eventEmitter.removeAllListeners('event');
        this.isProcessing.clear();
        logger.info('BotOrchestrator stopped');
    }
}

module.exports = BotOrchestrator;
