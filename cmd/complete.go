package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

var completePrefix string

var completeCmd = &cobra.Command{
	Use:   "complete",
	Short: "Emit candidates filtered by a prefix (used by shell completion)",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, err := collectContext()
		if err != nil {
			return err
		}
		candidates := generateCandidates(ctx)
		prefix := strings.TrimSpace(strings.ToLower(completePrefix))
		for _, c := range candidates {
			if prefix == "" || strings.HasPrefix(strings.ToLower(c), prefix) {
				fmt.Println(c)
			}
		}
		return nil
	},
}

func init() {
	completeCmd.Flags().StringVar(&completePrefix, "prefix", "", "current token prefix")
}
