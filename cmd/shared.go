package cmd

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
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

	cfg := openAIConfig()
	if strings.TrimSpace(cfg.APIKey) != "" {
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
	}

	return stubCandidates(c)
}

func openAIConfig() llm.Config {
	apiKey := strings.TrimSpace(viper.GetString("api_key"))
	if apiKey == "" {
		apiKey = strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))
	}
	return llm.Config{
		APIKey:       apiKey,
		Model:        strings.TrimSpace(viper.GetString("model")),
		BaseURL:      strings.TrimSpace(viper.GetString("base_url")),
		SystemPrompt: strings.TrimSpace(viper.GetString("system_prompt")),
		Temperature:  viper.GetFloat64("temperature"),
		MaxOutputs:   5,
	}
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
