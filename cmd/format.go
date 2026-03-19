package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const conventionalCommitsFormat = `Conventional Commit format: <type>[optional scope]: <description>

Rules:
- Type (feat, fix, refactor, docs, chore, etc.) reflects the nature of the changes. Use the same type across suggestions unless genuinely ambiguous.
- Scope is optional. Include only if changes clearly target a specific module or component. Derive from code structure and use consistently.
- Description is a sentence fragment without trailing punctuation, under ~72 characters.`

// formatPresets maps preset names to their full descriptions (used when the
// preset is the entire format value).
var formatPresets = map[string]string{
	"conventional-commits": conventionalCommitsFormat,
}

// formatPresetSummaries maps preset names to compact one-line structural
// descriptions suitable for inline expansion within a larger format string.
var formatPresetSummaries = map[string]string{
	"conventional-commits": `Conventional Commit structure: "<type>[optional scope]: <description>" (under ~72 chars, no trailing punctuation)`,
}

// resolveFormat interprets the format value and returns the final format
// guidance string to embed in the user prompt. It handles auto-detection,
// named presets, file references, and plain pass-through.
func resolveFormat(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))

	if normalized == "auto" {
		return resolveAutoFormat()
	}

	if preset, ok := formatPresets[normalized]; ok {
		return preset
	}

	if strings.HasPrefix(normalized, "file:") {
		return resolveFileFormat(strings.TrimPrefix(raw[len("file:"):], " "))
	}

	return expandPresetReferences(raw)
}

// expandPresetReferences checks if the free-form format string mentions any
// known preset names. When found, the preset's structural rules are appended
// as a clearly labeled block so the LLM treats them as hard constraints while
// the rest of the string (tone, style, mood) remains prominent.
func expandPresetReferences(s string) string {
	lower := strings.ToLower(s)
	var expanded []string
	for name, summary := range formatPresetSummaries {
		if strings.Contains(lower, name) {
			expanded = append(expanded, summary)
		}
	}
	if len(expanded) == 0 {
		return s
	}
	return s + "\n\nStructural rules (every suggestion must match this pattern exactly):\n" +
		strings.Join(expanded, "\n")
}

// resolveAutoFormat inspects the project for format signals.
func resolveAutoFormat() string {
	repoRoot := strings.TrimSpace(run("git", "rev-parse", "--show-toplevel"))
	if repoRoot == "" {
		return ""
	}

	// 1. Check for AGENTS.md
	agentsPath := filepath.Join(repoRoot, "AGENTS.md")
	if data, err := os.ReadFile(agentsPath); err == nil {
		content := capString(strings.TrimSpace(string(data)), 4096)
		if content != "" {
			return "The following project guidelines describe the expected commit message format:\n\n" +
				content +
				"\n\nFollow the commit message conventions described above."
		}
	}

	// 2. Check git history
	log := strings.TrimSpace(run("git", "log", "--format=%s", "--no-merges", "-n", "20"))
	if log != "" {
		subjects := nonEmptyLines(log)
		if len(subjects) > 0 {
			var b strings.Builder
			b.WriteString("Infer the commit message style from these recent commits in this repository:\n")
			for _, s := range subjects {
				b.WriteString("- ")
				b.WriteString(s)
				b.WriteString("\n")
			}
			b.WriteString("\nMatch the tone, structure, and conventions shown above.")
			return b.String()
		}
	}

	// 3. No signal
	return ""
}

// resolveFileFormat reads the specified file and returns its contents as
// format guidance. Relative paths are resolved against the git repo root.
func resolveFileFormat(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		fmt.Fprintln(os.Stderr, "diffscribe: file: format directive has no path")
		return ""
	}

	if !filepath.IsAbs(path) {
		repoRoot := strings.TrimSpace(run("git", "rev-parse", "--show-toplevel"))
		if repoRoot != "" {
			path = filepath.Join(repoRoot, path)
		}
	}

	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diffscribe: unable to read format file %s: %v\n", path, err)
		return ""
	}

	return capString(strings.TrimSpace(string(data)), 4096)
}
