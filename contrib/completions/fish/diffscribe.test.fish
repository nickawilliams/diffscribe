#!/usr/bin/env fish

function fail
    printf 'FAIL: %s\n' "$argv" >&2
    exit 1
end

set script_dir (dirname (status --current-filename))
set repo_root (cd $script_dir/../../..; pwd)
set tmp_dir (mktemp -d)

function __cleanup --on-event fish_exit
    rm -rf $tmp_dir
end

python3 -c 'import sys
from pathlib import Path

tmp = Path(sys.argv[1])
tmp.mkdir(parents=True, exist_ok=True)

(tmp / "diffscribe").write_text("""#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${DIFFSCRIBE_STASH_COMMIT:-} ]] ; then
  printf 'stash-candidate\n'
else
  printf 'commit-candidate\n'
fi
""")

(tmp / "git").write_text("""#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == stash && $2 == create ]]; then
  echo deadbeef
  exit 0
fi
echo "unexpected git command: $*" >&2
exit 1
""")' $tmp_dir
or fail "failed to create stubs"

chmod +x $tmp_dir/diffscribe $tmp_dir/git
set -x PATH $tmp_dir $PATH

source $repo_root/contrib/completions/fish/diffscribe.fish

function assert_eq --argument-names expected actual label
    if test "$expected" != "$actual"
        printf "FAIL: %s (expected '%s', got '%s')\n" $label $expected $actual >&2
        exit 1
    end
end

# Commit completion
set result (__diffscribe_fish_call 'fe')
assert_eq commit-candidate "$result" "fish commit completion"

# Stash push completion with flags/pathspec
set result (__diffscribe_fish_call '' '--include-untracked' -- src)
assert_eq commit-candidate "$result" "fish stash push completion"

# Stash save completion with option
set result (__diffscribe_fish_call '' -k)
assert_eq commit-candidate "$result" "fish stash save completion"

printf 'fish completion tests passed\n'
