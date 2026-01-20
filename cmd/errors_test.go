package cmd

import (
	"errors"
	"fmt"
	"testing"
)

func TestExitCode(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want int
	}{
		{
			name: "nil error returns 0",
			err:  nil,
			want: 0,
		},
		{
			name: "generic error returns 1",
			err:  errors.New("something went wrong"),
			want: 1,
		},
		{
			name: "exitError returns custom code",
			err:  &exitError{code: 42, msg: "custom exit"},
			want: 42,
		},
		{
			name: "exitError with code 0",
			err:  &exitError{code: 0, msg: "success with error"},
			want: 0,
		},
		{
			name: "wrapped exitError returns custom code",
			err:  fmt.Errorf("wrapped: %w", &exitError{code: 5, msg: "inner"}),
			want: 5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExitCode(tt.err)
			if got != tt.want {
				t.Errorf("ExitCode() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestExitError_Error(t *testing.T) {
	e := &exitError{code: 1, msg: "test message"}
	if got := e.Error(); got != "test message" {
		t.Errorf("Error() = %q, want %q", got, "test message")
	}
}
