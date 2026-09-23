import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  // public/elements.cardmeister.full.js is a vendored, minified third-party bundle.
  globalIgnores(['dist', 'public/elements.cardmeister.full.js']),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs['recommended-latest'],
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
      parserOptions: {
        ecmaVersion: 'latest',
        ecmaFeatures: { jsx: true },
        sourceType: 'module',
      },
    },
    rules: {
      // Core no-unused-vars cannot see JSX: `<Foo>` is covered by the capitalised
      // pattern (for a destructured `{ icon: Icon }` argument too), and `motion`
      // (framer-motion's `<motion.div>`) is the one lowercase namespace the
      // components use.
      'no-unused-vars': ['error', {
        varsIgnorePattern: '^([A-Z_]|motion$)',
        argsIgnorePattern: '^[A-Z_]',
      }],
    },
  },
  {
    // vitest runs in Node: its setup and tests may touch Node globals.
    files: ['src/test/**', '**/__tests__/**'],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
  },
])
