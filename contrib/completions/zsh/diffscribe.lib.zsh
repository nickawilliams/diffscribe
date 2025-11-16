# Shared zsh helpers for diffscribe git completion.

if [[ -n ${_DIFFSCRIBE_ZSH_LIB_LOADED-} ]]; then
  return 0
fi
typeset -g _DIFFSCRIBE_ZSH_LIB_LOADED=1

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

_diffscribe_complete_commit_message() {
  local prev cur prefix="" intercept=0
  cur=${words[CURRENT]}
  if (( CURRENT > 1 )); then
    prev=${words[CURRENT-1]}
  fi

  if [[ $prev == "-m" || $prev == "--message" ]]; then
    intercept=1
    prefix=$cur
  elif [[ $cur == --message=* ]]; then
    intercept=1
    prefix=${cur#--message=}
  elif [[ $cur == -m* && $cur != "-m" ]]; then
    intercept=1
    prefix=${cur#-m}
  fi

  (( intercept )) || return 1

  local clean
  clean=$(_diffscribe_clean_prefix "$prefix")
  _diffscribe_log "prefix='$prefix' clean='$clean'"

  if ! command -v diffscribe >/dev/null 2>&1; then
    _diffscribe_log "diffscribe not in PATH"
    return 1
  fi

  local raw
  raw=$(command diffscribe "$clean" 2>/dev/null)
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
