package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:           "diffscribe",
	Short:         "LLM-assisted git commit helper",
	SilenceUsage:  true,
	SilenceErrors: true,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default searches diffscribe.{yaml,json,toml})")
	rootCmd.PersistentFlags().String("api-key", "", "LLM provider API key")
	rootCmd.PersistentFlags().String("model", "", "LLM model identifier")
	rootCmd.PersistentFlags().String("base-url", "", "LLM API base URL")
	rootCmd.PersistentFlags().String("system-prompt", "", "LLM system prompt override")
	rootCmd.PersistentFlags().Float64("temperature", 0.2, "LLM sampling temperature")

	_ = viper.BindPFlag("api_key", rootCmd.PersistentFlags().Lookup("api-key"))
	_ = viper.BindPFlag("model", rootCmd.PersistentFlags().Lookup("model"))
	_ = viper.BindPFlag("base_url", rootCmd.PersistentFlags().Lookup("base-url"))
	_ = viper.BindPFlag("system_prompt", rootCmd.PersistentFlags().Lookup("system-prompt"))
	_ = viper.BindPFlag("temperature", rootCmd.PersistentFlags().Lookup("temperature"))

	viper.SetDefault("temperature", 0.2)

	rootCmd.AddCommand(genCmd)
	rootCmd.AddCommand(completeCmd)
}

func initConfig() {
	viper.SetEnvPrefix("diffscribe")
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))
	viper.AutomaticEnv()

	if viper.GetString("api_key") == "" {
		if val := strings.TrimSpace(os.Getenv("OPENAI_API_KEY")); val != "" {
			viper.Set("api_key", val)
		}
	}

	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		viper.SetConfigName("diffscribe")
		viper.AddConfigPath(".")
		if home, err := os.UserHomeDir(); err == nil {
			viper.AddConfigPath(home)
		}
	}

	if err := viper.ReadInConfig(); err == nil {
		fmt.Fprintf(os.Stderr, "Using config file: %s\n", viper.ConfigFileUsed())
	}
}
