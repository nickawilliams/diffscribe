package cmd

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/nickawilliams/diffscribe/internal/llm"
	"github.com/spf13/viper"
)

func TestCapString(t *testing.T) {
	tests := []struct {
		name  string
		input string
		n     int
		want  string
	}{
		{
			name:  "string shorter than limit",
			input: "hello",
			n:     10,
			want:  "hello",
		},
		{
			name:  "string exactly at limit",
			input: "hello",
			n:     5,
			want:  "hello",
		},
		{
			name:  "string longer than limit",
			input: "hello world",
			n:     5,
			want:  "hello\n…",
		},
		{
			name:  "empty string",
			input: "",
			n:     10,
			want:  "",
		},
		{
			name:  "limit of zero",
			input: "hello",
			n:     0,
			want:  "\n…",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := capString(tt.input, tt.n)
			if got != tt.want {
				t.Errorf("capString(%q, %d) = %q, want %q", tt.input, tt.n, got, tt.want)
			}
		})
	}
}

func TestJoinLimit(t *testing.T) {
	tests := []struct {
		name  string
		input []string
		n     int
		want  string
	}{
		{
			name:  "empty slice returns changes",
			input: []string{},
			n:     3,
			want:  "changes",
		},
		{
			name:  "nil slice returns changes",
			input: nil,
			n:     3,
			want:  "changes",
		},
		{
			name:  "single item",
			input: []string{"file.go"},
			n:     3,
			want:  "file.go",
		},
		{
			name:  "items within limit",
			input: []string{"a.go", "b.go", "c.go"},
			n:     3,
			want:  "a.go, b.go, c.go",
		},
		{
			name:  "items exceed limit",
			input: []string{"a.go", "b.go", "c.go", "d.go"},
			n:     3,
			want:  "a.go, b.go, c.go…",
		},
		{
			name:  "items exceed limit by many",
			input: []string{"a", "b", "c", "d", "e", "f"},
			n:     2,
			want:  "a, b…",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := joinLimit(tt.input, tt.n)
			if got != tt.want {
				t.Errorf("joinLimit(%v, %d) = %q, want %q", tt.input, tt.n, got, tt.want)
			}
		})
	}
}

func TestNonEmptyLines(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []string
	}{
		{
			name:  "empty string",
			input: "",
			want:  nil,
		},
		{
			name:  "whitespace only",
			input: "   \n\t\n   ",
			want:  nil,
		},
		{
			name:  "single line",
			input: "hello",
			want:  []string{"hello"},
		},
		{
			name:  "multiple lines",
			input: "line1\nline2\nline3",
			want:  []string{"line1", "line2", "line3"},
		},
		{
			name:  "lines with empty lines between",
			input: "line1\n\nline2\n\n\nline3",
			want:  []string{"line1", "line2", "line3"},
		},
		{
			name:  "lines with whitespace",
			input: "  line1  \n  line2  ",
			want:  []string{"line1", "line2"},
		},
		{
			name:  "trailing newline",
			input: "line1\nline2\n",
			want:  []string{"line1", "line2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := nonEmptyLines(tt.input)
			if len(got) != len(tt.want) {
				t.Errorf("nonEmptyLines(%q) = %v (len %d), want %v (len %d)",
					tt.input, got, len(got), tt.want, len(tt.want))
				return
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("nonEmptyLines(%q)[%d] = %q, want %q",
						tt.input, i, got[i], tt.want[i])
				}
			}
		})
	}
}

func TestRenderTemplate(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		data any
		want string
	}{
		{
			name: "empty template",
			raw:  "",
			data: nil,
			want: "",
		},
		{
			name: "whitespace only template",
			raw:  "   \t\n   ",
			data: nil,
			want: "",
		},
		{
			name: "plain text no variables",
			raw:  "Hello, world!",
			data: nil,
			want: "Hello, world!",
		},
		{
			name: "template with variable",
			raw:  "Hello, {{.Name}}!",
			data: struct{ Name string }{Name: "World"},
			want: "Hello, World!",
		},
		{
			name: "template with multiple variables",
			raw:  "{{.Greeting}}, {{.Name}}!",
			data: struct {
				Greeting string
				Name     string
			}{Greeting: "Hi", Name: "Alice"},
			want: "Hi, Alice!",
		},
		{
			name: "invalid template syntax returns raw",
			raw:  "Hello, {{.Name",
			data: struct{ Name string }{Name: "World"},
			want: "Hello, {{.Name",
		},
		{
			name: "template execution error returns raw",
			raw:  "Hello, {{.Missing}}!",
			data: struct{ Name string }{Name: "World"},
			want: "Hello, {{.Missing}}!",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := renderTemplate(tt.raw, tt.data)
			if got != tt.want {
				t.Errorf("renderTemplate(%q, %v) = %q, want %q", tt.raw, tt.data, got, tt.want)
			}
		})
	}
}

