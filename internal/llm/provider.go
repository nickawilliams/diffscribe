package llm

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

// Message represents a role/content pair sent to a provider.
type Message struct {
	Role    string
	Content string
}

// ProviderCapabilities describe optional features a provider supports.
type ProviderCapabilities struct {
	SupportsJSONSchema          bool
	SupportsMaxCompletionTokens bool
}

// Provider represents a backend capable of generating commit suggestions.
type Provider interface {
	Capabilities() ProviderCapabilities
	BuildRequest(ctx context.Context, cfg Config, messages []Message) (*http.Request, error)
	ParseResponse(resp *http.Response) ([]string, error)
}

func newProvider(cfg Config) (Provider, error) {
	name := strings.TrimSpace(strings.ToLower(cfg.Provider))
	if name == "" {
		name = "openai"
	}

	switch name {
	case "openai":
		return openAIProvider{}, nil
	default:
		return nil, fmt.Errorf("llm: unsupported provider %q", cfg.Provider)
	}
}
