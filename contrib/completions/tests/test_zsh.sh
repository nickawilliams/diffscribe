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
typeset -a TEST_COMPLETIONS=()

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

print -- "zsh completion tests passed"
