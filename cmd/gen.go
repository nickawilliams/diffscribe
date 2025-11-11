package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	genTop int
)

var genCmd = &cobra.Command{
	Use:   "gen",
	Short: "Generate commit message candidates",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, err := collectContext()
		if err != nil {
			return err
		}
		candidates := generateCandidates(ctx)
		if len(candidates) == 0 {
			return errNoSuggestions
		}
		if genTop > 0 && genTop < len(candidates) {
			candidates = candidates[:genTop]
		}
		for _, c := range candidates {
			fmt.Println(c)
		}
		return nil
	},
}

func init() {
	genCmd.Flags().IntVar(&genTop, "top", 5, "maximum number of candidates to print")
}
