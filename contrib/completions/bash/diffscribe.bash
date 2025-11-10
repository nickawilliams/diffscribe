# diffscribe: Bash completion hook for "git commit -m"
# Load this *after* standard git completion (usually in ~/.bashrc).

# Preserve the original _git_commit if already defined
if declare -F _git_commit >/dev/null && ! declare -F _git_commit_orig >/dev/null; then
  eval "$(declare -f _git_commit | sed '1s/_git_commit/_git_commit_orig/')"
fi

# Helper to call diffscribe for completion candidates
_diffscribe_candidates() {
  diffscribe complete --prefix "$1" 2>/dev/null
}

_git_commit() {
  local cur prev
  # bash-completion provides _get_comp_words_by_ref
  if declare -F _get_comp_words_by_ref >/dev/null; then
    _get_comp_words_by_ref -n =: cur prev
  else
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  # When previous token is -m or --message, use diffscribe suggestions
  if [[ "$prev" == "-m" || "$prev" == "--message" ]]; then
    local IFS=$'\n'
    COMPREPLY=( $(compgen -W "$(_diffscribe_candidates "$cur")" -- "$cur") )
    return 0
  fi

  # Fallback to the original git completion if it exists
  if declare -F _git_commit_orig >/dev/null; then
    _git_commit_orig "$@"
  fi
}

# Re-register git completion to point at our wrapped _git_commit
complete -o bashdefault -o default -F _git_commit git
