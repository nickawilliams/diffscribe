SHELL := /usr/bin/env bash

# Project metadata (read from project.yaml)
PROJECT_YAML := project.yaml
BINARY := $(shell yq -r '.binary' $(PROJECT_YAML))
PKG_DESCRIPTION := $(shell yq -r '.description' $(PROJECT_YAML))
PKG_HOMEPAGE := $(shell yq -r '.homepage' $(PROJECT_YAML))
PKG_LICENSE := $(shell yq -r '.license' $(PROJECT_YAML))
PKG_MAINTAINER_NAME := $(shell yq -r '.maintainer.name' $(PROJECT_YAML))
PKG_MAINTAINER_EMAIL := $(shell yq -r '.maintainer.email' $(PROJECT_YAML))

SRC := $(shell find . -name '*.go')
TAP_REPO ?= nickawilliams/homebrew-tap
TAP_FORMULA_PATH := Formula/diffscribe.rb
TAP_FORMULA := packaging/homebrew/diffscribe.rb

PORT_REPO ?= nickawilliams/fork-macports-ports
PORT_PULLREQUEST ?= false
PORTFILE_PATH := devel/diffscribe/Portfile
PORTFILE := packaging/macports/Portfile

OUT_DIR := .out
BUILD_BIN := $(OUT_DIR)/build/$(BINARY)

export CARGO_HOME ?= $(CURDIR)/.cache/cargo

GO ?= go
GIT_CLIFF ?= git-cliff
VERSION_PKG := github.com/nickawilliams/diffscribe/internal/version
GIT_TAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
EXACT_TAG := $(shell git describe --tags --exact-match 2>/dev/null)
VERSION ?= $(if $(EXACT_TAG),$(EXACT_TAG),$(GIT_TAG)-dev.$(GIT_SHA))
LDFLAGS := -s -w -X $(VERSION_PKG).version=$(VERSION)

RELEASE_BUMP_TYPE ?= patch
RELEASE_COMMIT_FLAG := $(OUT_DIR)/release_committed

PREFIX ?= /usr/local/bin
PREFIX_ROOT := $(patsubst %/,%,$(dir $(PREFIX)))
INSTALL_BIN := $(PREFIX)/$(BINARY)
MANPREFIX ?= $(PREFIX_ROOT)/share/man
MANDIR := $(MANPREFIX)/man1
MANPAGE := diffscribe.1
MANPAGE_SRC := contrib/man/$(MANPAGE)
INSTALL_MAN := $(MANDIR)/$(MANPAGE)

# Completion install locations
ZSH_DIR := $(HOME)/.zsh
BASH_DIR := $(HOME)/.bash_completion.d
FISH_DIR := $(HOME)/.config/fish/completions

ZSH_SCRIPT_NAME := diffscribe.zsh
BASH_SCRIPT_NAME := diffscribe.bash
FISH_SCRIPT_NAME := diffscribe.fish

ZSH_SCRIPT_SRC := contrib/completions/zsh/$(ZSH_SCRIPT_NAME)
BASH_SCRIPT_SRC := contrib/completions/bash/$(BASH_SCRIPT_NAME)
FISH_SCRIPT_SRC := contrib/completions/fish/$(FISH_SCRIPT_NAME)

INSTALL_ZSH := $(ZSH_DIR)/$(ZSH_SCRIPT_NAME)
INSTALL_BASH := $(BASH_DIR)/$(BASH_SCRIPT_NAME)
INSTALL_FISH := $(FISH_DIR)/$(FISH_SCRIPT_NAME)

INSTALL_BIN_DIR := $(dir $(INSTALL_BIN))
INSTALL_ZSH_DIR := $(dir $(INSTALL_ZSH))
INSTALL_BASH_DIR := $(dir $(INSTALL_BASH))
INSTALL_FISH_DIR := $(dir $(INSTALL_FISH))
OMZ_CUSTOM ?= $(HOME)/.oh-my-zsh/custom
OMZ_PLUGIN_DIR := $(OMZ_CUSTOM)/plugins/diffscribe
OMZ_PLUGIN_SRC := $(ZSH_SCRIPT_SRC)
OMZ_PLUGIN_DEST := $(OMZ_PLUGIN_DIR)/diffscribe.plugin.zsh

