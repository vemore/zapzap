/**
 * LLMBotStrategy
 * Bot strategy using Llama 3.3 via AWS Bedrock for decision-making
 * Uses HardBotStrategy as fallback when LLM is unavailable or fails
 */

const BotStrategy = require('./BotStrategy');
const HardBotStrategy = require('./HardBotStrategy');
const CardAnalyzer = require('../CardAnalyzer');
const logger = require('../../../../logger');

// Card suit symbols and rank names for human-readable output
const SUITS = ['Spades', 'Hearts', 'Clubs', 'Diamonds'];
const SUIT_SYMBOLS = ['S', 'H', 'C', 'D'];
const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

class LLMBotStrategy extends BotStrategy {
    /**
     * @param {Object} options
     * @param {Object} options.bedrockService - BedrockService instance for LLM calls
     * @param {boolean} options.enableFallback - Use HardBotStrategy on LLM failure (default: true)
     */
    constructor(options = {}) {
        super('llm');
        this.bedrockService = options.bedrockService;
        this.enableFallback = options.enableFallback !== false;
        this.fallbackStrategy = new HardBotStrategy();

        // System prompt with complete game rules (cached, reused across calls)
        this.systemPrompt = this._buildSystemPrompt();
    }

    /**
     * Build the system prompt with complete game rules
     * @private
     * @returns {string} System prompt for LLM
     */
    _buildSystemPrompt() {
        return `You are an expert ZapZap card game player bot. Your goal is to win by minimizing your hand value and calling ZapZap at the optimal time.

## Game Rules

### Card Values (for ZapZap eligibility and hand scoring)
- Ace (A): 1 point
- 2-10: Face value (2=2, 3=3, ..., 10=10)
- Jack (J): 11 points
- Queen (Q): 12 points
- King (K): 13 points
- Joker: 0 points for ZapZap eligibility, but 25 points penalty in final scoring if you don't have the lowest hand

### Card Notation
Cards are written as RankSuit, for example:
- AS = Ace of Spades
- 10H = 10 of Hearts
- KC = King of Clubs
- QD = Queen of Diamonds
- JKR = Joker

### Valid Plays
1. **Single card**: Any single card can be played alone
2. **Pairs/Sets**: 2 or more cards of the same rank (e.g., KS KH = pair of Kings)
3. **Sequences**: 3 or more consecutive cards of the same suit (e.g., 5S 6S 7S)
4. **Jokers**: Can substitute any card in pairs or sequences

### Turn Structure
Each turn has two phases:
1. **PLAY phase**: You must play a valid card combination from your hand
2. **DRAW phase**: Draw one card from the deck OR pick a card from the discard pile

### ZapZap Rules
- You can call ZapZap when your hand value is 5 points or less (Joker = 0 for this check)
- If you have the lowest hand value: You score 0, all other players score their hand value (Joker = 25 points penalty)
- If someone else has equal or lower hand value: You are COUNTERACTED and receive +20 points penalty plus your hand value

### Winning
- Players are eliminated when their total score exceeds 100 points
- When only 2 players remain: "Golden Score" final round begins
- The winner is the last player with 100 points or less

## Strategy Guidelines
1. **Minimize hand value quickly** to be able to call ZapZap early
2. **Multi-card plays are more efficient** than playing single cards
3. **Track what opponents pick from discard** - they likely need those cards
4. **In Golden Score (2 players)**: NEVER play Jokers - hoard them to deny your opponent
5. **Be cautious calling ZapZap** when opponents have few cards (higher counter risk)
6. **Prefer playing high-value cards** (J, Q, K) to reduce hand value faster
7. **Consider discard pile** - pick cards that help form pairs/sequences

## Response Format
You must respond with ONLY the requested information:
- For play decisions: List the cards to play (e.g., "KS, KH" or "5C, 6C, 7C")
- For ZapZap decisions: Answer "YES" or "NO"
- For draw decisions: Answer "DECK" or "DISCARD"

Be concise and direct in your responses.`;
    }

    /**
     * Convert a single card ID to human-readable name
     * @param {number} cardId - Card ID (0-53)
     * @returns {string} Human-readable card name (e.g., "KS" for King of Spades)
     */
    _cardToName(cardId) {
        if (cardId >= 52) return 'JKR';
        const suit = SUIT_SYMBOLS[Math.floor(cardId / 13)];
        const rank = RANKS[cardId % 13];
        return `${rank}${suit}`;
    }

    /**
     * Convert array of card IDs to human-readable names
     * @param {Array<number>} cards - Card IDs
     * @returns {string} Comma-separated card names
     */
    _cardsToNames(cards) {
        if (!Array.isArray(cards) || cards.length === 0) return 'none';
        return cards.map(id => this._cardToName(id)).join(', ');
    }

