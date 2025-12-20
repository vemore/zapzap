/**
 * ReflectOnRound Use Case
 * Triggers LLM reflection after each round to learn from decisions
 */

const logger = require('../../../logger');
const LLMBotMemory = require('../../infrastructure/bot/LLMBotMemory');
const { CATEGORIES } = LLMBotMemory;

class ReflectOnRound {
    /**
     * @param {Object} bedrockService - BedrockService for LLM calls
     */
    constructor(bedrockService) {
        this.bedrockService = bedrockService;
    }

    /**
     * Execute round reflection
     * @param {Object} request
     * @param {string} request.botUserId - Bot user ID
     * @param {string} request.partyId - Party ID
     * @param {number} request.roundNumber - Round number
     * @param {Object} request.outcome - Round outcome
     * @param {boolean} request.outcome.won - Whether bot won the round
     * @param {boolean} request.outcome.counteracted - Whether bot was counteracted
     * @param {number} request.outcome.scoreChange - Points added this round
     * @param {number} request.outcome.handPoints - Final hand points
     * @param {Array} request.outcome.finalHand - Final hand cards
     * @param {Object} request.gameState - Game state at end of round
     */
    async execute(request) {
        const { botUserId, partyId, roundNumber, outcome, gameState } = request;

        // Skip if no bedrock service
        if (!this.bedrockService) {
            logger.debug('ReflectOnRound skipped - no BedrockService');
            return { success: false, reason: 'no_bedrock_service' };
        }

        try {
            // Load bot memory
            const memory = new LLMBotMemory(botUserId);
            await memory.load();

            // Get decisions made this round
            const decisions = memory.getDecisionsForRound(roundNumber);

            if (decisions.length === 0) {
                logger.debug('ReflectOnRound skipped - no decisions tracked', {
                    botUserId,
                    roundNumber
                });
                return { success: false, reason: 'no_decisions' };
            }

            // Build reflection prompt
            const prompt = this._buildReflectionPrompt(roundNumber, outcome, decisions, gameState);

            // Call LLM for reflection
            const systemPrompt = this._buildSystemPrompt();
            const response = await this.bedrockService.invokeWithContext(systemPrompt, prompt);

            // Parse insights from response
            const insights = this._parseInsights(response);

            // Add insights to memory
            for (const insight of insights) {
                memory.addStrategy(
                    insight.text,
                    insight.category,
                    { partyId, roundNumber, outcome: outcome.won ? 'won' : 'lost' },
                    0.5 // Initial confidence
                );
            }

            // Clear round decisions and increment counter
            memory.clearRoundDecisions(roundNumber);
            memory.incrementRoundsAnalyzed();

            // Save memory
            await memory.save();

            logger.info('Round reflection completed', {
                botUserId,
                roundNumber,
                insightsGenerated: insights.length
            });

            return {
                success: true,
                insightsGenerated: insights.length,
                insights: insights.map(i => i.text)
            };

        } catch (error) {
            logger.error('ReflectOnRound failed', {
                botUserId,
                roundNumber,
                error: error.message
            });
            return { success: false, reason: error.message };
        }
    }

    /**
     * Build system prompt for reflection
     * @private
     */
    _buildSystemPrompt() {
        return `Tu es un expert du jeu de cartes ZapZap qui analyse ses propres décisions pour s'améliorer.

## Règles de ZapZap (rappel)
- But: réduire la valeur de sa main et appeler ZapZap quand ≤5 points
- Valeurs: A=1, 2-10=face, J=11, Q=12, K=13, Joker=0 (ou 25 si pénalité)
- Coups valides: cartes seules, paires/brelans, suites (3+ cartes même couleur)
- Si contre: +main + (joueurs-1)×5 points de pénalité

## Ta tâche
Analyser les décisions d'un round et générer 0-1 insight stratégique.

## Format de réponse
- Si nouvel insight: [catégorie] insight (max 100 caractères)
- Si pas de nouvel insight: NO_NEW_INSIGHTS

Catégories valides:
- play_strategy: stratégie de jeu de cartes
- zapzap_timing: timing pour appeler ZapZap
- draw_decision: choix entre pioche et défausse
- golden_score: stratégie en Golden Score

Exemples:
[play_strategy] Jouer les figures (V,D,R) en priorité réduit la main plus vite
[zapzap_timing] Appeler ZapZap à 5pts quand adversaires ont 2-3 cartes = risqué
[draw_decision] Prendre les Jokers de la défausse est toujours rentable

Sois concis et actionnable. Un seul insight maximum.`;
    }

