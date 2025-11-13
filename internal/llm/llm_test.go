package llm

import (
	"context"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
)

func TestValidateConfig(t *testing.T) {
	good := Config{
		APIKey:       "k",
		Model:        "m",
		BaseURL:      "http://example.com",
		Temperature:  0.5,
		Quantity:     2,
		SystemPrompt: "system",
	}

	if err := validateConfig(good); err != nil {
		t.Fatalf("expected valid config, got %v", err)
	}

	cases := []struct {
		name string
		cfg  Config
		want string
	}{
		{"missing api key", Config{Model: "m", BaseURL: "x", Quantity: 1, SystemPrompt: "s"}, "api key"},
		{"missing model", Config{APIKey: "k", BaseURL: "x", Quantity: 1, SystemPrompt: "s"}, "model"},
		{"missing base", Config{APIKey: "k", Model: "m", Quantity: 1, SystemPrompt: "s"}, "base URL"},
		{"missing system prompt", Config{APIKey: "k", Model: "m", BaseURL: "x", Quantity: 1}, "system prompt"},
		{"quantity <= 0", Config{APIKey: "k", Model: "m", BaseURL: "x", Quantity: 0, SystemPrompt: "s"}, "quantity"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateConfig(tc.cfg)
			if err == nil || !errors.Is(err, ErrInvalidConfig) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("expected ErrInvalidConfig mentioning %s, got %v", tc.want, err)
			}
		})
	}
}

func TestFallback(t *testing.T) {
	if got := fallback("foo", "bar"); got != "foo" {
		t.Fatalf("expected foo, got %s", got)
	}
	if got := fallback("  \t", "bar"); got != "bar" {
		t.Fatalf("expected bar, got %s", got)
	}
}

func TestParseSuggestions(t *testing.T) {
	jsonResp := `["feat: add docs", "fix: panic"]`
	got, err := parseSuggestions(jsonResp)
	if err != nil || !reflect.DeepEqual(got, []string{"feat: add docs", "fix: panic"}) {
		t.Fatalf("expected parsed array, got %v, err=%v", got, err)
	}

	textResp := "- chore: clean\n- docs: update"
	got, err = parseSuggestions(textResp)
	if err != nil || !reflect.DeepEqual(got, []string{"chore: clean", "docs: update"}) {
		t.Fatalf("expected bullet parsing, got %v, err=%v", got, err)
	}
}

func TestNormalize(t *testing.T) {
	input := []string{"", " feat: add ", "feat: add", "fix: bug"}
	if got := normalize(input); !reflect.DeepEqual(got, []string{"feat: add", "fix: bug"}) {
		t.Fatalf("normalize failed, got %v", got)
	}
}

func TestBuildPrompt(t *testing.T) {
	prompt := buildPrompt(Context{Branch: "main", Paths: []string{"README.md"}, Diff: "diff"}, 3)
	if !strings.Contains(prompt, "Repository branch: main") {
		t.Fatalf("missing branch in prompt: %s", prompt)
	}
	if !strings.Contains(prompt, "Return up to 3 git commit message suggestions") {
		t.Fatalf("missing quantity in prompt: %s", prompt)
	}
}

func TestGenerateCommitMessages_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"[\"feat: add docs\"]"}}]}`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{
		APIKey:       "k",
		Model:        "m",
		BaseURL:      srv.URL,
		Temperature:  1,
		Quantity:     1,
		SystemPrompt: "system",
	}

	got, err := GenerateCommitMessages(context.Background(), Context{}, cfg)
	if err != nil {
		t.Fatalf("expected success, got %v", err)
	}
	if !reflect.DeepEqual(got, []string{"feat: add docs"}) {
		t.Fatalf("unexpected suggestions: %v", got)
	}
}

func TestGenerateCommitMessages_HTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "bad", http.StatusBadRequest)
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{
		APIKey: "k", Model: "m", BaseURL: srv.URL, Temperature: 1, Quantity: 1, SystemPrompt: "s",
	}

	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected error for http failure")
	}
}

func TestGenerateCommitMessages_UserPromptUsed(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"[\"custom\"]"}}]}`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{
		APIKey:       "k",
		Model:        "m",
		BaseURL:      srv.URL,
		Temperature:  1,
		Quantity:     1,
		SystemPrompt: "system",
		UserPrompt:   "prefilled",
	}
	got, err := GenerateCommitMessages(context.Background(), Context{}, cfg)
	if err != nil {
		t.Fatalf("expected success, got %v", err)
	}
	if len(got) != 1 || got[0] != "custom" {
		t.Fatalf("unexpected suggestions: %v", got)
	}
}

func TestGenerateCommitMessages_EmptyChoices(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[]}`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{APIKey: "k", Model: "m", BaseURL: srv.URL, Temperature: 1, Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected error for empty choices")
	}
}

func TestGenerateCommitMessages_ParseError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":""}}]}`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{APIKey: "k", Model: "m", BaseURL: srv.URL, Temperature: 1, Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected parse error")
	}
}

func TestGenerateCommitMessages_JSONDecodeError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{invalid`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{APIKey: "k", Model: "m", BaseURL: srv.URL, Temperature: 1, Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected decode error")
	}
}

func TestGenerateCommitMessages_RequestError(t *testing.T) {
	oldClient := httpClient
	httpClient = &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
		return nil, errors.New("boom")
	})}
	defer func() { httpClient = oldClient }()

	cfg := Config{APIKey: "k", Model: "m", BaseURL: "http://example.com", Temperature: 1, Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected request error")
	}
}

func TestGenerateCommitMessages_MarshalError(t *testing.T) {
	cfg := Config{APIKey: "k", Model: "m", BaseURL: "http://example.com", Temperature: math.NaN(), Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected marshal error due to NaN")
	}
}

func TestGenerateCommitMessages_RequestBuildError(t *testing.T) {
	cfg := Config{APIKey: "k", Model: "m", BaseURL: ":://bad", Temperature: 1, Quantity: 1, SystemPrompt: "s"}
	if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err == nil {
		t.Fatalf("expected request build error")
	}
}

func TestGenerateCommitMessages_InvalidConfig(t *testing.T) {
	if _, err := GenerateCommitMessages(context.Background(), Context{}, Config{}); !errors.Is(err, ErrInvalidConfig) {
		t.Fatalf("expected invalid config error, got %v", err)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}
func BenchmarkGenerateCommitMessages(b *testing.B) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"[\"feat: bench\"]"}}]}`))
	}))
	defer srv.Close()

	oldClient := httpClient
	httpClient = srv.Client()
	defer func() { httpClient = oldClient }()

	cfg := Config{APIKey: "k", Model: "m", BaseURL: srv.URL, Temperature: 1, Quantity: 1, SystemPrompt: "s"}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := GenerateCommitMessages(context.Background(), Context{}, cfg); err != nil {
			b.Fatalf("unexpected error: %v", err)
		}
	}
}