# Main Targets
# ============================================================================

.PHONY: default clean build dist release install install/all install/binary \
		install/completions/all install/completions/zsh \
		install/completions/bash install/completions/fish install/completions/oh-my-zsh \
		install/man man link uninstall uninstall/all uninstall/binary uninstall/completions/zsh \
		uninstall/completions/bash uninstall/completions/fish uninstall/completions/oh-my-zsh \
		uninstall/man \
		deps changelog releasenotes version version/bump_type version/github_actions release/commit release/tag test test/completions test/completions/bash test/completions/zsh \
		test/completions/fish bench lint format help vars _print-var publish/homebrew publish/macports

## Build all artifacts
all: build

## Build the executable
build: $(SRC)
	@echo "Building $(BINARY)..."
	@mkdir -p $(dir $(BUILD_BIN))
	@go build -ldflags "$(LDFLAGS)" -o $(BUILD_BIN)
	@echo "Built $(BUILD_BIN)"

dist:
	@echo "Building release artifacts via GoReleaser..."
	@notes="$$($(MAKE) --no-print-directory releasenotes)"; \
	GIT_CLIFF_RELEASE_NOTES="$$notes" \
	PKG_BINARY="$(BINARY)" \
	PKG_DESCRIPTION="$(PKG_DESCRIPTION)" \
	PKG_HOMEPAGE="$(PKG_HOMEPAGE)" \
	PKG_LICENSE="$(PKG_LICENSE)" \
	PKG_MAINTAINER_NAME="$(PKG_MAINTAINER_NAME)" \
	PKG_MAINTAINER_EMAIL="$(PKG_MAINTAINER_EMAIL)" \
		$(GO) tool goreleaser release --snapshot --clean

release:
	@echo "Building release artifacts via GoReleaser..."
	@notes="$$($(MAKE) --no-print-directory releasenotes)"; \
	GIT_CLIFF_RELEASE_NOTES="$$notes" \
	PKG_BINARY="$(BINARY)" \
	PKG_DESCRIPTION="$(PKG_DESCRIPTION)" \
	PKG_HOMEPAGE="$(PKG_HOMEPAGE)" \
	PKG_LICENSE="$(PKG_LICENSE)" \
	PKG_MAINTAINER_NAME="$(PKG_MAINTAINER_NAME)" \
	PKG_MAINTAINER_EMAIL="$(PKG_MAINTAINER_EMAIL)" \
		$(GO) tool goreleaser release --clean

## Render and publish the MacPorts Portfile to the ports repository
publish/macports:
	@PORT_PULLREQUEST="$(PORT_PULLREQUEST)" ./scripts/publish_macports.sh "$(TAG)" "$(PORT_REPO)" "$(PORTFILE_PATH)" "$(PORTFILE)"

## Render and publish the Homebrew formula to the tap repository
publish/homebrew:
	@./scripts/publish_homebrew.sh "$(TAG)" "$(TAP_REPO)" "$(TAP_FORMULA_PATH)" "$(TAP_FORMULA)"

## Install Go module and tooling dependencies
deps:
	@if ! command -v $(GIT_CLIFF) >/dev/null 2>&1; then \
		echo "Installing git-cliff (requires cargo)..."; \
		if command -v cargo >/dev/null 2>&1; then \
			cargo install git-cliff >/dev/null 2>&1 || { echo "WARN: Failed to install git-cliff via cargo"; exit 1; }; \
		else \
			echo "WARN: cargo not found — install git-cliff manually from https://github.com/orhun/git-cliff"; \
		fi; \
	else \
		echo "INFO: git-cliff already installed ($$(command -v $(GIT_CLIFF)))"; \
	fi
	@echo "Downloading Go module dependencies..."
	@$(GO) mod download

