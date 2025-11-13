# --- Variables -------------------------------------------------------------

BINARY := diffscribe
SRC := $(shell find . -name '*.go')

BUILD_DIR := build
OUT_DIR := .out

PREFIX ?= /usr/local/bin
INSTALL_BIN := $(PREFIX)/$(BINARY)

ZSH_DIR := $(HOME)/.zsh
BASH_DIR := $(HOME)/.bash_completion.d
ZSH_SCRIPT_NAME := diffscribe.zsh
ZSH_LIB_NAME := diffscribe.lib.zsh
BASH_SCRIPT_NAME := diffscribe.bash
ZSH_SCRIPT_SRC := contrib/completions/zsh/$(ZSH_SCRIPT_NAME)
ZSH_LIB_SRC := contrib/completions/zsh/$(ZSH_LIB_NAME)
BASH_SCRIPT_SRC := contrib/completions/bash/$(BASH_SCRIPT_NAME)
INSTALL_ZSH := $(ZSH_DIR)/$(ZSH_SCRIPT_NAME)
INSTALL_ZSH_LIB := $(ZSH_DIR)/$(ZSH_LIB_NAME)
INSTALL_BASH := $(BASH_DIR)/$(BASH_SCRIPT_NAME)
INSTALL_BIN_DIR := $(dir $(INSTALL_BIN))
INSTALL_ZSH_DIR := $(dir $(INSTALL_ZSH))
INSTALL_ZSH_LIB_DIR := $(dir $(INSTALL_ZSH_LIB))
INSTALL_BASH_DIR := $(dir $(INSTALL_BASH))
OMZ_CUSTOM ?= $(HOME)/.oh-my-zsh/custom
OMZ_PLUGIN_DIR := $(OMZ_CUSTOM)/plugins/diffscribe
OMZ_PLUGIN_SRC := contrib/oh-my-zsh/diffscribe.plugin.zsh
OMZ_PLUGIN_DEST := $(OMZ_PLUGIN_DIR)/diffscribe.plugin.zsh
OMZ_PLUGIN_LIB := $(OMZ_PLUGIN_DIR)/$(ZSH_LIB_NAME)

# Main Targets
# ============================================================================



.PHONY: default clean build install install/all install/binary \
	install/completions/all install/completions/zsh install/completions/zsh/lib \
	install/completions/bash install/completions/oh-my-zsh \
	link uninstall uninstall/all uninstall/binary uninstall/completions/zsh \
	uninstall/completions/bash uninstall/completions/oh-my-zsh test bench format help vars _print-var

## Build all artifacts
all: build

## Build the executable
build: $(SRC)
	@echo "🔨 Building $(BINARY)..."
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY)
	@echo "✅ Built $(BUILD_DIR)/$(BINARY)"

## Remove all build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(OUT_DIR)

## Run all tests with coverage
test:
	@echo "🧪 Running tests with coverage..."
	@mkdir -p $(OUT_DIR)/coverage
	@go test ./... -coverprofile=$(OUT_DIR)/coverage/coverage.out
	@go tool cover -func=$(OUT_DIR)/coverage/coverage.out | tail -n 1
	@go run github.com/jandelgado/gcov2lcov@v1.1.1 -infile $(OUT_DIR)/coverage/coverage.out -outfile $(OUT_DIR)/coverage/lcov.info >/dev/null
	@go tool cover -html=$(OUT_DIR)/coverage/coverage.out -o $(OUT_DIR)/coverage/index.html
	@echo "📄 Coverage (LCOV): $(OUT_DIR)/coverage/lcov.info"
	@echo "🌐 Coverage (HTML): $(OUT_DIR)/coverage/index.html"

## Run benchmarks for the LLM client
bench:
	@echo "🏎  Running benchmarks..."
	@go test ./internal/llm -bench=BenchmarkGenerateCommitMessages -benchmem

## Format all Go files
format:
	@echo "🎨 Formatting Go files..."
	@gofmt -w $(SRC)

## Install just the binary
install: install/binary

install/all: install/binary install/completions/all

install/binary: build
	@echo "📦 Installing binary → $(INSTALL_BIN)"
	@if [ -w $(PREFIX) ]; then \
		install -Dm755 $(BUILD_DIR)/$(BINARY) $(INSTALL_BIN); \
	else \
		echo "🔐 Elevated permissions required — using sudo"; \
		sudo install -Dm755 $(BUILD_DIR)/$(BINARY) $(INSTALL_BIN); \
	fi
	@echo "✅ Binary installed"

install/completions/all: install/completions/zsh install/completions/bash install/completions/oh-my-zsh

install/completions/zsh: install/completions/zsh/lib
	@echo "📦 Installing Zsh completion assets into $(ZSH_DIR)"
	@mkdir -p $(ZSH_DIR)
	@if [ -f $(ZSH_SCRIPT_SRC) ]; then \
		install -Dm644 $(ZSH_SCRIPT_SRC) $(INSTALL_ZSH); \
	else \
		echo "⚠️  Missing $(ZSH_SCRIPT_SRC); skipping diffscribe.zsh"; \
	fi
	@echo "👉 Source $$HOME/.zsh/$(ZSH_SCRIPT_NAME) from ~/.zshrc"