    /**
     * Build game state context for LLM prompt
     * @param {Object} gameState - Current game state
     * @param {Array<number>} hand - Bot's hand
     * @returns {string} Formatted game state description
     */
    _buildGameStateContext(gameState, hand) {
        const lines = [];

        lines.push('## Current Game Situation');
        lines.push(`Round: ${gameState.roundNumber}`);
        lines.push(`Your player index: ${gameState.currentTurn}`);
        lines.push(`Action required: ${gameState.currentAction.toUpperCase()}`);
        lines.push(`Golden Score mode: ${gameState.isGoldenScore ? 'YES (final 2-player round!)' : 'NO'}`);

        lines.push('\n### Your Hand');
        lines.push(`Cards: ${this._cardsToNames(hand)}`);
        lines.push(`Hand value: ${CardAnalyzer.calculateHandValue(hand)} points`);
        lines.push(`Can call ZapZap: ${CardAnalyzer.calculateHandValue(hand) <= 5 ? 'YES' : 'NO'}`);

        lines.push('\n### Opponent Information');
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        for (const [idx, opponentHand] of Object.entries(gameState.hands)) {
            const playerIdx = parseInt(idx);
            if (playerIdx === gameState.currentTurn) continue;
            if (eliminatedPlayers.includes(playerIdx)) {
                lines.push(`Player ${playerIdx}: ELIMINATED`);
            } else {
                lines.push(`Player ${playerIdx}: ${opponentHand.length} cards, score: ${gameState.scores[playerIdx] || 0}`);
            }
        }

        lines.push('\n### Your Score');
        lines.push(`Your total score: ${gameState.scores[gameState.currentTurn] || 0} points`);

        if (gameState.lastCardsPlayed && gameState.lastCardsPlayed.length > 0) {
            lines.push('\n### Discard Pile (available to pick)');
            lines.push(this._cardsToNames(gameState.lastCardsPlayed));
        } else {
            lines.push('\n### Discard Pile');
            lines.push('Empty');
        }

        lines.push('\n### Deck Status');
        lines.push(`Cards remaining in deck: ${gameState.deck ? gameState.deck.length : 0}`);

        return lines.join('\n');
    }

    /**
     * Parse LLM response to extract card IDs
     * @param {string} response - LLM response text
     * @param {Array<number>} hand - Available cards in hand
     * @returns {Array<number>|null} Parsed card IDs or null if parsing fails
     */
    _parsePlayResponse(response, hand) {
        // Map suit letters/symbols to suit index
        const SUIT_MAP = {
            'S': 0, 'SPADES': 0, 'SPADE': 0,
            'H': 1, 'HEARTS': 1, 'HEART': 1,
            'C': 2, 'CLUBS': 2, 'CLUB': 2,
            'D': 3, 'DIAMONDS': 3, 'DIAMOND': 3
        };

        // Map rank names to rank index
        const RANK_MAP = {
            'A': 0, 'ACE': 0, '1': 0,
            '2': 1, '3': 2, '4': 3, '5': 4, '6': 5, '7': 6, '8': 7, '9': 8, '10': 9,
            'J': 10, 'JACK': 10,
            'Q': 11, 'QUEEN': 11,
            'K': 12, 'KING': 12
        };

        const foundCards = [];
        const upperResponse = response.toUpperCase();

        // Pattern 1: RankSuit format (e.g., "KS", "10H", "AC")
        const cardPattern = /\b([AKQJ]|10|[2-9])\s*([SHCD])\b/gi;
        let match;

        while ((match = cardPattern.exec(upperResponse)) !== null) {
            const rank = match[1].toUpperCase();
            const suit = match[2].toUpperCase();

            if (RANK_MAP[rank] !== undefined && SUIT_MAP[suit] !== undefined) {
                const cardId = SUIT_MAP[suit] * 13 + RANK_MAP[rank];
                if (hand.includes(cardId) && !foundCards.includes(cardId)) {
                    foundCards.push(cardId);
                }
            }
        }

        // Pattern 2: Check for Joker
        if (/\bJOKER\b|\bJKR\b/i.test(response)) {
            for (const cardId of hand) {
                if (cardId >= 52 && !foundCards.includes(cardId)) {
                    foundCards.push(cardId);
                    break; // Only add one joker per mention
                }
            }
        }

        // If we found cards, validate and return
        if (foundCards.length > 0) {
            return foundCards;
        }

        // Pattern 3: Try to find rank + suit spelled out (e.g., "King of Spades")
        const spelledPattern = /\b(ACE|KING|QUEEN|JACK|10|[2-9])\s*(?:OF\s*)?(SPADES?|HEARTS?|CLUBS?|DIAMONDS?)\b/gi;
        while ((match = spelledPattern.exec(upperResponse)) !== null) {
            const rank = match[1].toUpperCase();
            const suit = match[2].toUpperCase().replace(/S$/, ''); // Remove trailing 'S'

            if (RANK_MAP[rank] !== undefined && SUIT_MAP[suit] !== undefined) {
                const cardId = SUIT_MAP[suit] * 13 + RANK_MAP[rank];
                if (hand.includes(cardId) && !foundCards.includes(cardId)) {
                    foundCards.push(cardId);
                }
            }
        }

        return foundCards.length > 0 ? foundCards : null;
    }