man:
	@echo "Generating man page..."
	@MAN_OUT_DIR=$(dir $(MANPAGE_SRC)) go run ./tools/gen-man

## Generate CHANGELOG.md from conventional commits
changelog:
	@if ! command -v $(GIT_CLIFF) >/dev/null 2>&1; then \
		echo "ERROR: git-cliff not found. Run 'make deps' or install git-cliff manually."; \
		exit 1; \
	fi
	@echo "Generating CHANGELOG.md via git-cliff..."
	@if [ -n "$(CHANGELOG_VERSION)" ]; then \
		$(GIT_CLIFF) --config cliff.toml --tag "$(CHANGELOG_VERSION)" --output CHANGELOG.md; \
	else \
		$(GIT_CLIFF) --config cliff.toml --output CHANGELOG.md; \
	fi

## Print the release notes snippet used by GoReleaser
releasenotes:
	@if [ ! -x "$(CURDIR)/scripts/releasenotes.sh" ]; then \
		echo "ERROR: Missing $(CURDIR)/scripts/releasenotes.sh" >&2; \
		exit 1; \
	fi
	@"$(CURDIR)/scripts/releasenotes.sh"

## Print the next semantic version derived from conventional commits
version:
	@if ! command -v $(GIT_CLIFF) >/dev/null 2>&1; then \
		echo "ERROR: git-cliff not found. Run 'make deps' or install git-cliff manually." >&2; \
		exit 1; \
	fi
	@next_version=$$($(GIT_CLIFF) --config cliff.toml --bumped-version 2>/dev/null); \
	if [ -z "$$next_version" ]; then \
		echo "ERROR: Unable to determine next version" >&2; \
		exit 1; \
	fi; \
	echo "$$next_version"

