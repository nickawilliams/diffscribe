package cmd

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/nickawilliams/diffscribe/internal/llm"
	"github.com/spf13/viper"
)

func runStatus() error {
	cfg := llm.Config{
		APIKey:   strings.TrimSpace(viper.GetString("llm.api_key")),
		Provider: strings.TrimSpace(viper.GetString("llm.provider")),
		Model:    strings.TrimSpace(viper.GetString("llm.model")),
		BaseURL:  strings.TrimSpace(viper.GetString("llm.base_url")),
	}

	fmt.Println("Configuration")
	fmt.Printf("  Provider:  %s\n", cfg.Provider)
	fmt.Printf("  Model:     %s\n", cfg.Model)
	fmt.Printf("  Base URL:  %s\n", cfg.BaseURL)
	fmt.Println()

	fmt.Println("API Key")
	if cfg.APIKey == "" {
		fmt.Println("  Status:  not configured")
		fmt.Fprintln(os.Stderr, "diffscribe: set --llm-api-key, DIFFSCRIBE_API_KEY, or OPENAI_API_KEY")
		return &exitError{code: 1, msg: "API key not configured"}
	}
	fmt.Printf("  Value:   %s\n", maskKey(cfg.APIKey))

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	stop := spinStatus("  Status:  ")
	err := llm.ValidateAPIKey(ctx, cfg)
	stop()

	if err != nil {
		fmt.Printf("  Status:  FAIL (%s)\n", err)
		return &exitError{code: 1, msg: err.Error()}
	}
	fmt.Println("  Status:  ok")
	return nil
}

var spinFrames = [...]string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// spinStatus displays a spinner on the current line with the given label.
// It returns a function that stops the spinner and clears the line.
func spinStatus(label string) func() {
	done := make(chan struct{})
	fmt.Printf("%s %s\n", label, spinFrames[0])
	go func() {
		i := 1
		for {
			select {
			case <-done:
				return
			default:
				fmt.Printf("\033[A\r%s %s\n", label, spinFrames[i%len(spinFrames)])
				i++
				time.Sleep(80 * time.Millisecond)
			}
		}
	}()
	return func() {
		close(done)
		fmt.Printf("\033[A\r%s\r", strings.Repeat(" ", len(label)+4))
	}
}

// maskKey shows the first 4 and last 4 characters of the key with the middle
// replaced by an ellipsis. Keys shorter than 12 characters are fully masked.
func maskKey(key string) string {
	if len(key) < 12 {
		return "..."
	}
	return key[:4] + "..." + key[len(key)-4:]
}