    /**
     * Build reflection prompt with round context
     * @private
     */
    _buildReflectionPrompt(roundNumber, outcome, decisions, gameState) {
        const lines = [];

        lines.push(`## Résumé du Round ${roundNumber}`);
        lines.push(`- Résultat: ${this._outcomeToText(outcome)}`);
        lines.push(`- Score ce round: ${outcome.scoreChange > 0 ? '+' : ''}${outcome.scoreChange} points`);
        lines.push(`- Valeur main finale: ${outcome.handPoints} points`);

        if (outcome.finalHand) {
            lines.push(`- Main finale: ${this._cardsToText(outcome.finalHand)}`);
        }

        lines.push('\n## Tes décisions ce round');
        for (const decision of decisions) {
            lines.push(this._decisionToText(decision));
        }

        if (gameState && gameState.isGoldenScore) {
            lines.push('\n## Contexte: Golden Score (2 joueurs restants)');
        }

        lines.push('\n## Analyse');
        lines.push('Quelle décision a le plus impacté ce résultat ?');
        lines.push('Y a-t-il un pattern à retenir pour les prochaines parties ?');

        return lines.join('\n');
    }

    /**
     * Convert outcome to readable text
     * @private
     */
    _outcomeToText(outcome) {
        if (outcome.counteracted) {
            return 'CONTRÉ (ZapZap échoué)';
        } else if (outcome.won) {
            return 'GAGNÉ (meilleure main ou ZapZap réussi)';
        } else {
            return 'PERDU (main trop haute)';
        }
    }

    /**
     * Convert cards to readable text
     * @private
     */
    _cardsToText(cards) {
        if (!Array.isArray(cards) || cards.length === 0) return 'aucune';

        const SUITS = ['P', 'C', 'T', 'K']; // Pique, Coeur, Trèfle, Carreau
        const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];

        return cards.map(id => {
            if (id >= 52) return 'JKR';
            const suit = SUITS[Math.floor(id / 13)];
            const rank = RANKS[id % 13];
            return `${rank}${suit}`;
        }).join(', ');
    }

    /**
     * Convert decision to readable text
     * @private
     */
    _decisionToText(decision) {
        const d = decision.details || {};

        switch (decision.type) {
            case 'play':
                return `- JOUÉ: ${this._cardsToText(d.cards)} (main: ${d.handBefore}→${d.handAfter} pts)`;
            case 'draw':
                return `- PIOCHÉ: ${d.source === 'deck' ? 'pioche' : 'défausse'}${d.cardDrawn ? ` (${this._cardsToText([d.cardDrawn])})` : ''}`;
            case 'zapzap':
                return `- ZAPZAP: appelé à ${d.handValue} pts → ${d.success ? 'RÉUSSI' : 'CONTRÉ'}`;
            default:
                return `- ${decision.type}: ${JSON.stringify(d)}`;
        }
    }

    /**
     * Parse insights from LLM response
     * @private
     */
    _parseInsights(response) {
        const insights = [];

        // Check for no insights
        if (/NO_NEW_INSIGHTS/i.test(response)) {
            return insights;
        }

        // Parse [category] insight format
        const pattern = /\[(play_strategy|zapzap_timing|draw_decision|golden_score|opponent_reading)\]\s*(.+)/gi;
        let match;

        while ((match = pattern.exec(response)) !== null) {
            const category = match[1].toLowerCase();
            const text = match[2].trim().substring(0, 100); // Limit to 100 chars

            if (text.length > 10) { // Ignore too short insights
                insights.push({ category, text });
            }
        }

        // Limit to 1 insight per round
        return insights.slice(0, 1);
    }
}

module.exports = ReflectOnRound;
