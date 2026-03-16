package cmd

import "testing"

func TestMaskKey(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want string
	}{
		{"long key", "sk-proj-abcdefghijklmnop", "sk-p...mnop"},
		{"exactly 12 chars", "123456789012", "1234...9012"},
		{"short key", "short", "..."},
		{"empty key", "", "..."},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := maskKey(tt.key); got != tt.want {
				t.Errorf("maskKey(%q) = %q, want %q", tt.key, got, tt.want)
			}
		})
	}
}
