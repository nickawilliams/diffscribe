# diffscribe oh-my-zsh plugin
# Injects diffscribe completions into `git commit -m/--message` prompts.

[[ -z ${ZSH_VERSION-} ]] && return 0

typeset _diffscribe_plugin_dir=${${(%):-%N}:h}
typeset -a _diffscribe_plugin_lib_candidates=(
  "${_diffscribe_plugin_dir}/diffscribe-lib.zsh"
  "${_diffscribe_plugin_dir}/../diffscribe-lib.zsh"
  "${_diffscribe_plugin_dir}/../completions/zsh/diffscribe-lib.zsh"
  "${_diffscribe_plugin_dir}/../../completions/zsh/diffscribe-lib.zsh"
  "${_diffscribe_plugin_dir}/../../diffscribe-lib.zsh"
)

for _diffscribe_plugin_lib in ${_diffscribe_plugin_lib_candidates[@]}; do
  if [[ -r $_diffscribe_plugin_lib ]]; then
    source "$_diffscribe_plugin_lib"
    break
  fi
done
unset _diffscribe_plugin_lib _diffscribe_plugin_lib_candidates

if ! typeset -f diffscribe_wrap_git_completion >/dev/null; then
  print -ru2 -- "diffscribe: missing shared completion helpers"
  return 0
fi

diffscribe_wrap_git_completion
unset _diffscribe_plugin_dir
