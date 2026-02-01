package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nickawilliams/diffscribe/cmd"
	"github.com/spf13/pflag"
)

func main() {
	outDir := os.Getenv("MAN_OUT_DIR")
	if outDir == "" {
		outDir = filepath.Join("contrib", "man")
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		log.Fatalf("unable to create man dir: %v", err)
	}

	root := cmd.RootCommand()
	outPath := filepath.Join(outDir, "diffscribe.1")

	f, err := os.Create(outPath)
	if err != nil {
		log.Fatalf("unable to create man page file: %v", err)
	}
	defer f.Close()

	date := time.Now().Format("Jan 2006")

	// Header
	fmt.Fprintln(f, ".nh")
	fmt.Fprintf(f, ".TH \"DIFFSCRIBE\" \"1\" \"%s\" \"diffscribe\" \"User Commands\"\n", date)

	// NAME
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH NAME")
	fmt.Fprintf(f, "diffscribe \\- %s\n", root.Short)

	// SYNOPSIS
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH SYNOPSIS")
	fmt.Fprintln(f, `\fBdiffscribe\fP [\fIprefix\fP] [\fIflags\fP]`)

	// DESCRIPTION - extract just the main description, not env vars or config files
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH DESCRIPTION")
	desc := extractDescription(root.Long)
	fmt.Fprintln(f, escapeManPage(desc))

	// OPTIONS
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH OPTIONS")
	writeOptions(f, root.PersistentFlags())

	// ENVIRONMENT
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH ENVIRONMENT")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fBDIFFSCRIBE_API_KEY\fP, \fBOPENAI_API_KEY\fP`)
	fmt.Fprintln(f, "Provide the LLM provider API key.")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fBDIFFSCRIBE_STATUS\fP`)
	fmt.Fprintln(f, `Set to 0 to hide the "loading..." prompt indicator used by shell integrations.`)
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fBDIFFSCRIBE_STASH_COMMIT\fP`)
	fmt.Fprintln(f, "Inspect a temporary stash instead of staged changes (used in completions).")

	// FILES
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH FILES")
	fmt.Fprintln(f, "Configuration files are merged in the following order, with later entries")
	fmt.Fprintln(f, "overriding earlier ones for any keys they define:")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fI$XDG_CONFIG_HOME/diffscribe/.diffscribe*\fP`)
	fmt.Fprintln(f, "User configuration directory (XDG standard).")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fI$HOME/.diffscribe*\fP`)
	fmt.Fprintln(f, "User home directory configuration.")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fI./.diffscribe*\fP`)
	fmt.Fprintln(f, "Project-local configuration.")
	fmt.Fprintln(f, ".PP")
	fmt.Fprintln(f, "Each file only needs to specify the settings it wants to change (for example,")
	fmt.Fprintln(f, "llm.api_key, llm.provider, llm.model, etc.).")

	// EXIT STATUS
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH EXIT STATUS")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, "0")
	fmt.Fprintln(f, "Success.")
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, "1")
	fmt.Fprintln(f, "An error occurred.")

	// EXAMPLES
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH EXAMPLES")
	fmt.Fprintln(f, ".EX")
	example := strings.TrimSpace(root.Example)
	// Remove leading indentation from example lines
	lines := strings.Split(example, "\n")
	for _, line := range lines {
		fmt.Fprintln(f, strings.TrimPrefix(line, "  "))
	}
	fmt.Fprintln(f, ".EE")

	// SEE ALSO
	fmt.Fprintln(f, "")
	fmt.Fprintln(f, ".SH SEE ALSO")
	fmt.Fprintln(f, `\fBgit\fP(1), \fBgit-commit\fP(1)`)

	fmt.Printf("wrote man page to %s\n", outPath)
}

// extractDescription returns only the first paragraph of the long description,
// before the "Environment variables:" section.
func extractDescription(long string) string {
	idx := strings.Index(long, "Environment variables:")
	if idx > 0 {
		long = long[:idx]
	}
	return strings.TrimSpace(long)
}

// escapeManPage escapes special characters for troff/man pages.
func escapeManPage(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "-", `\-`)
	// Bold flag references in description
	s = strings.ReplaceAll(s, `\-\-format`, `\fB\-\-format\fP`)
	return s
}

// writeOptions writes all flags in .TP format.
func writeOptions(f *os.File, flags *pflag.FlagSet) {
	flags.VisitAll(func(flag *pflag.Flag) {
		if flag.Hidden {
			return
		}
		writeOption(f, flag)
	})

	// Add help flag (Cobra adds it automatically but not via PersistentFlags)
	fmt.Fprintln(f, ".TP")
	fmt.Fprintln(f, `\fB\-h\fP, \fB\-\-help\fP`)
	fmt.Fprintln(f, "Display help and exit.")
}

func writeOption(f *os.File, flag *pflag.Flag) {
	fmt.Fprintln(f, ".TP")

	// Build the flag signature (escape hyphens for troff)
	var sig strings.Builder
	if flag.Shorthand != "" {
		sig.WriteString(fmt.Sprintf(`\fB\-%s\fP, `, flag.Shorthand))
	}
	escapedName := strings.ReplaceAll(flag.Name, "-", `\-`)
	sig.WriteString(fmt.Sprintf(`\fB\-\-%s\fP`, escapedName))

	// Add value placeholder for non-bool flags
	if flag.Value.Type() != "bool" {
		placeholder := flagPlaceholder(flag.Name)
		sig.WriteString(fmt.Sprintf(`=\fI%s\fP`, placeholder))
	}

	fmt.Fprintln(f, sig.String())

	// Description with default value
	desc := flag.Usage
	def := flag.DefValue

	// For long defaults (prompts), don't include in man page
	if len(def) > 60 || strings.Contains(def, "\n") {
		fmt.Fprintln(f, capitalizeFirst(desc)+".")
	} else if def != "" && def != "false" && def != "0" && def != `""` {
		fmt.Fprintf(f, "%s. Default: %s\n", capitalizeFirst(desc), def)
	} else {
		fmt.Fprintln(f, capitalizeFirst(desc)+".")
	}
}

// flagPlaceholder returns an appropriate placeholder name for a flag's value.
func flagPlaceholder(name string) string {
	switch {
	case strings.HasSuffix(name, "-key"):
		return "key"
	case strings.HasSuffix(name, "-url"):
		return "url"
	case strings.HasSuffix(name, "-tokens"):
		return "n"
	case strings.HasSuffix(name, "-prompt"):
		return "prompt"
	case name == "config":
		return "file"
	case name == "llm-provider":
		return "provider"
	case name == "llm-model":
		return "model"
	case name == "llm-temperature":
		return "n"
	case name == "quantity":
		return "n"
	case name == "format":
		return "description"
	default:
		return "value"
	}
}

// capitalizeFirst capitalizes the first letter of a string.
func capitalizeFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}
