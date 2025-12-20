/**
 * BotStrategyFactory
 * Factory for creating bot strategy instances based on difficulty
 */

const EasyBotStrategy = require('./EasyBotStrategy');
const MediumBotStrategy = require('./MediumBotStrategy');
const HardBotStrategy = require('./HardBotStrategy');
const HardVinceBotStrategy = require('./HardVinceBotStrategy');
const MLBotStrategy = require('./MLBotStrategy');
const DRLBotStrategy = require('./DRLBotStrategy');
const LLMBotStrategy = require('./LLMBotStrategy');
const ThibotBotStrategy = require('./ThibotBotStrategy');
const LLMBotMemory = require('../LLMBotMemory');

// Shared ML policy for learning across games (singleton)
let sharedMLPolicy = null;

// Shared DRL policy for learning across games (singleton)
let sharedDRLPolicy = null;

// Cache for LLM bot memories (singleton per botUserId)
const llmMemoryCache = new Map();

class BotStrategyFactory {
    /**
     * Create a bot strategy instance
     * @param {string} difficulty - Bot difficulty ('easy', 'medium', 'hard', 'hard_vince', 'ml')
     * @param {Object} options - Additional options for strategy creation
     * @param {Object} options.policy - Shared policy for ML bot (optional)
     * @param {boolean} options.useSharedPolicy - Use shared ML policy (default: true for simulations)
     * @returns {BotStrategy} Strategy instance
     */
    static create(difficulty, options = {}) {
        switch (difficulty.toLowerCase()) {
            case 'easy':
                return new EasyBotStrategy();
            case 'medium':
                return new MediumBotStrategy();
            case 'hard':
                return new HardBotStrategy();
            case 'hard_vince':
                return new HardVinceBotStrategy(options.params || {});
            case 'ml':
                // ML bot can use a shared policy for learning across games
                if (options.policy) {
                    return new MLBotStrategy({ policy: options.policy });
                }
                if (options.useSharedPolicy !== false) {
                    // Use singleton shared policy for simulations
                    if (!sharedMLPolicy) {
                        const BanditPolicy = require('../ml/BanditPolicy');
                        sharedMLPolicy = new BanditPolicy();
                    }
                    return new MLBotStrategy({ policy: sharedMLPolicy });
                }
                return new MLBotStrategy();
            case 'ml_mcts':
                // ML bot with MCTS enabled for stronger play evaluation
                if (options.policy) {
                    return new MLBotStrategy({
                        policy: options.policy,
                        useMCTS: true,
                        mctsSimulations: options.mctsSimulations || 30
                    });
                }
                if (options.useSharedPolicy !== false) {
                    if (!sharedMLPolicy) {
                        const BanditPolicy = require('../ml/BanditPolicy');
                        sharedMLPolicy = new BanditPolicy();
                    }
                    return new MLBotStrategy({
                        policy: sharedMLPolicy,
                        useMCTS: true,
                        mctsSimulations: options.mctsSimulations || 30
                    });
                }
                return new MLBotStrategy({ useMCTS: true });
            case 'drl':
                // Deep RL bot using Double DQN with Prioritized Experience Replay
                if (options.policy) {
                    return new DRLBotStrategy({
                        policy: options.policy,
                        useHardRules: options.useHardRules !== false,
                        training: options.training !== false
                    });
                }
                if (options.useSharedPolicy !== false) {
                    // Use singleton shared policy for simulations
                    if (!sharedDRLPolicy) {
                        const DRLPolicy = require('../ml/DRLPolicy');
                        sharedDRLPolicy = new DRLPolicy({
                            inputDim: options.inputDim || 45,
                            epsilon: options.epsilon || 0.3,
                            minEpsilon: options.minEpsilon || 0.02
                        });
                    }
                    return new DRLBotStrategy({
                        policy: sharedDRLPolicy,
                        useHardRules: options.useHardRules !== false,
                        training: options.training !== false
                    });
                }
                return new DRLBotStrategy({
                    useHardRules: options.useHardRules !== false,
                    training: options.training !== false
                });
            case 'llm':
                // LLM bot using Llama 3.3 via AWS Bedrock
                // Requires bedrockService to be provided in options
                // Supports strategic memory for learning from previous games
                {
                    let memory = null;
                    if (options.botUserId) {
                        // Use cached memory or create new one
                        if (llmMemoryCache.has(options.botUserId)) {
                            memory = llmMemoryCache.get(options.botUserId);
                        } else {
                            memory = new LLMBotMemory(options.botUserId);
                            memory.loadSync();
                            llmMemoryCache.set(options.botUserId, memory);
                        }
                    }

                    if (!options.bedrockService) {
                        // Return strategy without Bedrock - will use fallback for all decisions
                        return new LLMBotStrategy({ enableFallback: true, memory });
                    }
                    return new LLMBotStrategy({
                        bedrockService: options.bedrockService,
                        enableFallback: options.enableFallback !== false,
                        memory
                    });
                }
            case 'thibot':
                // Thibot: Probability-based bot with genetically optimized parameters
                // Tracks all played cards and uses probabilities to maximize points removed
                return new ThibotBotStrategy();
            default:
                throw new Error(`Unknown bot difficulty: ${difficulty}`);
        }
    }

    /**
     * Get the shared ML policy (for saving/loading)
     * @returns {BanditPolicy|null}
     */
    static getSharedMLPolicy() {
        return sharedMLPolicy;
    }

    /**
     * Set the shared ML policy (for loading saved models)
     * @param {BanditPolicy} policy
     */
    static setSharedMLPolicy(policy) {
        sharedMLPolicy = policy;
    }

    /**
     * Reset the shared ML policy
     */
    static resetSharedMLPolicy() {
        if (sharedMLPolicy) {
            sharedMLPolicy.reset();
        }
    }

    /**
     * Get the shared DRL policy (for saving/loading)
     * @returns {DRLPolicy|null}
     */
    static getSharedDRLPolicy() {
        return sharedDRLPolicy;
    }

    /**
     * Set the shared DRL policy (for loading saved models)
     * @param {DRLPolicy} policy
     */
    static setSharedDRLPolicy(policy) {
        sharedDRLPolicy = policy;
    }

    /**
     * Reset the shared DRL policy
     */
    static resetSharedDRLPolicy() {
        if (sharedDRLPolicy) {
            sharedDRLPolicy.dispose();
            sharedDRLPolicy = null;
        }
    }

    /**
     * Get all available difficulty levels
     * @returns {Array<string>}
     */
    static getAvailableDifficulties() {
        return ['easy', 'medium', 'hard', 'hard_vince', 'ml', 'ml_mcts', 'drl', 'llm', 'thibot'];
    }

    /**
     * Validate difficulty level
     * @param {string} difficulty
     * @returns {boolean}
     */
    static isValidDifficulty(difficulty) {
        return this.getAvailableDifficulties().includes(difficulty.toLowerCase());
    }

    /**
     * Get LLM bot memory from cache
     * @param {string} botUserId
     * @returns {LLMBotMemory|null}
     */
    static getLLMMemory(botUserId) {
        return llmMemoryCache.get(botUserId) || null;
    }

    /**
     * Refresh LLM bot memory (reload from disk after reflection)
     * @param {string} botUserId
     */
    static async refreshLLMMemory(botUserId) {
        if (llmMemoryCache.has(botUserId)) {
            const memory = llmMemoryCache.get(botUserId);
            await memory.load();
        }
    }

    /**
     * Clear LLM memory cache
     */
    static clearLLMMemoryCache() {
        llmMemoryCache.clear();
    }
}

module.exports = BotStrategyFactory;
