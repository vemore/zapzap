/**
 * Initialize Bot Users
 * Creates demo bot users for testing the bot system
 */

const path = require('path');
const DatabaseConnection = require('../src/infrastructure/database/sqlite/DatabaseConnection');
const UserRepository = require('../src/infrastructure/database/sqlite/repositories/UserRepository');
const User = require('../src/domain/entities/User');

const logger = require('../logger');

async function initBots() {
    const db = new DatabaseConnection(path.join(__dirname, '../data/zapzap.db'));

    try {
        logger.info('Initializing bots...');

        await db.initialize();
        const userRepository = new UserRepository(db);

        // Define bots to create
        const botsToCreate = [
            { username: 'EasyBot1', difficulty: 'easy' },
            { username: 'EasyBot2', difficulty: 'easy' },
            { username: 'MediumBot1', difficulty: 'medium' },
            { username: 'MediumBot2', difficulty: 'medium' },
            { username: 'HardBot1', difficulty: 'hard' },
            { username: 'HardBot2', difficulty: 'hard' },
            { username: 'Thibot1', difficulty: 'thibot' },
            { username: 'Thibot2', difficulty: 'thibot' }
        ];

        const createdBots = [];

        for (const botConfig of botsToCreate) {
            // Check if bot already exists
            const existing = await userRepository.findByUsername(botConfig.username);
            if (existing) {
                logger.info(`Bot ${botConfig.username} already exists, skipping`);
                createdBots.push(existing);
                continue;
            }

            // Create bot
            const bot = await User.createBot(botConfig.username, botConfig.difficulty);
            const savedBot = await userRepository.save(bot);

            logger.info(`Created bot: ${savedBot.username} (${savedBot.botDifficulty})`);
            createdBots.push(savedBot);
        }

        console.log('\n✅ Bot initialization complete!');
        console.log(`\nCreated ${createdBots.length} bots:\n`);

        // Group by difficulty
        const byDifficulty = {
            easy: createdBots.filter(b => b.botDifficulty === 'easy'),
            medium: createdBots.filter(b => b.botDifficulty === 'medium'),
            hard: createdBots.filter(b => b.botDifficulty === 'hard'),
            thibot: createdBots.filter(b => b.botDifficulty === 'thibot')
        };

        console.log('Easy Bots:');
        byDifficulty.easy.forEach(bot => {
            console.log(`  - ${bot.username} (ID: ${bot.id})`);
        });

        console.log('\nMedium Bots:');
        byDifficulty.medium.forEach(bot => {
            console.log(`  - ${bot.username} (ID: ${bot.id})`);
        });

        console.log('\nHard Bots:');
        byDifficulty.hard.forEach(bot => {
            console.log(`  - ${bot.username} (ID: ${bot.id})`);
        });

        console.log('\nThibot Bots:');
        byDifficulty.thibot.forEach(bot => {
            console.log(`  - ${bot.username} (ID: ${bot.id})`);
        });

        console.log('\nYou can now add these bots to parties via the API:');
        console.log('  POST /api/party/:partyId/join');
        console.log('  Body: { "userId": "<bot-id>" }');
        console.log('');

    } catch (error) {
        logger.error('Bot initialization failed', { error: error.message, stack: error.stack });
        console.error('\n❌ Error:', error.message);
        process.exit(1);
    } finally {
        await db.close();
    }
}

// Run if called directly
if (require.main === module) {
    initBots()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error('Fatal error:', error);
            process.exit(1);
        });
}

module.exports = { initBots };
