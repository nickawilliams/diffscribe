package cmd

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/viper"
)

func TestReadConfigFile_WithExtension(t *testing.T) {
	dir := t.TempDir()

	yamlFile := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(yamlFile, []byte("llm:\n  model: test-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := viper.New()
	if err := readConfigFile(cfg, yamlFile); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got := cfg.GetString("llm.model"); got != "test-model" {
		t.Fatalf("expected test-model, got %s", got)
	}
}

func TestReadConfigFile_WithoutExtension(t *testing.T) {
	dir := t.TempDir()

	// File without extension, treated as YAML
	noExtFile := filepath.Join(dir, ".diffscribe")
	if err := os.WriteFile(noExtFile, []byte("llm:\n  provider: test-provider\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := viper.New()
	if err := readConfigFile(cfg, noExtFile); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got := cfg.GetString("llm.provider"); got != "test-provider" {
		t.Fatalf("expected test-provider, got %s", got)
	}
}

func TestReadConfigFile_JSON(t *testing.T) {
	dir := t.TempDir()

	jsonFile := filepath.Join(dir, "config.json")
	if err := os.WriteFile(jsonFile, []byte(`{"llm":{"model":"json-model"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := viper.New()
	if err := readConfigFile(cfg, jsonFile); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got := cfg.GetString("llm.model"); got != "json-model" {
		t.Fatalf("expected json-model, got %s", got)
	}
}

func TestReadConfigFile_TOML(t *testing.T) {
	dir := t.TempDir()

	tomlFile := filepath.Join(dir, "config.toml")
	if err := os.WriteFile(tomlFile, []byte("[llm]\nmodel = \"toml-model\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := viper.New()
	if err := readConfigFile(cfg, tomlFile); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got := cfg.GetString("llm.model"); got != "toml-model" {
		t.Fatalf("expected toml-model, got %s", got)
	}
}

func TestReadConfigFile_NonExistent(t *testing.T) {
	cfg := viper.New()
	err := readConfigFile(cfg, "/nonexistent/path/config.yaml")
	if err == nil {
		t.Fatal("expected error for nonexistent file")
	}
}

func TestReadConfigFile_NonExistentNoExt(t *testing.T) {
	cfg := viper.New()
	err := readConfigFile(cfg, "/nonexistent/path/.diffscribe")
	if err == nil {
		t.Fatal("expected error for nonexistent file without extension")
	}
}

func TestMergeConfigIfExists_FileExists(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()
	cfgFile := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(cfgFile, []byte("llm:\n  model: merged-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	mergeConfigIfExists(cfgFile, false)

	if got := viper.GetString("llm.model"); got != "merged-model" {
		t.Fatalf("expected merged-model, got %s", got)
	}
}

func TestMergeConfigIfExists_Verbose(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()
	cfgFile := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(cfgFile, []byte("llm:\n  model: verbose-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Should not panic; verbose=true prints to stderr
	mergeConfigIfExists(cfgFile, true)

	if got := viper.GetString("llm.model"); got != "verbose-model" {
		t.Fatalf("expected verbose-model, got %s", got)
	}
}

func TestMergeConfigIfExists_FileNotExists(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	// Should not panic or error, just silently skip
	mergeConfigIfExists("/nonexistent/config.yaml", false)
}

func TestMergeConfigIfExists_EmptyPath(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	// Should not panic or error, just return early
	mergeConfigIfExists("", false)
}

func TestMergeConfigIfExists_IsDirectory(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()

	// Should not panic or error when path is a directory
	mergeConfigIfExists(dir, false)
}

func TestMergeConfigIfExists_InvalidYAML(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()
	cfgFile := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(cfgFile, []byte("not: valid: yaml: content:::"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Should not panic, just print error to stderr
	mergeConfigIfExists(cfgFile, false)
}

func TestLoadConfigSet_EmptyDir(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	// Should not panic or error
	loadConfigSet("")
}

func TestLoadConfigSet_WithConfigs(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()

	// Create a .diffscribe.yaml file
	cfgFile := filepath.Join(dir, ".diffscribe.yaml")
	if err := os.WriteFile(cfgFile, []byte("llm:\n  model: set-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	loadConfigSet(dir)

	if got := viper.GetString("llm.model"); got != "set-model" {
		t.Fatalf("expected set-model, got %s", got)
	}
}

func TestLoadConfigSet_MultipleFiles(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()

	// Create .diffscribe (base)
	base := filepath.Join(dir, ".diffscribe")
	if err := os.WriteFile(base, []byte("llm:\n  model: base-model\n  provider: base-provider\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Create .diffscribe.yaml (should override)
	override := filepath.Join(dir, ".diffscribe.yaml")
	if err := os.WriteFile(override, []byte("llm:\n  model: override-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	loadConfigSet(dir)

	// Model should be overridden
	if got := viper.GetString("llm.model"); got != "override-model" {
		t.Fatalf("expected override-model, got %s", got)
	}

	// Provider should remain from base
	if got := viper.GetString("llm.provider"); got != "base-provider" {
		t.Fatalf("expected base-provider, got %s", got)
	}
}

func TestLoadConfigSet_NoMatchingFiles(t *testing.T) {
	viper.Reset()
	defer viper.Reset()

	dir := t.TempDir()

	// Create a file that doesn't match the pattern
	otherFile := filepath.Join(dir, "other.yaml")
	if err := os.WriteFile(otherFile, []byte("llm:\n  model: other-model\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	loadConfigSet(dir)

	// Should not have loaded anything
	if got := viper.GetString("llm.model"); got != "" {
		t.Fatalf("expected empty, got %s", got)
	}
}
