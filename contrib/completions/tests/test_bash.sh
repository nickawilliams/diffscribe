#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat <<'EOF' >"$TMP_DIR/diffscribe"
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${DIFFSCRIBE_STASH_COMMIT:-} ]]; then
  printf 'stash-candidate\n'
else
  printf 'commit-candidate\n'
fi
EOF
chmod +x "$TMP_DIR/diffscribe"

cat <<'EOF' >"$TMP_DIR/git"
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
chmod +x "$TMP_DIR/git"

export PATH="$TMP_DIR:$PATH"

unset -f _git_commit >/dev/null 2>&1 || true
source "$REPO_ROOT/contrib/completions/bash/diffscribe.bash"

assert_eq() {
  local expected=$1
  local actual=$2
  local msg=$3
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
    exit 1
  fi
}

# Commit completion
COMPREPLY=()
COMP_WORDS=(git commit -m "")
COMP_CWORD=3
if ! _git_commit; then
  echo "FAIL: _git_commit returned non-zero for commit" >&2
  exit 1
fi
[[ ${#COMPREPLY[@]} -gt 0 ]] || { echo "FAIL: no commit completions" >&2; exit 1; }
assert_eq "commit-candidate" "${COMPREPLY[0]}" "bash commit completion"

# Stash push completion with flags/pathspec
COMPREPLY=()
COMP_WORDS=(git stash push --include-untracked -- src -m "")
COMP_CWORD=7
if ! _git_commit; then
  echo "FAIL: _git_commit returned non-zero for stash push" >&2
  exit 1
fi
[[ ${#COMPREPLY[@]} -gt 0 ]] || { echo "FAIL: no stash push completions" >&2; exit 1; }
assert_eq "stash-candidate" "${COMPREPLY[0]}" "bash stash push completion"

# Stash save completion with extra option
COMPREPLY=()
COMP_WORDS=(git stash save -k "")
COMP_CWORD=4
if ! _git_commit; then
  echo "FAIL: _git_commit returned non-zero for stash save" >&2
  exit 1
fi
[[ ${#COMPREPLY[@]} -gt 0 ]] || { echo "FAIL: no stash save completions" >&2; exit 1; }
assert_eq "stash-candidate" "${COMPREPLY[0]}" "bash stash save completion"

echo "bash completion tests passed"
