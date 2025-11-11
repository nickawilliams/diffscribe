package cmd

import "errors"

type exitError struct {
	code int
	msg  string
}

func (e *exitError) Error() string { return e.msg }

var errNoSuggestions = &exitError{code: 10, msg: "no suggestions"}

// ExitCode returns the desired process exit code for the given error.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var ee *exitError
	if errors.As(err, &ee) {
		return ee.code
	}
	return 1
}