    /**
     * Select cards to play (async version)
     * @param {Array<number>} hand - Bot's hand
     * @param {Object} gameState - Current game state
     * @returns {Promise<Array<number>|null>} Cards to play
     */
    async selectPlayAsync(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // If no Bedrock service, use fallback immediately
        if (!this.bedrockService) {
            logger.warn('LLMBotStrategy: No BedrockService available, using fallback');
            return this.fallbackStrategy.selectPlay(hand, gameState);
        }

        try {
            // Get all valid plays and format them for the LLM
            const validPlays = CardAnalyzer.findAllValidPlays(hand);
            const playsDescription = validPlays.map(play => {
                const remaining = hand.filter(c => !play.includes(c));
                const remainingValue = CardAnalyzer.calculateHandValue(remaining);
                return `- ${this._cardsToNames(play)} (remaining hand: ${remainingValue} points)`;
            }).join('\n');

            const userPrompt = `${this._buildGameStateContext(gameState, hand)}

### Valid Plays Available
${playsDescription}

Based on the current game state and optimal strategy, which cards should I play?
Consider:
1. Minimizing remaining hand value
2. Setting up for ZapZap if close
3. Playing multi-card combinations when beneficial
4. In Golden Score: NEVER play Jokers

Respond with ONLY the cards to play (e.g., "KS, KH" for a pair of Kings).`;

            const response = await this.bedrockService.invokeWithContext(this.systemPrompt, userPrompt);
            const parsedCards = this._parsePlayResponse(response, hand);

            if (parsedCards && parsedCards.length > 0 && CardAnalyzer.isValidPlay(parsedCards)) {
                logger.info('LLM selected play', {
                    cards: this._cardsToNames(parsedCards),
                    response: response.substring(0, 100)
                });
                return parsedCards;
            }

            // LLM response invalid, use fallback
            logger.warn('LLM response could not be parsed to valid play, using fallback', {
                response: response.substring(0, 200),
                parsedCards: parsedCards ? this._cardsToNames(parsedCards) : 'none'
            });
            return this.fallbackStrategy.selectPlay(hand, gameState);

        } catch (error) {
            logger.error('LLM play selection failed', {
                error: error.message,
                stack: error.stack
            });
            if (this.enableFallback) {
                return this.fallbackStrategy.selectPlay(hand, gameState);
            }
            throw error;
        }
    }

    /**
     * Synchronous selectPlay - throws error directing to use async version
     * BotActionService should detect isAsync() and use selectPlayAsync instead
     */
    selectPlay(hand, gameState) {
        // Fallback for sync calls - use fallback strategy
        logger.warn('LLMBotStrategy.selectPlay called synchronously, using fallback');
        return this.fallbackStrategy.selectPlay(hand, gameState);
    }

    /**
     * Decide whether to call ZapZap (async version)
     * @param {Array<number>} hand - Bot's hand
     * @param {Object} gameState - Current game state
     * @returns {Promise<boolean>} True to call ZapZap
     */
    async shouldZapZapAsync(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Can't ZapZap if hand value > 5
        if (handValue > 5) {
            return false;
        }

        // Always ZapZap at 0 points - no risk
        if (handValue === 0) {
            return true;
        }

        // If no Bedrock service, use fallback
        if (!this.bedrockService) {
            return this.fallbackStrategy.shouldZapZap(hand, gameState);
        }

        try {
            // Calculate opponent info for context
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            const activeOpponents = Object.entries(gameState.hands)
                .filter(([idx]) => {
                    const playerIdx = parseInt(idx);
                    return playerIdx !== gameState.currentTurn && !eliminatedPlayers.includes(playerIdx);
                });

            const avgOpponentCards = activeOpponents.length > 0
                ? activeOpponents.reduce((sum, [, h]) => sum + h.length, 0) / activeOpponents.length
                : 0;

            const userPrompt = `${this._buildGameStateContext(gameState, hand)}

### ZapZap Decision
Your hand value is ${handValue} points, which is eligible for ZapZap (<=5).
Average opponent hand size: ${avgOpponentCards.toFixed(1)} cards

Should you call ZapZap now?

Consider:
1. Opponents with few cards (1-3) have higher chance of having low hands = counter risk
2. Opponents with many cards (5+) likely have high hands = safer to ZapZap
3. Your current score vs opponents - risk tolerance
4. If counteracted: +20 penalty plus your hand value

Respond with ONLY "YES" or "NO".`;

            const response = await this.bedrockService.invokeWithContext(this.systemPrompt, userPrompt);
            const shouldCall = /\bYES\b/i.test(response);

            logger.info('LLM ZapZap decision', {
                shouldCall,
                handValue,
                response: response.substring(0, 50)
            });
            return shouldCall;

        } catch (error) {
            logger.error('LLM ZapZap decision failed', { error: error.message });
            return this.fallbackStrategy.shouldZapZap(hand, gameState);
        }
    }

