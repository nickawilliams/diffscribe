package cmd

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"text/template"
	"time"

	"github.com/rogwilco/diffscribe/internal/llm"
	"github.com/spf13/viper"
)

type gitContext struct {
	Branch string
	Paths  []string
	Diff   string
}

func collectContext() (gitContext, error) {
	return gitContext{
		Branch: strings.TrimSpace(run("git", "rev-parse", "--abbrev-ref", "HEAD")),
		Paths:  nonEmptyLines(run("git", "diff", "--cached", "--name-only")),
		Diff:   capString(run("git", "diff", "--cached", "--unified=0"), 8000),
	}, nil
}

func generateCandidates(c gitContext) []string {
	if len(c.Paths) == 0 {
		return nil
	}

	tplData := templateData{
		Branch:     c.Branch,
		Paths:      c.Paths,
		Diff:       c.Diff,
		FileCount:  len(c.Paths),
		Summary:    joinLimit(c.Paths, 3),
		DiffLength: len(c.Diff),
		Timestamp:  time.Now(),
	}

	cfg := newLLMConfig(tplData)
	if err := requireLLMConfig(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return nil
	}

	msgs, err := llm.GenerateCommitMessages(context.Background(), llm.Context{
		Branch: c.Branch,
		Paths:  c.Paths,
		Diff:   c.Diff,
	}, cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "diffscribe: LLM error:", err)
	} else if len(msgs) > 0 {
		return msgs
	}

	return stubCandidates(c)
}

type templateData struct {
	Branch     string
	Paths      []string
	Diff       string
	FileCount  int
	Summary    string
	DiffLength int
	Timestamp  time.Time
}

type systemPromptData struct {
	templateData
	Model       string
	Provider    string
	Quantity    int
	Temperature float64
}

type userPromptData struct {
	templateData
	Quantity int
}

func newLLMConfig(data templateData) llm.Config {
	cfg := llm.Config{
		APIKey:      strings.TrimSpace(viper.GetString("api_key")),
		Model:       strings.TrimSpace(viper.GetString("model")),
		BaseURL:     strings.TrimSpace(viper.GetString("base_url")),
		Temperature: viper.GetFloat64("temperature"),
		Quantity:    viper.GetInt("quantity"),
	}

	sysData := systemPromptData{
		templateData: data,
		Model:        cfg.Model,
		Provider:     "openai",
		Quantity:     cfg.Quantity,
		Temperature:  cfg.Temperature,
	}
	userData := userPromptData{
		templateData: data,
		Quantity:     cfg.Quantity,
	}

	cfg.SystemPrompt = renderTemplate(viper.GetString("system_prompt"), sysData)
	cfg.UserPrompt = renderTemplate(viper.GetString("user_prompt"), userData)
	return cfg
}

func renderTemplate(raw string, data any) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	tmpl, err := template.New("prompt").Parse(raw)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diffscribe: bad system prompt template: %v\n", err)
		return raw
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		fmt.Fprintf(os.Stderr, "diffscribe: system prompt render error: %v\n", err)
		return raw
	}
	return buf.String()
}

func requireLLMConfig(cfg llm.Config) error {
	if strings.TrimSpace(cfg.APIKey) == "" {
		return errors.New("diffscribe: api_key is required (set --api-key or DIFFSCRIBE_API_KEY/OPENAI_API_KEY)")
	}
	return nil
}

func stubCandidates(c gitContext) []string {
	summary := joinLimit(c.Paths, 3)
	return []string{
		"feat: " + summary,
		"fix: address issues in " + c.Branch,
		"chore: update " + summary,
		"refactor: simplify " + summary,
		"docs: update docs for " + summary,
	}
}

func run(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	cmd.Env = os.Environ()
	var out bytes.Buffer
	var errBuf bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errBuf
	_ = cmd.Start()
	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(1500 * time.Millisecond):
		_ = cmd.Process.Kill()
	}
	return out.String()
}

func nonEmptyLines(s string) []string {
	sc := bufio.NewScanner(strings.NewReader(s))
	var out []string
	for sc.Scan() {
		x := strings.TrimSpace(sc.Text())
		if x != "" {
			out = append(out, x)
		}
	}
	return out
}

func capString(s string, n int) string {
	if len(s) > n {
		return s[:n] + "\n…"
	}
	return s
}

func joinLimit(ss []string, n int) string {
	if len(ss) == 0 {
		return "changes"
	}
	if len(ss) <= n {
		return strings.Join(ss, ", ")
	}
	return strings.Join(ss[:n], ", ") + "…"
}
