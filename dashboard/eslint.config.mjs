import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import prettier from 'eslint-config-prettier'
import globals from 'globals'

// Flat config for the Éist SPA (app/javascript). Type-checking is `tsc --noEmit`;
// this covers correctness (unused vars, hooks rules) and lets Prettier own formatting.
export default tseslint.config(
  { ignores: ['**/dist/**', '**/build/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  // Everything here runs in the browser (the SPA and the Stimulus controllers).
  {
    languageOptions: {
      ecmaVersion: 2022,
      globals: { ...globals.browser },
    },
  },
  {
    files: ['**/*.{ts,tsx}'],
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
  // The Stimulus controllers are plain browser JS, not the typed SPA — no type-checking.
  { files: ['**/*.js'], ...tseslint.configs.disableTypeChecked },
  prettier,
)
