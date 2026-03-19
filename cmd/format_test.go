package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveFormat_Passthrough(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "custom format string",
			input: "Use imperative mood, max 50 chars",
			want:  "Use imperative mood, max 50 chars",
		},
		{
			name:  "empty string",
			input: "",
			want:  "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := resolveFormat(tt.input)
			if got != tt.want {
				t.Errorf("resolveFormat(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestExpandPresetReferences(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		wantSub    string
		wantPrefix string
	}{
		{
			name:       "no preset reference",
			input:      "style: pirate",
			wantPrefix: "style: pirate",
		},
		{
			name:    "contains preset name",
			input:   "format: conventional-commits, style: pirate",
			wantSub: "Structural rules",
		},
		{
			name:    "case insensitive match",
			input:   "format: Conventional-Commits, mood: cranky",
			wantSub: "Structural rules",
		},
		{
			name:    "preserves original text",
			input:   "format: conventional-commits, style: pirate",
			wantSub: "style: pirate",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := expandPresetReferences(tt.input)
			if tt.wantSub != "" && !strings.Contains(got, tt.wantSub) {
				t.Errorf("expandPresetReferences(%q) = %q, want substring %q", tt.input, got, tt.wantSub)
			}
			if tt.wantPrefix != "" && !strings.HasPrefix(got, tt.wantPrefix) {
				t.Errorf("expandPresetReferences(%q) = %q, want prefix %q", tt.input, got, tt.wantPrefix)
			}
		})
	}
}

func TestResolveFormat_Preset(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"lowercase", "conventional-commits"},
		{"uppercase", "Conventional-Commits"},
		{"mixed case", "CONVENTIONAL-COMMITS"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := resolveFormat(tt.input)
			if got != conventionalCommitsFormat {
				t.Errorf("resolveFormat(%q) did not return conventional commits preset", tt.input)
			}
		})
	}
}

func TestResolveFormat_File(t *testing.T) {
	// Create a temp file with format guidance
	dir := t.TempDir()
	path := filepath.Join(dir, "format.txt")
	content := "Use angular commit format"
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	got := resolveFormat("file:" + path)
	if got != content {
		t.Errorf("resolveFormat(file:...) = %q, want %q", got, content)
	}
}

func TestResolveFormat_FileRelativePath(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()
	path := filepath.Join(dir, "commit-style.md")
	content := "Keep it short"
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 && args[0] == "rev-parse" {
			return dir + "\n"
		}
		return ""
	}

	got := resolveFormat("file:commit-style.md")
	if got != content {
		t.Errorf("resolveFormat(file:relative) = %q, want %q", got, content)
	}
}

func TestResolveFormat_FileMissing(t *testing.T) {
	got := resolveFormat("file:/nonexistent/path/format.txt")
	if got != "" {
		t.Errorf("resolveFormat(file:missing) = %q, want empty", got)
	}
}

func TestResolveFormat_FileContentCapped(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "big.txt")
	content := strings.Repeat("x", 5000)
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	got := resolveFormat("file:" + path)
	if len(got) > 4100 {
		t.Errorf("resolveFormat(file:big) length = %d, expected <= 4100", len(got))
	}
}

func TestResolveAutoFormat_AgentsMd(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()
	agentsContent := "Use conventional commits with scope."
	if err := os.WriteFile(filepath.Join(dir, "AGENTS.md"), []byte(agentsContent), 0644); err != nil {
		t.Fatal(err)
	}

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 && args[0] == "rev-parse" {
			return dir + "\n"
		}
		return ""
	}

	got := resolveAutoFormat()
	if !strings.Contains(got, agentsContent) {
		t.Errorf("resolveAutoFormat() should contain AGENTS.md content, got %q", got)
	}
	if !strings.Contains(got, "Follow the commit message conventions") {
		t.Errorf("resolveAutoFormat() should contain follow instruction, got %q", got)
	}
}

func TestResolveAutoFormat_GitHistory(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 {
			switch args[0] {
			case "rev-parse":
				return dir + "\n"
			case "log":
				return "feat: add login\nfix: resolve crash\nchore: update deps\n"
			}
		}
		return ""
	}

	got := resolveAutoFormat()
	if !strings.Contains(got, "- feat: add login") {
		t.Errorf("resolveAutoFormat() should contain commit subjects, got %q", got)
	}
	if !strings.Contains(got, "Match the tone") {
		t.Errorf("resolveAutoFormat() should contain match instruction, got %q", got)
	}
}

func TestResolveAutoFormat_AgentsMdTakesPriority(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "AGENTS.md"), []byte("Use gitmoji"), 0644); err != nil {
		t.Fatal(err)
	}

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 {
			switch args[0] {
			case "rev-parse":
				return dir + "\n"
			case "log":
				return "feat: should not appear\n"
			}
		}
		return ""
	}

	got := resolveAutoFormat()
	if !strings.Contains(got, "Use gitmoji") {
		t.Errorf("resolveAutoFormat() should use AGENTS.md, got %q", got)
	}
	if strings.Contains(got, "should not appear") {
		t.Errorf("resolveAutoFormat() should not fall through to git log when AGENTS.md exists")
	}
}

func TestResolveAutoFormat_NoSignal(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 && args[0] == "rev-parse" {
			return dir + "\n"
		}
		return ""
	}

	got := resolveAutoFormat()
	if got != "" {
		t.Errorf("resolveAutoFormat() with no signal should return empty, got %q", got)
	}
}

func TestResolveAutoFormat_NoRepo(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	runFunc = func(name string, args ...string) string {
		return ""
	}

	got := resolveAutoFormat()
	if got != "" {
		t.Errorf("resolveAutoFormat() outside repo should return empty, got %q", got)
	}
}

func TestResolveFormat_Auto(t *testing.T) {
	originalRunFunc := runFunc
	defer func() { runFunc = originalRunFunc }()

	dir := t.TempDir()

	runFunc = func(name string, args ...string) string {
		if name == "git" && len(args) >= 1 {
			switch args[0] {
			case "rev-parse":
				return dir + "\n"
			case "log":
				return "initial commit\n"
			}
		}
		return ""
	}

	got := resolveFormat("auto")
	if !strings.Contains(got, "- initial commit") {
		t.Errorf("resolveFormat(auto) should resolve via auto mode, got %q", got)
	}

	// Case insensitive
	got = resolveFormat("AUTO")
	if !strings.Contains(got, "- initial commit") {
		t.Errorf("resolveFormat(AUTO) should resolve via auto mode, got %q", got)
	}
}
