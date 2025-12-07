/**
 * GetAdminStatistics Use Case
 * Retrieves global platform statistics for admin dashboard
 */

const logger = require('../../../logger');

class GetAdminStatistics {
    /**
     * @param {PartyRepository} partyRepository - Party repository
     * @param {UserRepository} userRepository - User repository
     */
    constructor(partyRepository, userRepository) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @returns {Promise<Object>} Platform statistics
     */
    async execute() {
        try {
            // Get user counts
            const totalUsers = await this.userRepository.countHumans();

            // Get party counts
            const totalParties = await this.partyRepository.countAllParties();
            const waitingParties = await this.partyRepository.countAllParties('waiting');
            const playingParties = await this.partyRepository.countAllParties('playing');
            const finishedParties = await this.partyRepository.countAllParties('finished');

            // Get total rounds
            const totalRounds = await this.partyRepository.countTotalRounds();

            // Get games per period (for chart)
            const gamesPerDay = await this.partyRepository.getGamesPerPeriod('day');
            const gamesPerWeek = await this.partyRepository.getGamesPerPeriod('week');
            const gamesPerMonth = await this.partyRepository.getGamesPerPeriod('month');

            // Get most active users
            const mostActiveUsers = await this.partyRepository.getMostActiveUsers(10);

            // Calculate completion rate
            const completionRate = totalParties > 0
                ? ((finishedParties / totalParties) * 100).toFixed(1)
                : 0;

            logger.debug('Admin statistics retrieved');

            return {
                success: true,
                stats: {
                    users: {
                        total: totalUsers
                    },
                    parties: {
                        total: totalParties,
                        waiting: waitingParties,
                        playing: playingParties,
                        finished: finishedParties,
                        completionRate: parseFloat(completionRate)
                    },
                    rounds: {
                        total: totalRounds
                    },
                    gamesOverTime: {
                        daily: gamesPerDay,
                        weekly: gamesPerWeek,
                        monthly: gamesPerMonth
                    },
                    mostActiveUsers
                }
            };
        } catch (error) {
            logger.error('Failed to get admin statistics', { error: error.message });
            throw new Error(`Failed to get admin statistics: ${error.message}`);
        }
    }
}

module.exports = GetAdminStatistics;
