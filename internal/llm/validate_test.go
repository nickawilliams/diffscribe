package llm

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDeriveModelsURL(t *testing.T) {
	tests := []struct {
		name    string
		baseURL string
		want    string
	}{
		{"openai default", "https://api.openai.com/v1/chat/completions", "https://api.openai.com/v1/models"},
		{"trailing slash", "https://api.openai.com/v1/chat/completions/", "https://api.openai.com/v1/models"},
		{"custom host with v1", "https://my-proxy.example.com/v1/chat/completions", "https://my-proxy.example.com/v1/models"},
		{"no v1 segment", "https://example.com/api/chat", "https://example.com/api/models"},
		{"bare host", "https://example.com", "https://example.com/models"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := openAIDeriveModelsURL(tt.baseURL); got != tt.want {
				t.Errorf("openAIDeriveModelsURL(%q) = %q, want %q", tt.baseURL, got, tt.want)
			}
		})
	}
}

func TestValidateAPIKey(t *testing.T) {
	tests := []struct {
		name       string
		handler    http.HandlerFunc
		apiKey     string
		wantErr    bool
		errContain string
	}{
		{
			name: "valid key",
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
			},
			apiKey:  "sk-test",
			wantErr: false,
		},
		{
			name: "unauthorized on models",
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusUnauthorized)
			},
			apiKey:     "sk-bad",
			wantErr:    true,
			errContain: "invalid API key",
		},
		{
			name: "forbidden on models",
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusForbidden)
			},
			apiKey:     "sk-nope",
			wantErr:    true,
			errContain: "lacks permission",
		},
		{
			name: "server error on models",
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusInternalServerError)
			},
			apiKey:     "sk-test",
			wantErr:    true,
			errContain: "HTTP 500",
		},
		{
			name:       "empty key",
			handler:    nil,
			apiKey:     "",
			wantErr:    true,
			errContain: "no API key",
		},
		{
			name: "quota exceeded on completion",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if strings.HasSuffix(r.URL.Path, "/models") {
					w.WriteHeader(http.StatusOK)
					return
				}
				w.WriteHeader(http.StatusTooManyRequests)
				fmt.Fprint(w, `{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}`)
			},
			apiKey:     "sk-test",
			wantErr:    true,
			errContain: "quota exceeded",
		},
		{
			name: "other completion error",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if strings.HasSuffix(r.URL.Path, "/models") {
					w.WriteHeader(http.StatusOK)
					return
				}
				w.WriteHeader(http.StatusBadRequest)
				fmt.Fprint(w, `{"error":{"code":"invalid_model","message":"model not found"}}`)
			},
			apiKey:     "sk-test",
			wantErr:    true,
			errContain: "invalid_model",
		},
		{
			name: "completion error with unparseable body",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if strings.HasSuffix(r.URL.Path, "/models") {
					w.WriteHeader(http.StatusOK)
					return
				}
				w.WriteHeader(http.StatusBadRequest)
				fmt.Fprint(w, "not json")
			},
			apiKey:     "sk-test",
			wantErr:    true,
			errContain: "HTTP 400",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var srv *httptest.Server
			if tt.handler != nil {
				srv = httptest.NewServer(tt.handler)
				defer srv.Close()
			}

			cfg := Config{APIKey: tt.apiKey, Model: "gpt-4o-mini"}
			if srv != nil {
				cfg.BaseURL = srv.URL + "/v1/chat/completions"
			}

			err := ValidateAPIKey(context.Background(), cfg)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.errContain != "" && !strings.Contains(err.Error(), tt.errContain) {
					t.Errorf("error %q should contain %q", err.Error(), tt.errContain)
				}
			} else if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