install/completions/zsh/lib:
	@echo "📦 Installing Zsh shared helpers → $(INSTALL_ZSH_LIB)"
	@mkdir -p $(ZSH_DIR)
	@if [ -f $(ZSH_LIB_SRC) ]; then \
		install -Dm644 $(ZSH_LIB_SRC) $(INSTALL_ZSH_LIB); \
	else \
		echo "⚠️  Missing $(ZSH_LIB_SRC); skipping shared helpers"; \
	fi

install/completions/bash:
	@echo "📦 Installing Bash completion → $(INSTALL_BASH)"
	@mkdir -p $(BASH_DIR)
	@if [ -f $(BASH_SCRIPT_SRC) ]; then \
		install -Dm644 $(BASH_SCRIPT_SRC) $(INSTALL_BASH); \
	else \
		echo "⚠️  Missing $(BASH_SCRIPT_SRC); skipping Bash completion"; \
	fi
	@echo "👉 Add [[ -r $$HOME/.bash_completion.d/$(BASH_SCRIPT_NAME) ]] && . $$HOME/.bash_completion.d/$(BASH_SCRIPT_NAME) to ~/.bashrc"

install/completions/oh-my-zsh: install/completions/zsh/lib
	@if [ -f $(OMZ_PLUGIN_SRC) ]; then \
		echo "📦 Installing Oh-My-Zsh plugin → $(OMZ_PLUGIN_DEST)"; \
		mkdir -p $(OMZ_PLUGIN_DIR); \
		install -Dm644 $(OMZ_PLUGIN_SRC) $(OMZ_PLUGIN_DEST); \
		install -Dm644 $(ZSH_LIB_SRC) $(OMZ_PLUGIN_LIB); \
	else \
		echo "⚠️  Missing $(OMZ_PLUGIN_SRC); skipping Oh-My-Zsh plugin"; \
	fi
	@echo "👉 Add 'diffscribe' to the plugins list in ~/.zshrc"

## Symlink every artifact (binary + all completions) back to the repo
link: build
	@echo "🔗 Linking binary → $(INSTALL_BIN)"
	@src="$(CURDIR)/$(BUILD_DIR)/$(BINARY)"; \
	if [ -w $(INSTALL_BIN_DIR) ]; then \
		install -d $(INSTALL_BIN_DIR); \
		ln -sfn "$$src" $(INSTALL_BIN); \
	else \
		echo "🔐 Elevated permissions required — using sudo"; \
		sudo install -d $(INSTALL_BIN_DIR); \
		sudo ln -sfn "$$src" $(INSTALL_BIN); \
	fi
	@echo "🔗 Linking Zsh shared helpers → $(INSTALL_ZSH_LIB)"
	@install -d $(INSTALL_ZSH_LIB_DIR)
	@ln -sfn "$(CURDIR)/$(ZSH_LIB_SRC)" $(INSTALL_ZSH_LIB)
	@echo "🔗 Linking Zsh completion → $(INSTALL_ZSH)"
	@install -d $(INSTALL_ZSH_DIR)
	@ln -sfn "$(CURDIR)/$(ZSH_SCRIPT_SRC)" $(INSTALL_ZSH)
	@echo "🔗 Linking Bash completion → $(INSTALL_BASH)"
	@install -d $(INSTALL_BASH_DIR)
	@ln -sfn "$(CURDIR)/$(BASH_SCRIPT_SRC)" $(INSTALL_BASH)
	@echo "🔗 Linking Oh-My-Zsh plugin → $(OMZ_PLUGIN_DEST)"
	@install -d $(OMZ_PLUGIN_DIR)
	@ln -sfn "$(CURDIR)/$(OMZ_PLUGIN_SRC)" $(OMZ_PLUGIN_DEST)
	@ln -sfn "$(CURDIR)/$(ZSH_LIB_SRC)" $(OMZ_PLUGIN_LIB)
	@echo "✅ Linked all artifacts (remember to source ~/.zsh/diffscribe.zsh or add 'diffscribe' to OMZ plugins)"

## Remove the installed binary
uninstall: uninstall/binary

uninstall/all: uninstall/binary uninstall/completions/zsh uninstall/completions/bash uninstall/completions/oh-my-zsh

uninstall/binary:
	@echo "🗑️  Removing binary $(INSTALL_BIN)"
	@rm -f $(INSTALL_BIN)

uninstall/completions/zsh:
	@echo "🗑️  Removing Zsh completion assets"
	@rm -f $(INSTALL_ZSH) $(INSTALL_ZSH_LIB)

uninstall/completions/bash:
	@echo "🗑️  Removing Bash completion"
	@rm -f $(INSTALL_BASH)

uninstall/completions/oh-my-zsh:
	@echo "🗑️  Removing Oh-My-Zsh plugin"
	@rm -f $(OMZ_PLUGIN_DEST) $(OMZ_PLUGIN_LIB)

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
