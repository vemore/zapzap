/**
 * ReflectOnGame Use Case
 * Triggers LLM reflection after game ends to learn from overall performance
 * Called for ALL bots (winners and losers) to maximize learning
 */

const logger = require('../../../logger');
const LLMBotMemory = require('../../infrastructure/bot/LLMBotMemory');
const { CATEGORIES } = LLMBotMemory;

class ReflectOnGame {
    /**
     * @param {Object} bedrockService - BedrockService for LLM calls
     * @param {Object} partyRepository - Party repository for game data
     */
    constructor(bedrockService, partyRepository = null) {
        this.bedrockService = bedrockService;
        this.partyRepository = partyRepository;
    }

    /**
     * Execute game reflection
     * @param {Object} request
     * @param {string} request.botUserId - Bot user ID
     * @param {string} request.partyId - Party ID
     * @param {number} request.totalRounds - Total rounds played
     * @param {number} request.finalPosition - Final position (1 = winner)
     * @param {number} request.finalScore - Final score
     * @param {boolean} request.isWinner - Whether bot won the game
     * @param {boolean} request.wasGoldenScore - Whether game ended in Golden Score
     * @param {Array} request.roundSummaries - Optional summaries of each round
     */
    async execute(request) {
        const {
            botUserId,
            partyId,
            totalRounds,
            finalPosition,
            finalScore,
            isWinner,
            wasGoldenScore,
            roundSummaries
        } = request;

        // Skip if no bedrock service
        if (!this.bedrockService) {
            logger.debug('ReflectOnGame skipped - no BedrockService');
            return { success: false, reason: 'no_bedrock_service' };
        }

        try {
            // Load bot memory
            const memory = new LLMBotMemory(botUserId);
            await memory.load();

            // Get all decisions from the game
            const allDecisions = memory.getAllDecisions();
            const decisionCount = Object.values(allDecisions).flat().length;

            // Build game summary
            const gameSummary = {
                partyId,
                totalRounds,
                finalPosition,
                finalScore,
                isWinner,
                wasGoldenScore,
                decisionCount
            };

            // Build reflection prompt
            const prompt = this._buildReflectionPrompt(gameSummary, allDecisions, roundSummaries);

            // Call LLM for reflection
            const systemPrompt = this._buildSystemPrompt();
            const response = await this.bedrockService.invokeWithContext(systemPrompt, prompt);

            // Parse insights from response
            const insights = this._parseInsights(response);

            // Add insights to memory with higher confidence for game-level insights
            for (const insight of insights) {
                memory.addStrategy(
                    insight.text,
                    insight.category,
                    {
                        partyId,
                        totalRounds,
                        outcome: isWinner ? 'won' : 'lost',
                        position: finalPosition
                    },
                    isWinner ? 0.7 : 0.5 // Higher confidence if won
                );
            }

            // Add game to history
            memory.addGameHistory(gameSummary);

            // Clear all decisions and increment counter
            memory.clearAllDecisions();
            memory.incrementGamesAnalyzed();

            // Save memory
            await memory.save();

            logger.info('Game reflection completed', {
                botUserId,
                partyId,
                isWinner,
                finalPosition,
                insightsGenerated: insights.length
            });

            return {
                success: true,
                insightsGenerated: insights.length,
                insights: insights.map(i => i.text)
            };

        } catch (error) {
            logger.error('ReflectOnGame failed', {
                botUserId,
                partyId,
                error: error.message
            });
            return { success: false, reason: error.message };
        }
    }

    /**
     * Build system prompt for game reflection
     * @private
     */
    _buildSystemPrompt() {
        return `Tu es un expert du jeu de cartes ZapZap qui analyse sa performance globale sur une partie complète.

## Règles de ZapZap (rappel)
- But: réduire la valeur de sa main et appeler ZapZap quand ≤5 points
- Élimination à 100+ points, dernier joueur ≤100 gagne
- Golden Score: quand il reste 2 joueurs, le round décisif
- Si ZapZap contré: +main + (joueurs-1)×5 points de pénalité

## Ta tâche
Analyser ta performance sur l'ensemble de la partie et générer 0-2 insights stratégiques de haut niveau.

## Format de réponse
- Si insights: [catégorie] insight (max 100 caractères par insight)
- Si pas d'insight: NO_NEW_INSIGHTS

Catégories valides:
- play_strategy: patterns de jeu de cartes
- zapzap_timing: timing des appels ZapZap
- draw_decision: stratégie de pioche
- golden_score: stratégie en Golden Score
- opponent_reading: lecture des adversaires

Exemples:
[play_strategy] Vider sa main rapidement (5-6 cartes) force les adversaires à jouer défensif
[zapzap_timing] En début de partie, être patient et attendre 2-3 pts plutôt que 5
[golden_score] En Golden Score, garder les Jokers jusqu'au dernier tour
[opponent_reading] Quand adversaire pioche en défausse, il prépare une combinaison

Focus sur les patterns récurrents, pas les situations ponctuelles.
Maximum 2 insights.`;
    }

