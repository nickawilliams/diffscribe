package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

func (openAIProvider) Validate(ctx context.Context, client *http.Client, cfg Config) error {
	if err := openAICheckAuth(ctx, client, cfg); err != nil {
		return err
	}
	return openAICheckCompletions(ctx, client, cfg)
}

// openAICheckAuth sends a GET to the models endpoint to verify the API key.
func openAICheckAuth(ctx context.Context, client *http.Client, cfg Config) error {
	modelsURL := openAIDeriveModelsURL(cfg.BaseURL)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, modelsURL, nil)
	if err != nil {
		return fmt.Errorf("failed to build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	switch {
	case resp.StatusCode == http.StatusUnauthorized:
		return fmt.Errorf("invalid API key (HTTP 401)")
	case resp.StatusCode == http.StatusForbidden:
		return fmt.Errorf("API key lacks permission (HTTP 403)")
	case resp.StatusCode >= 400:
		return fmt.Errorf("API returned HTTP %d", resp.StatusCode)
	}
	return nil
}

// openAICheckCompletions sends a minimal completion request to verify the key
// can generate completions (catches quota exhaustion, billing issues, etc).
func openAICheckCompletions(ctx context.Context, client *http.Client, cfg Config) error {
	payload := openAIRequest{
		Model:               cfg.Model,
		Messages:            []openAIMessage{{Role: "user", Content: "hi"}},
		MaxCompletionTokens: 1,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to build request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.BaseURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return openAIParseError(resp.StatusCode, bodyBytes)
	}
	io.Copy(io.Discard, resp.Body)
	return nil
}

// openAIDeriveModelsURL converts a chat completions URL into the corresponding
// models list endpoint. For example:
//
//	https://api.openai.com/v1/chat/completions → https://api.openai.com/v1/models
func openAIDeriveModelsURL(baseURL string) string {
	u := strings.TrimRight(baseURL, "/")
	if before, _, ok := strings.Cut(u, "/v1/"); ok {
		return before + "/v1/models"
	}
	if i := strings.LastIndex(u, "/"); i > len("https://") {
		return u[:i] + "/models"
	}
	return u + "/models"
}

// openAIParseError extracts a readable error from the OpenAI error response
// body, falling back to the HTTP status code if parsing fails.
func openAIParseError(statusCode int, body []byte) error {
	var apiErr struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &apiErr); err == nil && apiErr.Error.Code != "" {
		switch apiErr.Error.Code {
		case "insufficient_quota":
			return fmt.Errorf("quota exceeded (check billing at https://platform.openai.com/settings/organization/billing)")
		default:
			return fmt.Errorf("%s: %s", apiErr.Error.Code, apiErr.Error.Message)
		}
	}
	return fmt.Errorf("completion request failed (HTTP %d)", statusCode)
}

type openAIProvider struct{}

func (openAIProvider) Capabilities() ProviderCapabilities {
	return ProviderCapabilities{
		SupportsJSONSchema:          true,
		SupportsMaxCompletionTokens: true,
	}
}

func (openAIProvider) BuildRequest(ctx context.Context, cfg Config, messages []Message) (*http.Request, error) {
	payload := openAIRequest{
		Model:       cfg.Model,
		Temperature: cfg.Temperature,
		Messages:    make([]openAIMessage, len(messages)),
	}
	for i, msg := range messages {
		payload.Messages[i] = openAIMessage(msg)
	}
	if cfg.MaxCompletionTokens > 0 {
		payload.MaxCompletionTokens = cfg.MaxCompletionTokens
	}
	payload.ResponseFormat = buildResponseFormat(cfg.Quantity)

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.BaseURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")
	return req, nil
}

func (openAIProvider) ParseResponse(resp *http.Response) ([]string, error) {
	if resp.StatusCode >= 300 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("openai: %s: %s", resp.Status, strings.TrimSpace(string(bodyBytes)))
	}

	var parsed openAIResponse
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, err
	}
	if len(parsed.Choices) == 0 {
		return nil, errors.New("openai: empty response")
	}

	content := strings.TrimSpace(parsed.Choices[0].Message.Content)
	return parseSuggestions(content)
}

type openAIRequest struct {
	Model               string                `json:"model"`
	Messages            []openAIMessage       `json:"messages"`
	Temperature         float64               `json:"temperature"`
	MaxCompletionTokens int                   `json:"max_completion_tokens,omitempty"`
	ResponseFormat      *openAIResponseFormat `json:"response_format,omitempty"`
}

type openAIMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

type openAIResponseFormat struct {
	Type       string           `json:"type"`
	JSONSchema openAIJSONSchema `json:"json_schema"`
}

type openAIJSONSchema struct {
	Name   string                 `json:"name"`
	Strict bool                   `json:"strict"`
	Schema openAISchemaDefinition `json:"schema"`
}

type openAISchemaDefinition struct {
	Type                 string                          `json:"type"`
	AdditionalProperties bool                            `json:"additionalProperties"`
	Properties           map[string]openAISchemaProperty `json:"properties"`
	Required             []string                        `json:"required"`
}

type openAISchemaProperty struct {
	Type        string                `json:"type"`
	Description string                `json:"description,omitempty"`
	Items       *openAISchemaProperty `json:"items,omitempty"`
	MinItems    int                   `json:"minItems,omitempty"`
	MaxItems    int                   `json:"maxItems,omitempty"`
}

func buildResponseFormat(quantity int) *openAIResponseFormat {
	if quantity <= 0 {
		quantity = 1
	}
	return &openAIResponseFormat{
		Type: "json_schema",
		JSONSchema: openAIJSONSchema{
			Name:   "commit_suggestions",
			Strict: true,
			Schema: openAISchemaDefinition{
				Type:                 "object",
				AdditionalProperties: false,
				Required:             []string{"suggestions"},
				Properties: map[string]openAISchemaProperty{
					"suggestions": {
						Type:     "array",
						MinItems: 1,
						MaxItems: quantity,
						Items: &openAISchemaProperty{
							Type:        "string",
							Description: "Git commit message suggestion",
						},
					},
				},
			},
		},
	}
}
