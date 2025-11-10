package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	switch os.Args[1] {
	case "gen":
		genCmd(os.Args[2:])
	case "complete":
		completeCmd(os.Args[2:])
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "Usage:")
	fmt.Fprintln(os.Stderr, "  diffscribe gen [--top N]")
	fmt.Fprintln(os.Stderr, "  diffscribe complete --prefix <text>")
	os.Exit(2)
}

func genCmd(args []string) {
	fs := flag.NewFlagSet("gen", flag.ExitOnError)
	top := fs.Int("top", 5, "max candidates")
	_ = fs.Parse(args)

	ctx := collectContext()
	cands := generateCandidates(ctx)
	if len(cands) == 0 {
		os.Exit(10) // no suggestions
	}
	if *top > 0 && *top < len(cands) {
		cands = cands[:*top]
	}
	for _, s := range cands {
		fmt.Println(s)
	}
}

func completeCmd(args []string) {
	fs := flag.NewFlagSet("complete", flag.ExitOnError)
	prefix := fs.String("prefix", "", "current token prefix")
	_ = fs.Parse(args)

	ctx := collectContext()
	cands := generateCandidates(ctx)
	for _, s := range cands {
		if *prefix == "" || strings.HasPrefix(strings.ToLower(s), strings.ToLower(*prefix)) {
			fmt.Println(s)
		}
	}
}

type ctx struct {
	Branch string
	Paths  []string
	Diff   string
}

func collectContext() ctx {
	return ctx{
		Branch: strings.TrimSpace(run("git", "rev-parse", "--abbrev-ref", "HEAD")),
		Paths:  nonEmptyLines(run("git", "diff", "--cached", "--name-only")),
		Diff:   capString(run("git", "diff", "--cached", "--unified=0"), 8000),
	}
}

func generateCandidates(c ctx) []string {
	if len(c.Paths) == 0 {
		return nil
	}
	summary := joinLimit(c.Paths, 3)
	// Stub suggestions for now; swap with LLM later.
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
	var err bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &err
	_ = cmd.Start()
	done := make(chan struct{})
	go func() { _ = cmd.Wait(); close(done) }()
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
