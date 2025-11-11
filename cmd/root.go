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
	rootCmd.PersistentFlags().String("openai-api-key", "", "OpenAI API key")
	rootCmd.PersistentFlags().String("openai-model", "", "OpenAI model identifier")
	rootCmd.PersistentFlags().String("openai-base-url", "", "OpenAI base URL")
	rootCmd.PersistentFlags().String("openai-system-prompt", "", "OpenAI system prompt override")
	rootCmd.PersistentFlags().Float64("openai-temperature", 0.2, "OpenAI sampling temperature")

	_ = viper.BindPFlag("openai_api_key", rootCmd.PersistentFlags().Lookup("openai-api-key"))
	_ = viper.BindPFlag("openai_model", rootCmd.PersistentFlags().Lookup("openai-model"))
	_ = viper.BindPFlag("openai_base_url", rootCmd.PersistentFlags().Lookup("openai-base-url"))
	_ = viper.BindPFlag("openai_system_prompt", rootCmd.PersistentFlags().Lookup("openai-system-prompt"))
	_ = viper.BindPFlag("openai_temperature", rootCmd.PersistentFlags().Lookup("openai-temperature"))

	viper.SetDefault("openai_temperature", 0.2)

	rootCmd.AddCommand(genCmd)
	rootCmd.AddCommand(completeCmd)
}

func initConfig() {
	viper.SetEnvPrefix("diffscribe")
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))
	viper.AutomaticEnv()

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
