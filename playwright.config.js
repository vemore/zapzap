/**
 * Playwright E2E Test Configuration
 * For full-stack testing of ZapZap card game
 */

const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  // Test directory
  testDir: './tests/e2e/scenarios',

  // Maximum time one test can run
  timeout: 30 * 1000,

  // Expect timeout for assertions
  expect: {
    timeout: 5000
  },

  // Run tests sequentially for local debugging
  fullyParallel: false,
  workers: 1,

  // Fail the build on CI if you accidentally left test.only
  forbidOnly: !!process.env.CI,

  // Retry on CI only
  retries: process.env.CI ? 2 : 0,

  // Reporter configuration
  reporter: [
    ['list'],
    ['html', { open: 'never' }],
    ['json', { outputFile: 'tests/e2e/results/results.json' }]
  ],

  // Shared settings for all projects
  use: {
    // Base URL for navigation
    baseURL: 'http://localhost:5173',

    // Collect trace on failure for debugging
    trace: 'retain-on-failure',

    // Screenshot on failure
    screenshot: 'only-on-failure',

    // Video recording on failure
    video: 'retain-on-failure',

    // Headless mode disabled for debugging (set to true for CI)
    headless: false,

    // Browser viewport
    viewport: { width: 1280, height: 720 },

    // Ignore HTTPS errors (for local development)
    ignoreHTTPSErrors: true,

    // Collect console logs
    launchOptions: {
      args: ['--disable-web-security'],
    },
  },

  // Global setup script
  globalSetup: require.resolve('./tests/e2e/setup/playwright.setup.js'),

  // Global teardown script
  globalTeardown: require.resolve('./tests/e2e/setup/playwright.teardown.js'),

  // Configure projects for different browsers
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },

    // Uncomment to test on other browsers
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    // },
  ],

  // Web server configuration
  webServer: [
    {
      // Backend test server (start first to ensure it's ready)
      command: 'node tests/e2e/setup/test-server.js',
      port: 9999,
      timeout: 60 * 1000,
      reuseExistingServer: false, // Always start fresh test server
      stdout: 'ignore', // Reduce noise
      stderr: 'pipe',
    },
    {
      // Frontend dev server
      command: 'npm run dev',
      port: 5173,
      timeout: 120 * 1000,
      reuseExistingServer: !process.env.CI,
      cwd: './frontend',
      stdout: 'ignore',  // Reduce noise
      stderr: 'pipe',
    },
  ],
});
