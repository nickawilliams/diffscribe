package version

import "testing"

func TestString(t *testing.T) {
	got := String()
	if got == "" {
		t.Error("String() returned empty string")
	}
	// Default value when not set via ldflags is "dev"
	if got != "dev" {
		t.Logf("String() = %q (set via ldflags)", got)
	}
}