    /**
     * Build reflection prompt with game context
     * @private
     */
    _buildReflectionPrompt(gameSummary, allDecisions, roundSummaries) {
        const lines = [];

        // Game summary
        lines.push('## Résumé de la Partie');
        lines.push(`- Rounds joués: ${gameSummary.totalRounds}`);
        lines.push(`- Position finale: ${this._positionToText(gameSummary.finalPosition)}`);
        lines.push(`- Score final: ${gameSummary.finalScore} points`);
        lines.push(`- Résultat: ${gameSummary.isWinner ? 'VICTOIRE' : 'DÉFAITE'}`);

        if (gameSummary.wasGoldenScore) {
            lines.push(`- Mode: Golden Score (partie serrée)`);
        }

        // Decision statistics
        const decisionStats = this._computeDecisionStats(allDecisions);
        lines.push('\n## Statistiques de Décisions');
        lines.push(`- Total décisions: ${decisionStats.total}`);
        lines.push(`- Plays: ${decisionStats.plays}`);
        lines.push(`- Draws: ${decisionStats.draws} (pioche: ${decisionStats.deckDraws}, défausse: ${decisionStats.discardDraws})`);
        lines.push(`- ZapZap appelés: ${decisionStats.zapzaps} (réussis: ${decisionStats.zapzapSuccess})`);

        // Round by round summary if available
        if (roundSummaries && roundSummaries.length > 0) {
            lines.push('\n## Résumé par Round');
            for (const round of roundSummaries) {
                lines.push(`- R${round.number}: ${round.outcome} (${round.scoreChange > 0 ? '+' : ''}${round.scoreChange} pts)`);
            }
        } else {
            // Generate basic round summary from decisions
            lines.push('\n## Rounds');
            const roundNumbers = Object.keys(allDecisions).map(Number).sort((a, b) => a - b);
            for (const rn of roundNumbers) {
                const roundDecisions = allDecisions[rn] || [];
                const hasZapZap = roundDecisions.some(d => d.type === 'zapzap');
                lines.push(`- Round ${rn}: ${roundDecisions.length} décisions${hasZapZap ? ' (ZapZap)' : ''}`);
            }
        }

        // Analysis questions
        lines.push('\n## Analyse Globale');
        if (gameSummary.isWinner) {
            lines.push('Tu as GAGNÉ cette partie. Quels patterns ont contribué à ta victoire ?');
        } else {
            lines.push('Tu as PERDU cette partie. Quels patterns ont mené à ta défaite ?');
            lines.push('Qu\'aurais-tu pu faire différemment ?');
        }

        if (gameSummary.wasGoldenScore) {
            lines.push('La partie s\'est terminée en Golden Score - qu\'as-tu appris sur ce mode ?');
        }

        return lines.join('\n');
    }

    /**
     * Convert position to readable text
     * @private
     */
    _positionToText(position) {
        switch (position) {
            case 1: return '1er (Vainqueur)';
            case 2: return '2ème';
            case 3: return '3ème';
            case 4: return '4ème';
            default: return `${position}ème`;
        }
    }

    /**
     * Compute statistics from decisions
     * @private
     */
    _computeDecisionStats(allDecisions) {
        const stats = {
            total: 0,
            plays: 0,
            draws: 0,
            deckDraws: 0,
            discardDraws: 0,
            zapzaps: 0,
            zapzapSuccess: 0
        };

        for (const decisions of Object.values(allDecisions)) {
            for (const d of decisions) {
                stats.total++;

                switch (d.type) {
                    case 'play':
                        stats.plays++;
                        break;
                    case 'draw':
                        stats.draws++;
                        if (d.details?.source === 'deck') {
                            stats.deckDraws++;
                        } else {
                            stats.discardDraws++;
                        }
                        break;
                    case 'zapzap':
                        stats.zapzaps++;
                        if (d.details?.success) {
                            stats.zapzapSuccess++;
                        }
                        break;
                }
            }
        }

        return stats;
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

        // Limit to 2 insights per game
        return insights.slice(0, 2);
    }
}

module.exports = ReflectOnGame;
