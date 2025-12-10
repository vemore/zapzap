/**
 * SimulationStats
 * Tracks simulation statistics and learning progress
 */

class SimulationStats {
    constructor() {
        this.gamesPlayed = 0;
        this.winsByStrategy = {};
        this.winsByPlayerIndex = {};
        this.scoresByStrategy = {};
        this.roundCounts = [];
        this.learningCurve = [];
        this.strategyMatchups = {}; // Track win rates by matchup
    }

    /**
     * Record a completed game
     * @param {Object} result - Game result from HeadlessGameEngine
     * @param {Array<string>} strategyTypes - Strategy type for each player index
     */
    recordGame(result, strategyTypes) {
        this.gamesPlayed++;

        const winnerIndex = result.winner;
        const winnerStrategy = strategyTypes[winnerIndex];

        // Record win by strategy type
        if (!this.winsByStrategy[winnerStrategy]) {
            this.winsByStrategy[winnerStrategy] = 0;
        }
        this.winsByStrategy[winnerStrategy]++;

        // Record win by player index
        if (!this.winsByPlayerIndex[winnerIndex]) {
            this.winsByPlayerIndex[winnerIndex] = 0;
        }
        this.winsByPlayerIndex[winnerIndex]++;

        // Record scores by strategy
        for (let i = 0; i < strategyTypes.length; i++) {
            const strategy = strategyTypes[i];
            if (!this.scoresByStrategy[strategy]) {
                this.scoresByStrategy[strategy] = [];
            }
            this.scoresByStrategy[strategy].push(result.finalScores[i] || 0);
        }

        // Record round count
        this.roundCounts.push(result.totalRounds);

        // Track strategy matchups
        const matchupKey = strategyTypes.sort().join('_vs_');
        if (!this.strategyMatchups[matchupKey]) {
            this.strategyMatchups[matchupKey] = {
                games: 0,
                wins: {}
            };
        }
        this.strategyMatchups[matchupKey].games++;
        if (!this.strategyMatchups[matchupKey].wins[winnerStrategy]) {
            this.strategyMatchups[matchupKey].wins[winnerStrategy] = 0;
        }
        this.strategyMatchups[matchupKey].wins[winnerStrategy]++;

        // Track learning curve (every 100 games)
        if (this.gamesPlayed % 100 === 0) {
            this.learningCurve.push({
                games: this.gamesPlayed,
                winRates: this.getWinRates(),
                avgScores: this.getAverageScores(),
                timestamp: Date.now()
            });
        }
    }

    /**
     * Get win rates by strategy
     * @returns {Object} Map of strategy to win rate (0-1)
     */
    getWinRates() {
        const rates = {};
        const strategyCounts = {};

        // Count total games per strategy
        for (const scores of Object.values(this.scoresByStrategy)) {
            // This counts games where strategy participated
        }

        for (const [strategy, wins] of Object.entries(this.winsByStrategy)) {
            const totalGames = this.scoresByStrategy[strategy]?.length || 0;
            rates[strategy] = totalGames > 0 ? wins / totalGames : 0;
        }

        return rates;
    }

    /**
     * Get win rates by player index (position)
     * @returns {Object} Map of player index to win rate
     */
    getWinRatesByPosition() {
        const rates = {};
        for (const [index, wins] of Object.entries(this.winsByPlayerIndex)) {
            rates[index] = this.gamesPlayed > 0 ? wins / this.gamesPlayed : 0;
        }
        return rates;
    }

    /**
     * Get average scores by strategy
     * @returns {Object} Map of strategy to average final score
     */
    getAverageScores() {
        const avgScores = {};
        for (const [strategy, scores] of Object.entries(this.scoresByStrategy)) {
            if (scores.length > 0) {
                avgScores[strategy] = scores.reduce((a, b) => a + b, 0) / scores.length;
            }
        }
        return avgScores;
    }

    /**
     * Get average rounds per game
     * @returns {number}
     */
    getAverageRounds() {
        if (this.roundCounts.length === 0) return 0;
        return this.roundCounts.reduce((a, b) => a + b, 0) / this.roundCounts.length;
    }

    /**
     * Get summary statistics
     * @returns {Object}
     */
    getSummary() {
        return {
            gamesPlayed: this.gamesPlayed,
            winRates: this.getWinRates(),
            winRatesByPosition: this.getWinRatesByPosition(),
            avgScores: this.getAverageScores(),
            avgRounds: this.getAverageRounds(),
            learningCurve: this.learningCurve
        };
    }

