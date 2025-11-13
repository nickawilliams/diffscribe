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

type openAIProvider struct{}

func (openAIProvider) Capabilities() ProviderCapabilities {
	return ProviderCapabilities{
		SupportsJSONSchema:          false,
		SupportsMaxCompletionTokens: false,
	}
}

func (openAIProvider) BuildRequest(ctx context.Context, cfg Config, messages []Message) (*http.Request, error) {
	payload := openAIRequest{
		Model:       cfg.Model,
		Temperature: cfg.Temperature,
		Messages:    make([]openAIMessage, len(messages)),
	}
	for i, msg := range messages {
		payload.Messages[i] = openAIMessage{Role: msg.Role, Content: msg.Content}
	}

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
	Model       string          `json:"model"`
	Messages    []openAIMessage `json:"messages"`
	Temperature float64         `json:"temperature"`
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
