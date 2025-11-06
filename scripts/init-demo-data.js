/**
 * Initialize Demo Data
 * Creates demo users and a party for testing
 */

const { bootstrap, shutdown } = require('../src/api/bootstrap');
const logger = require('../logger');

async function initDemoData() {
    let container;

    try {
        logger.info('Initializing demo data...');

        // Bootstrap application
        container = await bootstrap();

        const registerUser = container.resolve('registerUser');
        const createParty = container.resolve('createParty');
        const joinParty = container.resolve('joinParty');

        // Create demo users
        const usernames = ['Vincent', 'Thibaut', 'Simon', 'Lyo', 'Laurent'];
        const userRepository = container.resolve('userRepository');

        // Register new users and get all users
        for (const username of usernames) {
            try {
                const result = await registerUser.execute({
                    username,
                    password: 'demo123'
                });
                logger.info(`Created user: ${username}`, { userId: result.user.id });
            } catch (error) {
                if (error.message === 'Username already exists') {
                    logger.info(`User already exists: ${username}`);
                } else {
                    throw error;
                }
            }
        }

        // Get all users from database
        const users = [];
        for (const username of usernames) {
            const user = await userRepository.findByUsername(username);
            if (user) {
                users.push(user);
                logger.info(`Retrieved user: ${username}`, { userId: user.id });
            } else {
                logger.warn(`User not found: ${username}`);
            }
        }

        logger.info(`Total users found: ${users.length}`);

        // Create a demo party with the first user
        if (users.length > 0) {
            logger.info(`Creating party with owner`, { userId: users[0].id, username: users[0].username });
            try {
                const partyResult = await createParty.execute({
                    ownerId: users[0].id,
                    name: 'Demo Game',
                    visibility: 'public',
                    settings: {
                        playerCount: 5,
                        handSize: 7
                    }
                });

                logger.info('Created demo party', {
                    partyId: partyResult.party.id,
                    inviteCode: partyResult.party.inviteCode
                });

                // Have other users join
                for (let i = 1; i < Math.min(users.length, 4); i++) {
                    try {
                        await joinParty.execute({
                            userId: users[i].id,
                            partyId: partyResult.party.id
                        });
                        logger.info(`User ${usernames[i]} joined party`);
                    } catch (error) {
                        logger.error(`Failed to join party for ${usernames[i]}`, {
                            error: error.message
                        });
                    }
                }

                console.log('\n');
                console.log('========================================');
                console.log('Demo Data Initialized Successfully!');
                console.log('========================================');
                console.log('');
                console.log('Demo Users (username / password):');
                usernames.forEach(username => {
                    console.log(`  - ${username} / demo123`);
                });
                console.log('');
                console.log('Demo Party:');
                console.log(`  - Party ID: ${partyResult.party.id}`);
                console.log(`  - Invite Code: ${partyResult.party.inviteCode}`);
                console.log(`  - Name: ${partyResult.party.name}`);
                console.log('');
                console.log('API Endpoints:');
                console.log('  - POST /api/auth/login - Login with username/password');
                console.log('  - GET /api/party - List public parties');
                console.log('  - GET /api/game/:partyId/state - Get game state');
                console.log('');
                console.log('========================================');
                console.log('');
            } catch (error) {
                logger.error('Failed to create demo party', { error: error.message });
                throw error;
            }
        }

        logger.info('Demo data initialization complete');
    } catch (error) {
        logger.error('Failed to initialize demo data', {
            error: error.message,
            stack: error.stack
        });
        process.exit(1);
    } finally {
        if (container) {
            await shutdown(container);
        }
    }
}

// Run if called directly
if (require.main === module) {
    initDemoData()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
}

module.exports = initDemoData;
