package llm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Context carries the git information we send to the LLM.
type Context struct {
	Branch string
	Paths  []string
	Diff   string
}

// Config controls how we call the OpenAI API.
type Config struct {
	APIKey              string
	Provider            string
	Model               string
	BaseURL             string
	Temperature         float64
	Quantity            int
	MaxCompletionTokens int
	SystemPrompt        string
	UserPrompt          string
}

var httpClient = &http.Client{Timeout: 25 * time.Second}

var ErrInvalidConfig = errors.New("llm: invalid config")

// GenerateCommitMessages calls OpenAI and returns the suggested commit messages.
func GenerateCommitMessages(ctx context.Context, data Context, cfg Config) ([]string, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	provider, err := newProvider(cfg)
	if err != nil {
		return nil, err
	}
	prompt := cfg.UserPrompt
	if strings.TrimSpace(prompt) == "" {
		prompt = buildPrompt(data, cfg.Quantity)
	}

	messages := []Message{
		{Role: "system", Content: cfg.SystemPrompt},
		{Role: "user", Content: prompt},
	}

	req, err := provider.BuildRequest(ctx, cfg, messages)
	if err != nil {
		return nil, err
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	return provider.ParseResponse(resp)
}

func buildPrompt(data Context, max int) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Repository branch: %s\n", fallback(data.Branch, "unknown"))
	fmt.Fprintf(&b, "Changed files (%d max shown):\n", len(data.Paths))
	for _, p := range data.Paths {
		fmt.Fprintf(&b, "- %s\n", p)
	}
	b.WriteString("\nDiff (truncated when necessary):\n")
	b.WriteString(data.Diff)
	b.WriteString("\n\nReturn up to ")
	fmt.Fprintf(&b, "%d", max)
	b.WriteString(" git commit message suggestions.\n")
	b.WriteString("Respond with a JSON array of strings (no markdown, no prose).")
	return b.String()
}

func fallback(v, alt string) string {
	if strings.TrimSpace(v) == "" {
		return alt
	}
	return v
}

func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.APIKey) == "" {
		return fmt.Errorf("%w: api key is required", ErrInvalidConfig)
	}
	if strings.TrimSpace(cfg.Provider) == "" {
		return fmt.Errorf("%w: provider is required", ErrInvalidConfig)
	}
	if strings.TrimSpace(cfg.Model) == "" {
		return fmt.Errorf("%w: model identifier is required", ErrInvalidConfig)
	}
	if strings.TrimSpace(cfg.BaseURL) == "" {
		return fmt.Errorf("%w: base URL is required", ErrInvalidConfig)
	}
	if strings.TrimSpace(cfg.SystemPrompt) == "" {
		return fmt.Errorf("%w: system prompt is required", ErrInvalidConfig)
	}
	if cfg.Quantity <= 0 {
		return fmt.Errorf("%w: quantity must be greater than zero", ErrInvalidConfig)
	}
	if cfg.MaxCompletionTokens < 0 {
		return fmt.Errorf("%w: max completion tokens cannot be negative", ErrInvalidConfig)
	}
	return nil
}

func parseSuggestions(content string) ([]string, error) {
	content = strings.TrimSpace(content)
	if content == "" {
		return nil, errors.New("openai: empty response")
	}

	var obj struct {
		Suggestions []string `json:"suggestions"`
	}
	if err := json.Unmarshal([]byte(content), &obj); err == nil && len(obj.Suggestions) > 0 {
		return normalize(obj.Suggestions), nil
	}

	var arr []string
	if err := json.Unmarshal([]byte(content), &arr); err == nil {
		return normalize(arr), nil
	}

	lines := strings.Split(content, "\n")
	arr = nil
	for _, line := range lines {
		line = strings.TrimSpace(strings.TrimLeft(line, "-*•"))
		if line != "" {
			arr = append(arr, line)
		}
	}
	if len(arr) == 0 {
		return nil, errors.New("openai: unable to parse response")
	}
	return normalize(arr), nil
}

func normalize(in []string) []string {
	seen := make(map[string]struct{})
	var out []string
	for _, item := range in {
		cleaned := strings.TrimSpace(item)
		if cleaned == "" {
			continue
		}
		if _, ok := seen[cleaned]; ok {
			continue
		}
		seen[cleaned] = struct{}{}
		out = append(out, cleaned)
	}
	return out
}
