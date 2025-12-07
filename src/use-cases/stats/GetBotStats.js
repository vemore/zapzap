/**
 * GetBotStats Use Case
 * Retrieves statistics for all bots, grouped by difficulty
 */

const logger = require('../../../logger');

class GetBotStats {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     */
    constructor(partyRepository) {
        this.partyRepository = partyRepository;
    }

    /**
     * Execute the use case
     * @returns {Promise<Object>} Bot statistics result
     */
    async execute() {
        try {
            // Get bot stats from repository
            const rawStats = await this.partyRepository.getBotStats();

            // Transform difficulty stats
            const byDifficulty = rawStats.byDifficulty.map(d => ({
                difficulty: d.difficulty,
                botCount: d.bot_count,
                gamesPlayed: d.games_played,
                roundsPlayed: d.total_rounds || 0,
                wins: d.wins,
                winRate: d.games_played > 0 ? d.wins / d.games_played : 0,
                zapzaps: {
                    total: d.zapzap_total || 0,
                    successful: d.zapzap_success || 0,
                    failed: d.zapzap_failed || 0,
                    successRate: (d.zapzap_total || 0) > 0
                        ? (d.zapzap_success || 0) / (d.zapzap_total || 0)
                        : 0
                },
                lowestHandCount: d.lowest_hand_count || 0,
                roundWinRate: (d.total_rounds || 0) > 0
                    ? (d.lowest_hand_count || 0) / (d.total_rounds || 0)
                    : 0
            }));

            // Transform individual bot stats
            const byBot = rawStats.byBot.map(b => ({
                botId: b.bot_id,
                username: b.username,
                difficulty: b.difficulty,
                gamesPlayed: b.games_played,
                roundsPlayed: b.total_rounds || 0,
                wins: b.wins,
                winRate: b.games_played > 0 ? b.wins / b.games_played : 0,
                zapzaps: {
                    total: b.zapzap_total || 0,
                    successful: b.zapzap_success || 0,
                    failed: b.zapzap_failed || 0,
                    successRate: (b.zapzap_total || 0) > 0
                        ? (b.zapzap_success || 0) / (b.zapzap_total || 0)
                        : 0
                },
                lowestHandCount: b.lowest_hand_count || 0
            }));

            // Calculate totals
            const totals = {
                totalBots: byDifficulty.reduce((sum, d) => sum + d.botCount, 0),
                totalGamesPlayed: byDifficulty.reduce((sum, d) => sum + d.gamesPlayed, 0),
                totalRoundsPlayed: byDifficulty.reduce((sum, d) => sum + d.roundsPlayed, 0),
                totalWins: byDifficulty.reduce((sum, d) => sum + d.wins, 0),
                totalZapzapCalls: byDifficulty.reduce((sum, d) => sum + d.zapzaps.total, 0),
                totalSuccessfulZapzaps: byDifficulty.reduce((sum, d) => sum + d.zapzaps.successful, 0)
            };

            totals.overallWinRate = totals.totalGamesPlayed > 0
                ? totals.totalWins / totals.totalGamesPlayed
                : 0;
            totals.overallZapzapSuccessRate = totals.totalZapzapCalls > 0
                ? totals.totalSuccessfulZapzaps / totals.totalZapzapCalls
                : 0;

            logger.debug('Bot stats retrieved', {
                difficulties: byDifficulty.length,
                totalBots: totals.totalBots,
                totalGames: totals.totalGamesPlayed
            });

            return {
                success: true,
                totals,
                byDifficulty,
                byBot
            };
        } catch (error) {
            logger.error('Get bot stats error', { error: error.message });
            throw error;
        }
    }
}

module.exports = GetBotStats;