    /**
     * Synchronous shouldZapZap - uses fallback
     */
    shouldZapZap(hand, gameState) {
        logger.warn('LLMBotStrategy.shouldZapZap called synchronously, using fallback');
        return this.fallbackStrategy.shouldZapZap(hand, gameState);
    }

    /**
     * Select draw source (async version)
     * @param {Array<number>} hand - Bot's hand
     * @param {Array<number>} lastCardsPlayed - Discard pile
     * @param {Object} gameState - Current game state
     * @returns {Promise<string>} 'deck' or 'played'
     */
    async selectDrawSourceAsync(hand, lastCardsPlayed, gameState) {
        // If discard pile is empty, must draw from deck
        if (!lastCardsPlayed || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        // If no Bedrock service, use fallback
        if (!this.bedrockService) {
            return this.fallbackStrategy.selectDrawSource(hand, lastCardsPlayed, gameState);
        }

        try {
            // Analyze what picking each discard card would do
            const discardAnalysis = lastCardsPlayed.map(cardId => {
                const newHand = [...hand, cardId];
                const newPlays = CardAnalyzer.findAllValidPlays(newHand);
                const multiCardPlays = newPlays.filter(p => p.length > 1 && p.includes(cardId));
                return {
                    card: this._cardToName(cardId),
                    enablesMultiCardPlays: multiCardPlays.length,
                    isJoker: cardId >= 52
                };
            });

            const discardInfo = discardAnalysis.map(d =>
                `${d.card}: ${d.isJoker ? 'JOKER (valuable!)' : `enables ${d.enablesMultiCardPlays} multi-card plays`}`
            ).join('\n');

            const userPrompt = `${this._buildGameStateContext(gameState, hand)}

### Draw Decision
You must draw a card. Options:

1. **DECK**: Draw unknown card from deck (${gameState.deck ? gameState.deck.length : 0} cards remaining)

2. **DISCARD**: Pick from discard pile:
${discardInfo}

Which option is better for your current hand?

Consider:
1. Does any discard card complete a pair or sequence with your hand?
2. Is there a Joker in discard? (Always valuable to grab!)
3. Picking from discard reveals information to opponents about your strategy
4. In Golden Score: Grabbing Joker denies it from opponent

Respond with ONLY "DECK" or "DISCARD".`;

            const response = await this.bedrockService.invokeWithContext(this.systemPrompt, userPrompt);
            const source = /\bDISCARD\b/i.test(response) ? 'played' : 'deck';

            logger.info('LLM draw decision', {
                source,
                response: response.substring(0, 50)
            });
            return source;

        } catch (error) {
            logger.error('LLM draw decision failed', { error: error.message });
            return this.fallbackStrategy.selectDrawSource(hand, lastCardsPlayed, gameState);
        }
    }

    /**
     * Synchronous selectDrawSource - uses fallback
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        logger.warn('LLMBotStrategy.selectDrawSource called synchronously, using fallback');
        return this.fallbackStrategy.selectDrawSource(hand, lastCardsPlayed, gameState);
    }

    /**
     * Select hand size - simple decision, use fallback (sync is fine)
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size to use
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        // This is a simple decision - no need for LLM
        return this.fallbackStrategy.selectHandSize(activePlayerCount, isGoldenScore);
    }

    /**
     * Check if this strategy requires async execution
     * @returns {boolean} True - this strategy is async
     */
    isAsync() {
        return true;
    }

    /**
     * Get strategy name
     * @returns {string}
     */
    getName() {
        return 'LLM Bot (Llama 3.3)';
    }
}

module.exports = LLMBotStrategy;
