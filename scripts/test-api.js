/**
 * API Integration Test
 * Tests the new clean architecture API endpoints
 */

const http = require('http');
const logger = require('../logger');

const BASE_URL = 'http://localhost:9999';
let authToken = null;
let userId = null;
let partyId = null;

/**
 * Make HTTP request
 */
function makeRequest(method, path, data = null, token = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, BASE_URL);
        const options = {
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + url.search,
            method: method,
            headers: {
                'Content-Type': 'application/json'
            }
        };

        if (token) {
            options.headers['Authorization'] = `Bearer ${token}`;
        }

        const req = http.request(options, (res) => {
            let body = '';

            res.on('data', (chunk) => {
                body += chunk;
            });

            res.on('end', () => {
                try {
                    const response = {
                        statusCode: res.statusCode,
                        headers: res.headers,
                        body: body ? JSON.parse(body) : null
                    };
                    resolve(response);
                } catch (error) {
                    reject(new Error(`Failed to parse response: ${error.message}`));
                }
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (data) {
            req.write(JSON.stringify(data));
        }

        req.end();
    });
}

/**
 * Test user login
 */
async function testLogin() {
    logger.info('Testing login...');

    const response = await makeRequest('POST', '/api/auth/login', {
        username: 'Vincent',
        password: 'demo123'
    });

    if (response.statusCode !== 200) {
        throw new Error(`Login failed: ${JSON.stringify(response.body)}`);
    }

    if (!response.body.token || !response.body.user) {
        throw new Error('Login response missing token or user');
    }

    authToken = response.body.token;
    userId = response.body.user.id;

    logger.info('✓ Login successful', {
        userId: userId,
        username: response.body.user.username
    });
}

/**
 * Test listing public parties
 */
async function testListParties() {
    logger.info('Testing list parties...');

    const response = await makeRequest('GET', '/api/party');

    if (response.statusCode !== 200) {
        throw new Error(`List parties failed: ${JSON.stringify(response.body)}`);
    }

    if (!Array.isArray(response.body.parties)) {
        throw new Error('List parties response missing parties array');
    }

    logger.info('✓ List parties successful', {
        count: response.body.parties.length
    });

    // Find the demo party
    const demoParty = response.body.parties.find(p => p.name === 'Demo Game');
    if (demoParty) {
        partyId = demoParty.id;
        logger.info('Found demo party', { partyId });
    }

    return response.body.parties;
}

/**
 * Test getting party details
 */
async function testPartyDetails() {
    if (!partyId) {
        logger.warn('Skipping party details test - no party ID');
        return;
    }

    logger.info('Testing party details...');

    const response = await makeRequest('GET', `/api/party/${partyId}`, null, authToken);

    if (response.statusCode === 403) {
        logger.info('✓ Party details requires membership (expected behavior)');
        return;
    }

    if (response.statusCode !== 200) {
        throw new Error(`Party details failed: ${JSON.stringify(response.body)}`);
    }

    logger.info('✓ Party details successful', {
        partyId: response.body.party.id,
        players: response.body.players.length
    });
}

/**
 * Test getting game state
 */
async function testGameState() {
    if (!partyId) {
        logger.warn('Skipping game state test - no party ID');
        return;
    }

    logger.info('Testing game state...');

    const response = await makeRequest('GET', `/api/game/${partyId}/state`, null, authToken);

    if (response.statusCode === 403) {
        logger.info('✓ Game state requires membership (expected behavior)');
        return;
    }

    if (response.statusCode !== 200) {
        throw new Error(`Game state failed: ${JSON.stringify(response.body)}`);
    }

    logger.info('✓ Game state successful', {
        partyId: response.body.partyId,
        status: response.body.party.status
    });
}

/**
 * Test health endpoint
 */
async function testHealth() {
    logger.info('Testing health endpoint...');

    const response = await makeRequest('GET', '/api/health');

    if (response.statusCode !== 200) {
        throw new Error(`Health check failed: ${JSON.stringify(response.body)}`);
    }

    if (response.body.status !== 'ok') {
        throw new Error('Health check returned non-ok status');
    }

    logger.info('✓ Health check successful');
}

/**
 * Run all tests
 */
async function runTests() {
    try {
        logger.info('========================================');
        logger.info('Starting API Integration Tests');
        logger.info('========================================');

        await testHealth();
        await testLogin();
        await testListParties();
        await testPartyDetails();
        await testGameState();

        logger.info('========================================');
        logger.info('✓ All API tests passed!');
        logger.info('========================================');

        process.exit(0);
    } catch (error) {
        logger.error('✗ API test failed', {
            error: error.message,
            stack: error.stack
        });
        process.exit(1);
    }
}

// Check if server is running
logger.info('Checking if server is running...');
makeRequest('GET', '/api/health')
    .then(() => {
        logger.info('Server is running, starting tests...');
        runTests();
    })
    .catch(() => {
        logger.error('Server is not running. Please start the server with: npm start');
        process.exit(1);
    });