## Determine whether the upcoming version is a major/minor/patch bump
version/bump_type:
	@current=$$($(MAKE) --no-print-directory version); \
	prev_tag=$$(git describe --tags --abbrev=0 HEAD 2>/dev/null || echo v0.0.0); \
	clean_prev=$${prev_tag#v}; \
	clean_curr=$${current#v}; \
	prev_major=$$(printf '%s' "$$clean_prev" | cut -d. -f1); \
	prev_minor=$$(printf '%s' "$$clean_prev" | cut -d. -f2); \
	prev_patch=$$(printf '%s' "$$clean_prev" | cut -d. -f3); \
	curr_major=$$(printf '%s' "$$clean_curr" | cut -d. -f1); \
	curr_minor=$$(printf '%s' "$$clean_curr" | cut -d. -f2); \
	curr_patch=$$(printf '%s' "$$clean_curr" | cut -d. -f3); \
	prev_major=$${prev_major:-0}; prev_minor=$${prev_minor:-0}; prev_patch=$${prev_patch:-0}; \
	curr_major=$${curr_major:-0}; curr_minor=$${curr_minor:-0}; curr_patch=$${curr_patch:-0}; \
	bump=patch; \
	if [ "$$curr_major" != "$$prev_major" ]; then \
		bump=major; \
	elif [ "$$curr_minor" != "$$prev_minor" ]; then \
		bump=minor; \
	elif [ "$$curr_patch" != "$$prev_patch" ]; then \
		bump=patch; \
	fi; \
	echo "$$bump"

version/github_actions:
	@output_file="$$GITHUB_OUTPUT"; \
	if [ -z "$$output_file" ]; then \
		echo "ERROR: GITHUB_OUTPUT is not set" >&2; \
		exit 1; \
	fi; \
	set -euo pipefail; \
	version=$$($(MAKE) --no-print-directory version); \
	bump=$$($(MAKE) --no-print-directory version/bump_type); \
	echo "next_version=$$version" >> "$$output_file"; \
	echo "bump_type=$$bump" >> "$$output_file"

## Commit release artifacts (CHANGELOG, manpage, etc.)
release/commit:
	@if [ -z "$(RELEASE_VERSION)" ]; then \
		echo "ERROR: RELEASE_VERSION is required" >&2; \
		exit 1; \
	fi
	@if [ -z "$(RELEASE_BUMP_TYPE)" ]; then \
		echo "ERROR: RELEASE_BUMP_TYPE is required" >&2; \
		exit 1; \
	fi
	@mkdir -p $(dir $(RELEASE_COMMIT_FLAG))
	@rm -f $(RELEASE_COMMIT_FLAG)
	git add -A; \
	if git diff --cached --quiet; then \
		echo "INFO: No release changes to commit"; \
	else \
		git commit -m "release($(RELEASE_BUMP_TYPE)): $(RELEASE_VERSION)"; \
		echo "true" > $(RELEASE_COMMIT_FLAG); \
	fi

## Tag the release
release/tag:
	@if [ -z "$(RELEASE_VERSION)" ]; then \
		echo "ERROR: RELEASE_VERSION is required" >&2; \
		exit 1; \
	fi
	@if git rev-parse "$(RELEASE_VERSION)" >/dev/null 2>&1; then \
		echo "INFO: Tag $(RELEASE_VERSION) already exists"; \
		git tag -d "$(RELEASE_VERSION)" >/dev/null 2>&1 || true; \
	fi
	@git tag -a "$(RELEASE_VERSION)" -m "Release $(RELEASE_VERSION)"

## Remove all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(OUT_DIR)

## Run all tests with coverage
test:
	@echo "Running tests with coverage..."
	@mkdir -p $(OUT_DIR)/coverage
	@go test ./... -coverpkg=./cmd/...,./internal/... -coverprofile=$(OUT_DIR)/coverage/coverage.out
	@go tool cover -func=$(OUT_DIR)/coverage/coverage.out | tail -n 1
	@$(GO) tool gcov2lcov -infile $(OUT_DIR)/coverage/coverage.out -outfile $(OUT_DIR)/coverage/lcov.info >/dev/null
	@go tool cover -html=$(OUT_DIR)/coverage/coverage.out -o $(OUT_DIR)/coverage/index.html
	@echo "Coverage (LCOV): $(OUT_DIR)/coverage/lcov.info"
	@echo "Coverage (HTML): $(OUT_DIR)/coverage/index.html"

## Run all completion hook tests
test/completions: test/completions/bash test/completions/zsh test/completions/fish

## Run Bash completion tests
test/completions/bash:
	@bash contrib/completions/bash/diffscribe.test.bash

## Run Zsh completion tests
test/completions/zsh:
	@zsh contrib/completions/zsh/diffscribe.test.zsh

## Run Fish completion tests
test/completions/fish:
	@fish contrib/completions/fish/diffscribe.test.fish

## Run benchmarks for the LLM client
bench:
	@echo "Running benchmarks..."
	@go test ./internal/llm -bench=BenchmarkGenerateCommitMessages -benchmem

## Run golangci-lint
lint:
	@echo "Running golangci-lint..."
	@$(GO) tool golangci-lint run

## Prepare the codebase for a new commit
prep: format
		@echo "Tidying go.mod/go.sum..."
		@go mod tidy

## Format all Go files
format:
		@echo "Formatting Go files..."
		@gofmt -w $(SRC)
		@echo "Regenerating code..."
		@go generate ./...

## Install just the binary
install: install/binary

install/all: install/binary install/completions/all install/man

install/binary: build
	@echo "Installing binary -> $(INSTALL_BIN)"
	@if install -d $(INSTALL_BIN_DIR) >/dev/null 2>&1; then \
		install -m755 $(BUILD_BIN) $(INSTALL_BIN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo install -d $(INSTALL_BIN_DIR); \
		sudo install -m755 $(BUILD_BIN) $(INSTALL_BIN); \
	fi
	@echo "Binary installed"

install/completions/all: install/completions/zsh install/completions/bash install/completions/fish install/completions/oh-my-zsh

install/completions/zsh:
	@echo "Installing Zsh completion assets into $(ZSH_DIR)"
	@mkdir -p $(ZSH_DIR)
	@if [ -f $(ZSH_SCRIPT_SRC) ]; then \
		install -m644 $(ZSH_SCRIPT_SRC) $(INSTALL_ZSH); \
	else \
		echo "WARN: Missing $(ZSH_SCRIPT_SRC); skipping diffscribe.zsh"; \
	fi
	@echo "NOTE: Source $$HOME/.zsh/$(ZSH_SCRIPT_NAME) from ~/.zshrc"

install/completions/bash:
	@echo "Installing Bash completion -> $(INSTALL_BASH)"
	@mkdir -p $(BASH_DIR)
	@if [ -f $(BASH_SCRIPT_SRC) ]; then \
		install -m644 $(BASH_SCRIPT_SRC) $(INSTALL_BASH); \
	else \
		echo "WARN: Missing $(BASH_SCRIPT_SRC); skipping Bash completion"; \
	fi
	@echo "NOTE: Add [[ -r $$HOME/.bash_completion.d/$(BASH_SCRIPT_NAME) ]] && . $$HOME/.bash_completion.d/$(BASH_SCRIPT_NAME) to ~/.bashrc"

install/completions/fish:
	@echo "Installing Fish completion -> $(INSTALL_FISH)"
	@mkdir -p $(FISH_DIR)
	@if [ -f $(FISH_SCRIPT_SRC) ]; then \
		install -m644 $(FISH_SCRIPT_SRC) $(INSTALL_FISH); \
	else \
		echo "WARN: Missing $(FISH_SCRIPT_SRC); skipping Fish completion"; \
	fi
	@echo "NOTE: Fish auto-loads $$HOME/.config/fish/completions/$(FISH_SCRIPT_NAME)"

install/completions/oh-my-zsh:
	@if [ -f $(OMZ_PLUGIN_SRC) ]; then \
		echo "Installing Oh-My-Zsh plugin -> $(OMZ_PLUGIN_DEST)"; \
		mkdir -p $(OMZ_PLUGIN_DIR); \
		install -m644 $(OMZ_PLUGIN_SRC) $(OMZ_PLUGIN_DEST); \
	else \
		echo "WARN: Missing $(OMZ_PLUGIN_SRC); skipping Oh-My-Zsh plugin"; \
	fi
	@echo "NOTE: Add 'diffscribe' to the plugins list in ~/.zshrc"

install/man: man
	@echo "Installing man page -> $(INSTALL_MAN)"
	@if install -d $(MANDIR) >/dev/null 2>&1; then \
		install -m644 $(MANPAGE_SRC) $(INSTALL_MAN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo install -d $(MANDIR); \
		sudo install -m644 $(MANPAGE_SRC) $(INSTALL_MAN); \
	fi
	@echo "NOTE: View it via 'man diffscribe'"

## Symlink every artifact (binary + all completions) back to the repo
link: build man
	@echo "Linking binary -> $(INSTALL_BIN)"
	@src="$(CURDIR)/$(BUILD_BIN)"; \
	if [ -w $(INSTALL_BIN_DIR) ]; then \
		install -d $(INSTALL_BIN_DIR); \
		ln -sfn "$$src" $(INSTALL_BIN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo install -d $(INSTALL_BIN_DIR); \
		sudo ln -sfn "$$src" $(INSTALL_BIN); \
	fi
	@echo "Linking Zsh completion -> $(INSTALL_ZSH)"
	@install -d $(INSTALL_ZSH_DIR)
	@ln -sfn "$(CURDIR)/$(ZSH_SCRIPT_SRC)" $(INSTALL_ZSH)
	@echo "Linking Bash completion -> $(INSTALL_BASH)"
	@install -d $(INSTALL_BASH_DIR)
	@ln -sfn "$(CURDIR)/$(BASH_SCRIPT_SRC)" $(INSTALL_BASH)
	@echo "Linking Fish completion -> $(INSTALL_FISH)"
	@install -d $(INSTALL_FISH_DIR)
	@ln -sfn "$(CURDIR)/$(FISH_SCRIPT_SRC)" $(INSTALL_FISH)
	@echo "Linking Oh-My-Zsh plugin -> $(OMZ_PLUGIN_DEST)"
	@install -d $(OMZ_PLUGIN_DIR)
	@ln -sfn "$(CURDIR)/$(ZSH_SCRIPT_SRC)" $(OMZ_PLUGIN_DEST)
	@echo "Linking man page -> $(INSTALL_MAN)"
	@mandir=$(MANDIR); \
	if [ -w "$$mandir" ]; then \
		install -d "$$mandir"; \
		ln -sfn "$(CURDIR)/$(MANPAGE_SRC)" $(INSTALL_MAN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo install -d "$$mandir"; \
		sudo ln -sfn "$(CURDIR)/$(MANPAGE_SRC)" $(INSTALL_MAN); \
	fi
	@echo "Linked all artifacts (remember to source ~/.zsh/diffscribe.zsh or add 'diffscribe' to OMZ plugins)"

## Remove the installed binary
uninstall: uninstall/binary

uninstall/all: uninstall/binary uninstall/completions/zsh uninstall/completions/bash uninstall/completions/fish uninstall/completions/oh-my-zsh uninstall/man

uninstall/binary:
	@echo "Removing binary $(INSTALL_BIN)"
	@if [ -w $(INSTALL_BIN_DIR) ]; then \
		rm -f $(INSTALL_BIN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(INSTALL_BIN); \
	fi

uninstall/completions/zsh:
	@echo "Removing Zsh completion assets"
	@if [ -w $(INSTALL_ZSH_DIR) ]; then \
		rm -f $(INSTALL_ZSH); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(INSTALL_ZSH); \
	fi

uninstall/completions/bash:
	@echo "Removing Bash completion"
	@if [ -w $(INSTALL_BASH_DIR) ]; then \
		rm -f $(INSTALL_BASH); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(INSTALL_BASH); \
	fi

uninstall/completions/fish:
	@echo "Removing Fish completion"
	@if [ -w $(INSTALL_FISH_DIR) ]; then \
		rm -f $(INSTALL_FISH); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(INSTALL_FISH); \
	fi

uninstall/completions/oh-my-zsh:
	@echo "Removing Oh-My-Zsh plugin"
	@if [ -w $(OMZ_PLUGIN_DIR) ]; then \
		rm -f $(OMZ_PLUGIN_DEST); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(OMZ_PLUGIN_DEST); \
	fi

uninstall/man:
	@echo "Removing man page $(INSTALL_MAN)"
	@if [ -w $(MANDIR) ]; then \
		rm -f $(INSTALL_MAN); \
	else \
		echo "Elevated permissions required — using sudo"; \
		sudo rm -f $(INSTALL_MAN); \
	fi

# Utils
# ============================================================================

## This help screen
help:
	@printf "Available targets:\n\n"
	@awk '/^[a-zA-Z\-\_0-9%:\\]+/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			gsub("\\\\", "", helpCommand); \
			gsub(":+$$", "", helpCommand); \
			printf "  \x1b[32;01m%-35s\x1b[0m %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST) | sort -u
	@printf "\n"

## Show the variables used in the Makefile and their values
vars:
	@printf "Variable values:\n\n"
	@awk 'BEGIN { FS = "[:?]?="; } /^[A-Za-z0-9_]+[[:space:]]*[:?]?=/ { \
		if ($$0 ~ /\?=/) operator = "?="; \
		else if ($$0 ~ /:=/) operator = ":="; \
		else operator = "="; \
		print $$1, operator; \
	}' $(MAKEFILE_LIST) | \
	while read var op; do \
		value=$$(make --no-print-directory -f $(MAKEFILE_LIST) _print-var VAR=$$var); \
		printf "  \x1b[32;01m%-35s\x1b[0m%2s \x1b[34;01m%s\x1b[0m\n" "$$var" "$$op" "$$value"; \
	done
	@printf "\n"

_print-var:
	@echo $($(VAR))
