# diffscribe

[![Build Status][ci-image]][ci-url]
[![Code Coverage][coverage-image]][coverage-url]

`diffscribe` is a CLI that inspects your staged Git changes and asks an LLM to craft high-quality commit messages for you. It plugs into your shell completion, so `git commit -m "" <TAB>` yields AI suggestions that respect whatever prefix you already typed. The default format is [Conventional Commits](https://www.conventionalcommits.org/), but you can customize it via the `--format` flag or config file.

## Installation

### Homebrew (macOS)

```sh
brew install nickawilliams/tap/diffscribe
```

### MacPorts (macOS)

```sh
sudo port install diffscribe
```

### Go

```sh
go install github.com/nickawilliams/diffscribe@latest
```

### Linux

Download `.deb` or `.rpm` packages from the [latest release](https://github.com/nickawilliams/diffscribe/releases/latest), then install:

```sh
# Debian / Ubuntu (apt 1.1+)
sudo apt install <url>.deb

# Debian / Ubuntu (older apt)
curl -LO <url>.deb && sudo dpkg -i diffscribe_*_amd64.deb

# Fedora / RHEL
sudo dnf install <url>.rpm
```

Replace `<url>` with the package link for your architecture from the release page.

### From source

Requires Go 1.25+.

```sh
make install              # binary only
make install/all          # binary + shell completions + man page
```

The binary installs to `/usr/local/bin` by default. Override with `PREFIX`, e.g. `PREFIX=$HOME/.local make install`.

## Quick start

1. Set your API key:

   ```sh
   export DIFFSCRIBE_API_KEY="sk-..."
   ```

   Or use `OPENAI_API_KEY`, or pass `--llm-api-key` at runtime.

2. Stage some changes and run:

   ```sh
   diffscribe
   ```

   diffscribe prints numbered commit message candidates to choose from.

3. Optionally, provide a prefix to constrain suggestions:

   ```sh
   diffscribe "feat: add"
   ```

## Shell completion

The real power of diffscribe is inline completion while writing commit messages. Install completions for your shell, then use `<TAB>` to trigger suggestions:

```sh
git commit -m "feat: " <TAB>
```

Whatever you type after `-m` becomes the prefix automatically.

### Installing completions

Homebrew and MacPorts install completions automatically. For other installation methods:

```sh
make install/completions/all    # all shells at once
make install/completions/zsh    # zsh only
make install/completions/bash   # bash only
make install/completions/fish   # fish only
```

### Enabling completions

- **Zsh** — add `source ~/.zsh/diffscribe.zsh` to your `.zshrc`, or enable the bundled Oh My Zsh plugin: `plugins+=(diffscribe)`.
- **Bash** — ensure `~/.bash_completion.d/diffscribe.bash` is sourced from `.bashrc`.
- **Fish** — completions auto-load from `~/.config/fish/completions/diffscribe.fish`.

Set `DIFFSCRIBE_STATUS=0` to suppress the in-prompt loading indicator.

## Configuration

Configuration lives in `.diffscribe{,.yaml,.toml,.json}` and is merged in this precedence order:

1. `$XDG_CONFIG_HOME/diffscribe/.diffscribe*` (or `$HOME/.config/diffscribe`)
2. `$HOME/.diffscribe*`
3. `./.diffscribe*` (per-project)

Each file only overrides the keys it specifies, so global defaults flow into project-level configs. LLM settings sit under an `llm` block:

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

### Flags

| Flag                          | Description                       | Default              |
| ----------------------------- | --------------------------------- | -------------------- |
| `--llm-api-key`               | API key                           | —                    |
| `--llm-provider`              | LLM provider                      | `openai`             |
| `--llm-model`                 | Model identifier                  | `gpt-4o-mini`        |
| `--llm-base-url`              | API base URL                      | OpenAI               |
| `--llm-temperature`           | Sampling temperature              | `1`                  |
| `--llm-max-completion-tokens` | Max response tokens               | `512`                |
| `--quantity`                  | Number of suggestions             | `5`                  |
| `--format`                    | Commit message format description | Conventional Commits |
| `--system-prompt`             | Override the system prompt        | —                    |
| `--user-prompt`               | Override the user prompt          | —                    |
| `--config`                    | Explicit config file path         | —                    |

### Environment variables

| Variable              | Description                              |
| --------------------- | ---------------------------------------- |
| `DIFFSCRIBE_API_KEY`  | API key (takes precedence)               |
| `OPENAI_API_KEY`      | API key (fallback)                       |
| `DIFFSCRIBE_STATUS`   | Set to `0` to hide the loading indicator |
| `DIFFSCRIBE_QUANTITY` | Override suggestion count in completions |

### Using other providers

Any OpenAI-compatible API works. Point `--llm-base-url` (or the config equivalent) at your provider:

```yaml
llm:
  provider: openai
  baseUrl: https://api.anthropic.com/v1/chat/completions
  model: claude-sonnet-4-6
```

## Man page

A man page is available after installation:

```sh
man diffscribe
```

Homebrew and MacPorts install it automatically. For other methods, run `make install/man`.

## Development

### Building from source

```sh
make build    # outputs to .out/build/diffscribe
```

### Running tests

```sh
make test               # Go unit tests + coverage
make test/completions   # Bash, Zsh, Fish completion tests
```

### Other useful targets

```sh
make lint       # run golangci-lint
make format     # format code and run go generate
make prep       # format + tidy (pre-commit prep)
make help       # list all available targets
```

## License

[BSD 3-Clause](LICENSE.md)

[ci-image]: https://img.shields.io/github/actions/workflow/status/nickawilliams/diffscribe/release.yaml?logo=GitHub&logoColor=white
[ci-url]: https://github.com/nickawilliams/diffscribe/actions/workflows/release.yaml
[coverage-image]: https://img.shields.io/codecov/c/github/nickawilliams/diffscribe?logo=codecov&logoColor=white
[coverage-url]: https://codecov.io/gh/nickawilliams/diffscribe
