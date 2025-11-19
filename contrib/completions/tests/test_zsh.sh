#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h:h:h}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat <<'EOF' >"$tmp_dir/diffscribe"
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${DIFFSCRIBE_STASH_COMMIT:-} ]]; then
  printf 'stash-candidate\n'
else
  printf 'commit-candidate\n'
fi
EOF
chmod +x "$tmp_dir/diffscribe"

cat <<'EOF' >"$tmp_dir/git"
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "stash" && "$2" == "create" ]]; then
  shift 2
  echo deadbeef
  exit 0
fi
echo "unexpected git command: $*" >&2
exit 1
EOF
chmod +x "$tmp_dir/git"

export PATH="$tmp_dir:$PATH"

source "$repo_root/contrib/completions/zsh/diffscribe.lib.zsh"

typeset -Ag compstate
typeset -Ag _comps
typeset -a TEST_COMPLETIONS=()
typeset called_git=0

compdef() {
  local func=$1
  shift
  local arg cmd
  for arg in "$@"; do
    if [[ $arg == *=* ]]; then
      func=${arg%%=*}
      cmd=${arg#*=}
      _comps[$cmd]=$func
    else
      _comps[$arg]=$func
    fi
  done
}

compadd() {
  local args=("$@")
  local idx=1
  while (( $# > 0 )); do
    case $1 in
      -S)
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        shift
        ;;
      *)
        break
        ;;
    esac
  done
  TEST_COMPLETIONS=("$@")
  return 0
}

assert_eq() {
  local expected=$1
  local actual=$2
  local msg=$3
  if [[ "$expected" != "$actual" ]]; then
    print -u2 -- "FAIL: $msg (expected '$expected', got '$actual')"
    exit 1
  fi
}

run_completion() {
  local expected=$1
  shift
  words=("$@")
  CURRENT=${#words}
  TEST_COMPLETIONS=()
  if ! _diffscribe_complete_commit_message; then
    print -u2 -- "FAIL: completion handler returned non-zero"
    exit 1
  fi
  assert_eq "$expected" "${TEST_COMPLETIONS[1]-}" "zsh completion for $words"
}

run_completion "commit-candidate" git commit -m ''
run_completion "stash-candidate" git stash push --include-untracked -- src -m ''
run_completion "stash-candidate" git stash save -k ''

# Completing again with an existing message should still trigger diffscribe.
words=(git commit -m 'commit-candidate' '')
CURRENT=${#words}
TEST_COMPLETIONS=()
if ! _diffscribe_complete_commit_message; then
  print -u2 -- "FAIL: repeat commit completion returned non-zero"
  exit 1
fi
assert_eq "commit-candidate" "${TEST_COMPLETIONS[1]-}" "repeat commit completion"

words=(git stash push --include-untracked -- src -m 'stash-candidate' '')
CURRENT=${#words}
TEST_COMPLETIONS=()
if ! _diffscribe_complete_commit_message; then
  print -u2 -- "FAIL: repeat stash push completion returned non-zero"
  exit 1
fi
assert_eq "stash-candidate" "${TEST_COMPLETIONS[1]-}" "repeat stash push completion"

words=(git stash save -k 'stash-candidate' '')
CURRENT=${#words}
TEST_COMPLETIONS=()
if ! _diffscribe_complete_commit_message; then
  print -u2 -- "FAIL: repeat stash save completion returned non-zero"
  exit 1
fi
assert_eq "stash-candidate" "${TEST_COMPLETIONS[1]-}" "repeat stash save completion"

print -- "zsh completion tests passed"

# Ensure the git completion wrapper intercepts commit completions and falls back
# to the original _git implementation otherwise.
_git() {
  (( called_git++ ))
  return 0
}

_comps[git]=_git
_diffscribe_git_orig_handler=""
_diffscribe_git_hook_registered=0
diffscribe_wrap_git_completion
assert_eq "_diffscribe_git_wrapper" "${_comps[git]-}" "git completion wrapper registered"
assert_eq 1 ${_diffscribe_git_hook_registered:-0} "git completion hook registered"

# Simulate another plugin re-registering git completion (e.g., git plugin loaded after us).
_comps[git]=_git
diffscribe_wrap_git_completion
assert_eq "_diffscribe_git_wrapper" "${_comps[git]-}" "wrapper reapplied after override"

words=(git commit -m '')
CURRENT=${#words}
called_git=0
TEST_COMPLETIONS=()
if ! _diffscribe_git_wrapper; then
  print -u2 -- "FAIL: wrapper commit invocation failed"
  exit 1
fi
assert_eq 0 $called_git "wrapper short-circuits git commit completions"
assert_eq "commit-candidate" "${TEST_COMPLETIONS[1]-}" "wrapper commit completion"

words=(git status)
CURRENT=${#words}
called_git=0
TEST_COMPLETIONS=()
if ! _diffscribe_git_wrapper; then
  print -u2 -- "FAIL: wrapper fallback invocation failed"
  exit 1
fi
assert_eq 1 $called_git "wrapper falls back to original git completion"
