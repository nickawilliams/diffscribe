# Shared zsh helpers for diffscribe git completion.

if [[ -n ${_DIFFSCRIBE_ZSH_LIB_LOADED-} ]]; then
  return 0
fi
typeset -g _DIFFSCRIBE_ZSH_LIB_LOADED=1
typeset -ga _diffscribe_stash_args=()

_diffscribe_log() {
  [[ -z ${DIFFSCRIBE_DEBUG-} ]] && return
  print -ru2 -- "[diffscribe] $*"
}

_diffscribe_clean_prefix() {
  local clean=$1
  clean=${clean#\'}
  clean=${clean#\"}
  clean=${clean%\'}
  clean=${clean%\"}
  printf '%s' "$clean"
}

_diffscribe_detect_flag_prefix() {
  local cur prev prefix="" intercept=0
  cur=${words[CURRENT]}
  if (( CURRENT > 1 )); then
    prev=${words[CURRENT-1]}
  fi

  if [[ $prev == "-m" || $prev == "--message" ]]; then
    prefix=$cur
    intercept=1
  elif [[ $cur == --message=* ]]; then
    prefix=${cur#--message=}
    intercept=1
  elif [[ $cur == -m* && $cur != "-m" ]]; then
    prefix=${cur#-m}
    intercept=1
  fi

  (( intercept )) || return 1
  printf '%s' "$prefix"
  return 0
}

_diffscribe_detect_stash_push_prefix() {
  _diffscribe_stash_args=()
  local cur=${words[CURRENT]}
  local prev=""
  if (( CURRENT > 1 )); then
    prev=${words[CURRENT-1]}
  fi

  local prefix="" intercept=0
  if [[ $prev == "-m" || $prev == "--message" ]]; then
    prefix=$cur
    intercept=1
  elif [[ $cur == --message=* ]]; then
    prefix=${cur#--message=}
    intercept=1
  elif [[ $cur == -m* && $cur != "-m" ]]; then
    prefix=${cur#-m}
    intercept=1
  fi

  (( intercept )) || return 1

  local stash_idx=0 push_idx=0 token
  for ((i = 1; i < CURRENT; i++)); do
    token=${words[i]}
    if (( ! stash_idx )) && [[ $token == stash ]]; then
      stash_idx=$i
      continue
    fi
    if (( stash_idx && ! push_idx )) && [[ $token == push ]]; then
      push_idx=$i
      continue
    fi
  done

  (( stash_idx && push_idx && push_idx < CURRENT )) || return 1

  for ((i = stash_idx + 1; i < push_idx; i++)); do
    _diffscribe_stash_args+=("${words[i]}")
  done

  local skip_next=0 after_dd=0
  for ((i = push_idx + 1; i <= ${#words}; i++)); do
    token=${words[i]}
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

  printf '%s' "$prefix"
  return 0
}

_diffscribe_detect_stash_save_prefix() {
  _diffscribe_stash_args=()
  local stash_idx=0 save_idx=0 token
  for ((i = 1; i < CURRENT; i++)); do
    token=${words[i]}
    if (( ! stash_idx )) && [[ $token == stash ]]; then
      stash_idx=$i
      continue
    fi

    if (( stash_idx && ! save_idx )) && [[ $token == save ]]; then
      save_idx=$i
      continue
    fi

    if (( save_idx )); then
      if [[ $token == -* ]]; then
        _diffscribe_stash_args+=("$token")
        continue
      fi
      return 1
    fi
  done

  (( stash_idx && save_idx && save_idx < CURRENT )) || return 1

  local cur=${words[CURRENT]}
  if [[ $cur == -* && $cur != "-" ]]; then
    return 1
  fi

  printf '%s' "$cur"
  return 0
}

_diffscribe_run_diffscribe() {
  local prefix=$1 mode=$2 raw=""

  if [[ $mode == stash ]]; then
    local oid
    oid=$(command git stash create "${_diffscribe_stash_args[@]}" 2>/dev/null)
    if [[ -z $oid ]]; then
      _diffscribe_log "git stash create failed"
      return 1
    fi
    raw=$(DIFFSCRIBE_STASH_COMMIT=$oid command diffscribe "$prefix" 2>/dev/null)
  else
    raw=$(command diffscribe "$prefix" 2>/dev/null)
  fi

  printf '%s' "$raw"
  return 0
}

_diffscribe_complete_commit_message() {
  local prefix="" mode=""
  if prefix=$(_diffscribe_detect_stash_push_prefix 2>/dev/null); then
    mode="stash"
  elif prefix=$(_diffscribe_detect_stash_save_prefix 2>/dev/null); then
    mode="stash"
  elif prefix=$(_diffscribe_detect_flag_prefix 2>/dev/null); then
    mode="commit"
  else
    return 1
  fi

  local clean
  clean=$(_diffscribe_clean_prefix "$prefix")
  _diffscribe_log "prefix='$prefix' clean='$clean' mode=$mode"

  if ! command -v diffscribe >/dev/null 2>&1; then
    _diffscribe_log "diffscribe not in PATH"
    return 1
  fi

  local raw
  raw=$(_diffscribe_run_diffscribe "$clean" "$mode")
  local rc=$?
  _diffscribe_log "diffscribe rc=$rc"
  [[ -n $raw ]] || return 1

  local -a cands
  cands=(${(@f)raw})
  (( ${#cands} )) || return 1

  compadd -S "" -- "${cands[@]}"
  local comp_status=$?
  _diffscribe_log "compadd status=$comp_status count=${#cands}"

  if (( comp_status == 0 )); then
    compstate[list]='list'
    compstate[insert]='menu'
  fi

  return $comp_status
}

diffscribe_wrap_git_completion() {
  (( $+functions[_git] )) || autoload -Uz _git 2>/dev/null
  if ! typeset -f _git >/dev/null; then
    _diffscribe_log "_git unavailable"
    return 1
  fi

  local body
  body=$(functions _git)
  if [[ $body == *"_diffscribe_complete_commit_message"* ]]; then
    _diffscribe_log "_git already wrapped"
    return 0
  fi

  if ! functions -c _git _git_diffscribe_orig 2>/dev/null; then
    _diffscribe_log "failed to copy _git"
    return 1
  fi

  eval 'function _git() {
    if _diffscribe_complete_commit_message "$@"; then
      return 0;
    fi;
    _git_diffscribe_orig "$@";
  }'

  if type compdef >/dev/null 2>&1; then
    compdef _git git >/dev/null 2>&1
  fi

  return 0
}