    /**
     * Get detailed report
     * @returns {string}
     */
    getReport() {
        const summary = this.getSummary();
        let report = '\n=== Simulation Report ===\n';
        report += `Total games: ${summary.gamesPlayed}\n`;
        report += `Average rounds per game: ${summary.avgRounds.toFixed(1)}\n\n`;

        report += 'Win Rates by Strategy:\n';
        for (const [strategy, rate] of Object.entries(summary.winRates).sort((a, b) => b[1] - a[1])) {
            const wins = this.winsByStrategy[strategy] || 0;
            const games = this.scoresByStrategy[strategy]?.length || 0;
            report += `  ${strategy}: ${(rate * 100).toFixed(1)}% (${wins}/${games})\n`;
        }

        report += '\nWin Rates by Position:\n';
        for (const [index, rate] of Object.entries(summary.winRatesByPosition)) {
            report += `  Player ${index}: ${(rate * 100).toFixed(1)}%\n`;
        }

        report += '\nAverage Final Scores:\n';
        for (const [strategy, score] of Object.entries(summary.avgScores).sort((a, b) => a[1] - b[1])) {
            report += `  ${strategy}: ${score.toFixed(1)}\n`;
        }

        return report;
    }

    /**
     * Merge stats from another SimulationStats instance (for parallel workers)
     * @param {Object} otherStats - Stats from a worker (JSON format)
     */
    merge(otherStats) {
        if (!otherStats) return;

        this.gamesPlayed += otherStats.gamesPlayed || 0;

        // Merge wins by strategy
        for (const [strategy, wins] of Object.entries(otherStats.winsByStrategy || {})) {
            this.winsByStrategy[strategy] = (this.winsByStrategy[strategy] || 0) + wins;
        }

        // Merge wins by position
        for (const [pos, wins] of Object.entries(otherStats.winsByPlayerIndex || {})) {
            this.winsByPlayerIndex[pos] = (this.winsByPlayerIndex[pos] || 0) + wins;
        }

        // Merge scores by strategy
        for (const [strategy, scores] of Object.entries(otherStats.scoresByStrategy || {})) {
            if (!this.scoresByStrategy[strategy]) {
                this.scoresByStrategy[strategy] = [];
            }
            this.scoresByStrategy[strategy].push(...scores);
        }

        // Merge round counts
        if (otherStats.roundCounts) {
            this.roundCounts.push(...otherStats.roundCounts);
        }

        // Merge strategy matchups
        for (const [matchupKey, matchupData] of Object.entries(otherStats.strategyMatchups || {})) {
            if (!this.strategyMatchups[matchupKey]) {
                this.strategyMatchups[matchupKey] = { games: 0, wins: {} };
            }
            this.strategyMatchups[matchupKey].games += matchupData.games || 0;
            for (const [strategy, wins] of Object.entries(matchupData.wins || {})) {
                this.strategyMatchups[matchupKey].wins[strategy] =
                    (this.strategyMatchups[matchupKey].wins[strategy] || 0) + wins;
            }
        }
    }

    /**
     * Reset all statistics
     */
    reset() {
        this.gamesPlayed = 0;
        this.winsByStrategy = {};
        this.winsByPlayerIndex = {};
        this.scoresByStrategy = {};
        this.roundCounts = [];
        this.learningCurve = [];
        this.strategyMatchups = {};
    }

    /**
     * Export stats to JSON
     * @returns {Object}
     */
    toJSON() {
        return {
            gamesPlayed: this.gamesPlayed,
            winsByStrategy: this.winsByStrategy,
            winsByPlayerIndex: this.winsByPlayerIndex,
            scoresByStrategy: this.scoresByStrategy,
            roundCounts: this.roundCounts,
            learningCurve: this.learningCurve,
            strategyMatchups: this.strategyMatchups
        };
    }

    /**
     * Import stats from JSON
     * @param {Object} data
     */
    fromJSON(data) {
        this.gamesPlayed = data.gamesPlayed || 0;
        this.winsByStrategy = data.winsByStrategy || {};
        this.winsByPlayerIndex = data.winsByPlayerIndex || {};
        this.scoresByStrategy = data.scoresByStrategy || {};
        this.roundCounts = data.roundCounts || [];
        this.learningCurve = data.learningCurve || [];
        this.strategyMatchups = data.strategyMatchups || {};
    }
}

module.exports = SimulationStats;
