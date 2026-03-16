package llm

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// ValidateAPIKey resolves the configured provider and delegates validation to
// it. Each provider implements its own auth and completions checks.
func ValidateAPIKey(ctx context.Context, cfg Config) error {
	if strings.TrimSpace(cfg.APIKey) == "" {
		return fmt.Errorf("no API key configured")
	}

	provider, err := newProvider(cfg)
	if err != nil {
		return err
	}

	client := &http.Client{Timeout: 10 * time.Second}
	return provider.Validate(ctx, client, cfg)
}
