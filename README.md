# diffscribe

[![Build Status][ci-image]][ci-url]
[![Code Coverage][coverage-image]][coverage-url]

`diffscribe` is a CLI that inspects your staged Git changes and asks an LLM to craft high-quality Conventional Commit messages for you. It plugs into your shell completion, so `git commit -m "" <TAB>` yields AI suggestions that respect whatever prefix you already typed.

## Installation

Prerequisites: Go 1.21+ and an OpenAI-compatible API key.

```sh
# build and install the binary
make install
# (optional) install completions for all shells
make install/completions/all
# (optional) install the man page
make install/man
```

By default the binary is installed to `/usr/local/bin`. Override `PREFIX` if needed, e.g. `PREFIX=$HOME/.local/bin make install`.

### Shell integration

After installing the binary, enable completion in your shell of choice.

- **Zsh**: add `source ~/.zsh/diffscribe.zsh` to your `.zshrc` (or enable the bundled Oh My Zsh plugin via `plugins+=(diffscribe)`).
- **Bash**: ensure `~/.bash_completion.d/diffscribe.bash` is sourced from `.bashrc`.
- **Fish**: completions auto-load from `~/.config/fish/completions/diffscribe.fish`.

Set `DIFFSCRIBE_STATUS=0` if you want to suppress the in-prompt “loading…” indicator.

### Man page

Run `make install/man` (or `make install/all`) to copy `diffscribe(1)` into your manpath (defaults to `/usr/local/share/man/man1`). Afterwards you can type `man diffscribe` for a concise reference covering flags, environment variables, and config file locations. Regenerate the page after CLI changes with `make man`, which uses Cobra's `doc` helpers to emit `contrib/man/diffscribe.1`.

## Configuration

Provide an API key via `DIFFSCRIBE_API_KEY` or `OPENAI_API_KEY`, or pass `--llm-api-key` at runtime. Configuration lives in `.diffscribe{,.yaml,.toml,.json}`—we merge files in this precedence order:

1. `$XDG_CONFIG_HOME/diffscribe/.diffscribe*` (or `$HOME/.config/diffscribe`)
2. `$HOME/.diffscribe*`
3. `./.diffscribe*` (per-project)

Each file only overrides the keys it specifies, so global defaults flow into project configs. LLM settings sit under an `llm` block, for example:

```yaml
llm:
  apiKey: $DIFFSCRIBE_API_KEY
  provider: openai
  model: gpt-4o-mini
  baseUrl: https://api.openai.com/v1/chat/completions
  temperature: 0.8
  quantity: 5
  maxCompletionTokens: 512
```

## Usage

Stage your changes, then let diffscribe suggest a commit message:

```sh
# show candidates in the terminal
diffscribe

# complete inline while typing
git commit -m "feat: "<TAB>
```

The CLI accepts an optional prefix: `diffscribe "feat: add"` returns suggestions beginning with that text. When used through shell completion, whatever you type after `-m` becomes the prefix automatically.

## Development

Run the test suite (including completion harnesses):

```sh
make test            # Go unit tests + coverage
make test/completions  # Bash, Zsh, Fish completion tests
```

To rebuild the binary: `make build`. Use `make help` to see all targets.

[ci-image]: https://img.shields.io/github/actions/workflow/status/nickawilliams/diffscribe/ci.yaml?logo=GitHub&logoColor=white
[ci-url]: https://github.com/nickawilliams/diffscribe/actions/workflows/ci.yaml
[coverage-image]: https://img.shields.io/codecov/c/github/nickawilliams/diffscribe?logo=codecov&logoColor=white
[coverage-url]: https://codecov.io/gh/nickawilliams/diffscribe
