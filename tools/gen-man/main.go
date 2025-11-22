package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/rogwilco/diffscribe/cmd"
	"github.com/spf13/cobra/doc"
)

func main() {
	outDir := filepath.Join("contrib", "man")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		log.Fatalf("unable to create man dir: %v", err)
	}

	root := cmd.RootCommand()
	root.DisableAutoGenTag = true

	header := &doc.GenManHeader{
		Title:   "DIFFSCRIBE",
		Section: "1",
		Source:  "diffscribe",
		Manual:  "User Commands",
	}
	if err := doc.GenManTree(root, header, outDir); err != nil {
		log.Fatalf("unable to generate man page: %v", err)
	}

	fmt.Printf("wrote man page to %s\n", filepath.Join(outDir, "diffscribe.1"))
}