func TestRequireLLMConfig(t *testing.T) {
	tests := []struct {
		name    string
		cfg     llm.Config
		wantErr bool
	}{
		{
			name:    "empty API key returns error",
			cfg:     llm.Config{APIKey: ""},
			wantErr: true,
		},
		{
			name:    "whitespace API key returns error",
			cfg:     llm.Config{APIKey: "   "},
			wantErr: true,
		},
		{
			name:    "valid API key returns nil",
			cfg:     llm.Config{APIKey: "sk-test-key"},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := requireLLMConfig(tt.cfg)
			if (err != nil) != tt.wantErr {
				t.Errorf("requireLLMConfig() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestRun(t *testing.T) {
	tests := []struct {
		name    string
		cmd     string
		args    []string
		wantSub string
	}{
		{
			name:    "simple echo",
			cmd:     "echo",
			args:    []string{"hello"},
			wantSub: "hello",
		},
		{
			name:    "command with multiple args",
			cmd:     "echo",
			args:    []string{"hello", "world"},
			wantSub: "hello world",
		},
		{
			name:    "nonexistent command returns empty",
			cmd:     "nonexistent-command-12345",
			args:    []string{},
			wantSub: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := run(tt.cmd, tt.args...)
			if tt.wantSub != "" && !strings.Contains(got, tt.wantSub) {
				t.Errorf("run(%q, %v) = %q, want substring %q", tt.cmd, tt.args, got, tt.wantSub)
			}
			if tt.wantSub == "" && got != "" {
				t.Errorf("run(%q, %v) = %q, want empty", tt.cmd, tt.args, got)
			}
		})
	}
}

func TestNewLLMConfig(t *testing.T) {
	// Save current viper state and restore after test
	originalViper := viper.AllSettings()
	defer func() {
		viper.Reset()
		for k, v := range originalViper {
			viper.Set(k, v)
		}
	}()

	// Set up test configuration
	viper.Reset()
	viper.Set("llm.api_key", "test-api-key")
	viper.Set("llm.provider", "openai")
	viper.Set("llm.model", "gpt-4")
	viper.Set("llm.base_url", "https://api.openai.com/v1")
	viper.Set("llm.temperature", 0.7)
	viper.Set("quantity", 3)
	viper.Set("llm.max_completion_tokens", 1000)
	viper.Set("system_prompt", "You are a helpful assistant. Model: {{.Model}}")
	viper.Set("user_prompt", "Generate {{.Quantity}} suggestions for {{.Summary}}")

	data := templateData{
		Branch:     "main",
		Paths:      []string{"file.go"},
		Diff:       "diff content",
		FileCount:  1,
		Summary:    "file.go",
		DiffLength: 12,
		Prefix:     "",
		Format:     "conventional",
		Timestamp:  time.Now(),
	}

	cfg := newLLMConfig(data)

	// Verify basic config values
	if cfg.APIKey != "test-api-key" {
		t.Errorf("APIKey = %q, want %q", cfg.APIKey, "test-api-key")
	}
	if cfg.Provider != "openai" {
		t.Errorf("Provider = %q, want %q", cfg.Provider, "openai")
	}
	if cfg.Model != "gpt-4" {
		t.Errorf("Model = %q, want %q", cfg.Model, "gpt-4")
	}
	if cfg.Temperature != 0.7 {
		t.Errorf("Temperature = %f, want %f", cfg.Temperature, 0.7)
	}
	if cfg.Quantity != 3 {
		t.Errorf("Quantity = %d, want %d", cfg.Quantity, 3)
	}
	if cfg.MaxCompletionTokens != 1000 {
		t.Errorf("MaxCompletionTokens = %d, want %d", cfg.MaxCompletionTokens, 1000)
	}

	// Verify template rendering in prompts
	if !strings.Contains(cfg.SystemPrompt, "gpt-4") {
		t.Errorf("SystemPrompt should contain model name, got %q", cfg.SystemPrompt)
	}
	if !strings.Contains(cfg.UserPrompt, "3") {
		t.Errorf("UserPrompt should contain quantity, got %q", cfg.UserPrompt)
	}
	if !strings.Contains(cfg.UserPrompt, "file.go") {
		t.Errorf("UserPrompt should contain summary, got %q", cfg.UserPrompt)
	}
}

func TestGenerateCandidates_EmptyPaths(t *testing.T) {
	ctx := gitContext{
		Branch: "main",
		Paths:  []string{},
		Diff:   "",
	}

	got := generateCandidates(ctx, "")
	if got != nil {
		t.Errorf("generateCandidates with empty paths should return nil, got %v", got)
	}
}

func TestCollectContext(t *testing.T) {
	// Save original runFunc and restore after test
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	// Mock git commands
	runFunc = func(name string, args ...string) string {
		if name != "git" {
			return ""
		}
		if len(args) == 0 {
			return ""
		}
		switch args[0] {
		case "rev-parse":
			return "feature-branch\n"
		case "diff":
			if len(args) >= 2 && args[1] == "--cached" {
				if len(args) >= 3 && args[2] == "--name-only" {
					return "file1.go\nfile2.go\n"
				}
				return "+added line\n-removed line\n"
			}
		}
		return ""
	}

	// Clear any stash env var
	os.Unsetenv("DIFFSCRIBE_STASH_COMMIT")

	ctx, err := collectContext()
	if err != nil {
		t.Fatalf("collectContext() error = %v", err)
	}

	if ctx.Branch != "feature-branch" {
		t.Errorf("Branch = %q, want %q", ctx.Branch, "feature-branch")
	}
	if len(ctx.Paths) != 2 {
		t.Errorf("Paths = %v, want 2 items", ctx.Paths)
	}
	if ctx.Paths[0] != "file1.go" || ctx.Paths[1] != "file2.go" {
		t.Errorf("Paths = %v, want [file1.go, file2.go]", ctx.Paths)
	}
	if !strings.Contains(ctx.Diff, "+added line") {
		t.Errorf("Diff = %q, should contain '+added line'", ctx.Diff)
	}
}

func TestCollectContext_WithStash(t *testing.T) {
	// Save original runFunc and restore after test
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	// Mock git commands for stash context
	// git stash show --include-untracked --name-only <oid>
	// git stash show --include-untracked --patch <oid>
	runFunc = func(name string, args ...string) string {
		if name != "git" {
			return ""
		}
		if len(args) == 0 {
			return ""
		}
		switch args[0] {
		case "rev-parse":
			return "main\n"
		case "stash":
			if len(args) >= 4 && args[3] == "--name-only" {
				return "stashed-file.go\n"
			}
			if len(args) >= 4 && args[3] == "--patch" {
				return "+stash diff content\n"
			}
		}
		return ""
	}

	// Set stash env var
	os.Setenv("DIFFSCRIBE_STASH_COMMIT", "stash@{0}")
	defer os.Unsetenv("DIFFSCRIBE_STASH_COMMIT")

	ctx, err := collectContext()
	if err != nil {
		t.Fatalf("collectContext() error = %v", err)
	}

	if ctx.Branch != "main" {
		t.Errorf("Branch = %q, want %q", ctx.Branch, "main")
	}
	if len(ctx.Paths) != 1 || ctx.Paths[0] != "stashed-file.go" {
		t.Errorf("Paths = %v, want [stashed-file.go]", ctx.Paths)
	}
	if !strings.Contains(ctx.Diff, "+stash diff content") {
		t.Errorf("Diff = %q, should contain '+stash diff content'", ctx.Diff)
	}
}

func TestCollectStashContext(t *testing.T) {
	// Save original runFunc and restore after test
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	// git stash show --include-untracked --name-only <oid>
	// git stash show --include-untracked --patch <oid>
	runFunc = func(name string, args ...string) string {
		if name != "git" {
			return ""
		}
		if len(args) == 0 {
			return ""
		}
		switch args[0] {
		case "rev-parse":
			return "develop\n"
		case "stash":
			if len(args) >= 4 && args[3] == "--name-only" {
				return "a.go\nb.go\nc.go\n"
			}
			if len(args) >= 4 && args[3] == "--patch" {
				return "stash patch content"
			}
		}
		return ""
	}

	ctx := collectStashContext("abc123")

	if ctx.Branch != "develop" {
		t.Errorf("Branch = %q, want %q", ctx.Branch, "develop")
	}
	if len(ctx.Paths) != 3 {
		t.Errorf("Paths = %v, want 3 items", ctx.Paths)
	}
	if ctx.Diff != "stash patch content" {
		t.Errorf("Diff = %q, want %q", ctx.Diff, "stash patch content")
	}
}

func TestGenerateCandidates_WithMockLLM(t *testing.T) {
	// Save original state
	originalRunFunc := runFunc
	originalViper := viper.AllSettings()
	defer func() {
		runFunc = originalRunFunc
		viper.Reset()
		for k, v := range originalViper {
			viper.Set(k, v)
		}
	}()

	// Create mock LLM server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		response := map[string]any{
			"choices": []map[string]any{
				{
					"message": map[string]any{
						"content": `["feat: add new feature", "fix: resolve bug"]`,
					},
				},
			},
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(response)
	}))
	defer server.Close()

	// Configure viper for test
	viper.Reset()
	viper.Set("llm.api_key", "test-key")
	viper.Set("llm.provider", "openai")
	viper.Set("llm.model", "gpt-4")
	viper.Set("llm.base_url", server.URL)
	viper.Set("llm.temperature", 0.7)
	viper.Set("quantity", 2)
	viper.Set("system_prompt", "You are a helpful assistant.")
	viper.Set("user_prompt", "Generate commit messages.")

	ctx := gitContext{
		Branch: "main",
		Paths:  []string{"file.go"},
		Diff:   "+added line",
	}

	got := generateCandidates(ctx, "")

	if len(got) != 2 {
		t.Errorf("generateCandidates() returned %d candidates, want 2", len(got))
	}
	if len(got) >= 1 && got[0] != "feat: add new feature" {
		t.Errorf("got[0] = %q, want %q", got[0], "feat: add new feature")
	}
}

