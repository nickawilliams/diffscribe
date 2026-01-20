# Changelog

## [v0.1.0](https://github.com/nickawilliams/diffscribe/compare/e1a422f9980850551eeaffa116015d187e8e06b0...v0.1.0) - 2026-01-20

### New Features

- Add quantity flag to control LLM outputs and replace openAIConfig with newLLMConfig builder - ([825fcc4](https://github.com/nickawilliams/diffscribe/commit/825fcc47cb2972bf7783dd66a5ac9b289336227b))
- Add max completion tokens to LLM configuration - ([f7d9feb](https://github.com/nickawilliams/diffscribe/commit/f7d9febb38f676f0e23df36152f56befee70dabe))
- Add prefix handling for commit message suggestions - ([26da7b4](https://github.com/nickawilliams/diffscribe/commit/26da7b4331e7946434d0677c6b1a16ab6dd88d6a))
- Add version flag to display application version - ([4c94395](https://github.com/nickawilliams/diffscribe/commit/4c94395c8af491942197454e6dfb980424fdf54c))
- **Completions**

  - Add Fish shell completion - ([da82127](https://github.com/nickawilliams/diffscribe/commit/da82127e499c339fa7ab6536ef8591be9dfc1243))
  - Add list and menu insert modes - ([15463ef](https://github.com/nickawilliams/diffscribe/commit/15463efbcca0d6360171eba93417530cd7ec9ba2))
  - Add stash-aware diffs for completions - ([f186c38](https://github.com/nickawilliams/diffscribe/commit/f186c38ae3ac06a4521f6e55ed979b89d433b7ba))
  - Implement git completion wrapper for better handling - ([8152dd6](https://github.com/nickawilliams/diffscribe/commit/8152dd6962ff88498a7f0cb0b11f081d38d29299))
  - Add status message during commit completion - ([0315060](https://github.com/nickawilliams/diffscribe/commit/03150605e633a92b5c91a9c4e107e0effc90d5d1))
  - Add support for repeat commit zsh completions - ([23fa205](https://github.com/nickawilliams/diffscribe/commit/23fa205aab99b508843a8d67ad4341b7bd4c82f8))
  - Support DIFFSCRIBE_QUANTITY in bash completions - ([ab004b2](https://github.com/nickawilliams/diffscribe/commit/ab004b232f5084becc8166f72ceed79c0badd521))
  - Added status indicator text for fish completions - ([90e33f7](https://github.com/nickawilliams/diffscribe/commit/90e33f73f0966626df75bb428e5ccc40dbd404ca))
  - Add cursor mode handling for better user experience in fish completions - ([cf8d370](https://github.com/nickawilliams/diffscribe/commit/cf8d3709ade2ff1c02833ce56663a1baf0077a8e))

### Improvements

- Migrate to Cobra for the CLI and Viper for managing configuration - ([c2552af](https://github.com/nickawilliams/diffscribe/commit/c2552af1c27c2763e7943d46cc761c1412fcd6cb))
- Reorganize config keys - ([13865ca](https://github.com/nickawilliams/diffscribe/commit/13865caaf8386c7b5a75fab91d3fbea0121893c4))
- Template-based prompts and config validation for LLM - ([7802177](https://github.com/nickawilliams/diffscribe/commit/7802177eff8c7502d72a56464cd487a833d0d19f))
- Remove manual OPENAI_API_KEY fallback in initConfig - ([51be9fe](https://github.com/nickawilliams/diffscribe/commit/51be9fea23ffd6bd954ce60e41d23a5f7f5043d7))
- Centralize llm config validation in validateConfig - ([6076596](https://github.com/nickawilliams/diffscribe/commit/6076596af088963f019d8f1d119196690d6b9587))
- Drop gen and complete commands, centralize in root - ([6097e27](https://github.com/nickawilliams/diffscribe/commit/6097e2770d712f2ee6bacb1675ea10fbbd9d0b9d))
- Route build outputs to .out/build/$(BINARY) - ([9e06bf8](https://github.com/nickawilliams/diffscribe/commit/9e06bf863c3f247c4f10775f31b975a1753e4129))
- Centralized defaults - ([1e0edcd](https://github.com/nickawilliams/diffscribe/commit/1e0edcdcae64c99161c7592608669b710910aa13))
- Introduce provider abstraction for llm requests - ([61b2a44](https://github.com/nickawilliams/diffscribe/commit/61b2a4487b2121256238cd3237329ab978be60af))
- Modularize config loading logic for better maintainability - ([c47730b](https://github.com/nickawilliams/diffscribe/commit/c47730b857f430bb915457d59d842914fe6f49ef))
- Consolidate zsh completion scripts into a single file - ([941e253](https://github.com/nickawilliams/diffscribe/commit/941e253f72d9472f91a740ca004a4b40462d5047))
- Migrate to new GitHub username - ([dbd3e53](https://github.com/nickawilliams/diffscribe/commit/dbd3e5304ce7621bc63ca2d22d8d07540510a134))
- **Completions**

  - Update `_diffscribe_set_status` for better output handling - ([4a17387](https://github.com/nickawilliams/diffscribe/commit/4a1738716096441d3b353c1931165154909192e3))
  - Simplified fish completions - ([eb475e0](https://github.com/nickawilliams/diffscribe/commit/eb475e0019e4f0d28b25b5da6dbea1b3a509487f))

### Fixes

- **Completions:** Enhance status check logic for commit message completion - ([41632dc](https://github.com/nickawilliams/diffscribe/commit/41632dc860c8b81fe9e905083ef177eb4ed3e5fb))

