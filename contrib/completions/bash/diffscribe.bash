# diffscribe: Bash completion hook for git commit and git stash messages.
# Load this *after* standard git completion (usually in ~/.bashrc).

# Preserve the original _git_commit if already defined
if declare -F _git_commit >/dev/null && ! declare -F _git_commit_orig >/dev/null; then
  eval "$(declare -f _git_commit | sed '1s/_git_commit/_git_commit_orig/')"
fi

# Helper to call diffscribe for completion candidates
_diffscribe_candidates() {
  local prefix=$1
  local mode=${2-}
  local qty=${DIFFSCRIBE_QUANTITY:-1}
  local diffscribe_cmd=(diffscribe --quantity "$qty")
  if [[ $mode == "stash" ]]; then
    local oid
    oid=$(command git stash create "${_diffscribe_stash_args[@]}" 2>/dev/null) || return
    [[ -n $oid ]] || return
    DIFFSCRIBE_STASH_COMMIT=$oid "${diffscribe_cmd[@]}" "$prefix" 2>/dev/null
  else
    "${diffscribe_cmd[@]}" "$prefix" 2>/dev/null
  fi
}

declare -a _diffscribe_stash_args=()

_diffscribe_stash_save_prefix() {
  _diffscribe_stash_args=()
  local cword=${COMP_CWORD}
  local cur="${COMP_WORDS[cword]}"

  # Do not intercept option completions
  if [[ $cur == -* && $cur != "-" ]]; then
    return 1
  fi

  local seen_stash=0 seen_save=0 token
  local i
  for (( i=0; i<cword; i++ )); do
    token=${COMP_WORDS[i]}
    if (( ! seen_stash )); then
      [[ $token == stash ]] && seen_stash=1
      continue
    fi
    if (( ! seen_save )); then
      if [[ $token == save ]]; then
        seen_save=1
      fi
      continue
    fi

    if [[ $token == -* ]]; then
      _diffscribe_stash_args+=("$token")
      continue
    fi

    return 1
  done

  (( seen_stash && seen_save )) || return 1
  printf '%s' "$cur"
  return 0
}

_diffscribe_prepare_stash_push_args() {
  _diffscribe_stash_args=()
  local total=${#COMP_WORDS[@]}
  local stash_idx=-1 push_idx=-1 token
  local i
  for (( i=0; i<total; i++ )); do
    token=${COMP_WORDS[i]}
    if (( stash_idx < 0 )) && [[ $token == stash ]]; then
      stash_idx=$i
      continue
    fi
    if (( stash_idx >= 0 && push_idx < 0 )) && [[ $token == push ]]; then
      push_idx=$i
      continue
    fi
  done

  (( stash_idx >= 0 && push_idx > stash_idx )) || return 1

  for (( i=stash_idx+1; i<push_idx; i++ )); do
    _diffscribe_stash_args+=("${COMP_WORDS[i]}")
  done

  local skip_next=0 after_dd=0
  for (( i=push_idx+1; i<total; i++ )); do
    token=${COMP_WORDS[i]}
    if (( skip_next )); then
      skip_next=0
      continue
    fi

    case $token in
      -m|--message)
        skip_next=1
        continue
        ;;
      --message=*)
        continue
        ;;
      -m*)
        continue
        ;;
    esac

    if [[ $token == -- ]]; then
      after_dd=1
      _diffscribe_stash_args+=("$token")
      continue
    fi

    if (( after_dd )); then
      _diffscribe_stash_args+=("$token")
      continue
    fi

    if [[ $token == push ]]; then
      continue
    fi

    _diffscribe_stash_args+=("$token")
  done

  return 0
}

_diffscribe_stash_push_prefix() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local prefix=""

  if [[ "$prev" == "-m" || "$prev" == "--message" ]]; then
    prefix=$cur
  elif [[ "$cur" == --message=* ]]; then
    prefix=${cur#--message=}
  elif [[ "$cur" == -m* && "$cur" != "-m" ]]; then
    prefix=${cur#-m}
  else
    return 1
  fi

  if ! _diffscribe_prepare_stash_push_args; then
    return 1
  fi

  printf '%s' "$prefix"
  return 0
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

  # Handle stash push -m/--message contexts first
  local stash_prefix
  if stash_prefix=$(_diffscribe_stash_push_prefix 2>/dev/null); then
    local IFS=$'\n'
    COMPREPLY=( $(compgen -W "$(_diffscribe_candidates "$stash_prefix" stash)" -- "$stash_prefix") )
    return 0
  fi

  if stash_prefix=$(_diffscribe_stash_save_prefix 2>/dev/null); then
    local IFS=$'\n'
    COMPREPLY=( $(compgen -W "$(_diffscribe_candidates "$stash_prefix" stash)" -- "$stash_prefix") )
    return 0
  fi

  # When previous token is -m or --message, use diffscribe suggestions for commit
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