func TestGenerateCandidates_FallsBackToStubs(t *testing.T) {
	// Save original state
	originalViper := viper.AllSettings()
	defer func() {
		viper.Reset()
		for k, v := range originalViper {
			viper.Set(k, v)
		}
	}()

	// Configure viper with missing API key to trigger fallback
	viper.Reset()
	viper.Set("llm.api_key", "")
	viper.Set("llm.provider", "openai")
	viper.Set("llm.model", "gpt-4")

	ctx := gitContext{
		Branch: "main",
		Paths:  []string{"file.go"},
		Diff:   "+added line",
	}

	got := generateCandidates(ctx, "")

	// Should fall back to stub candidates (nil because requireLLMConfig fails)
	if got != nil {
		t.Errorf("generateCandidates() with no API key should return nil, got %v", got)
	}
}

func TestGenerateCandidates_LLMErrorReturnsNil(t *testing.T) {
	// Save original state
	originalViper := viper.AllSettings()
	defer func() {
		viper.Reset()
		for k, v := range originalViper {
			viper.Set(k, v)
		}
	}()

	// Create mock LLM server that returns an error
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error": "server error"}`))
	}))
	defer server.Close()

	// Configure viper for test
	viper.Reset()
	viper.Set("llm.api_key", "test-key")
	viper.Set("llm.provider", "openai")
	viper.Set("llm.model", "gpt-4")
	viper.Set("llm.base_url", server.URL)
	viper.Set("llm.temperature", 0.7)
	viper.Set("quantity", 2)
	viper.Set("system_prompt", "You are a helpful assistant.")
	viper.Set("user_prompt", "Generate commit messages.")

	ctx := gitContext{
		Branch: "main",
		Paths:  []string{"file.go"},
		Diff:   "+added line",
	}

	got := generateCandidates(ctx, "")

	if got != nil {
		t.Errorf("generateCandidates() on LLM error should return nil, got %v", got)
	}
}
