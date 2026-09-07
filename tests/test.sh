#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PURE_BASH_NO_SETUP=1
# shellcheck source=../pure.bash
source "$ROOT/pure.bash"

failures=0
assert_eq() {
    local expected=$1 actual=$2 label=$3
    if [[ $expected != "$actual" ]]; then
        printf 'not ok - %s\n  expected: %q\n  actual:   %q\n' "$label" "$expected" "$actual"
        failures=$((failures + 1))
    else
        printf 'ok - %s\n' "$label"
    fi
}

assert_eq '0s' "$(__pure_human_time 0)" 'human time: zero'
assert_eq '59s' "$(__pure_human_time 59)" 'human time: seconds'
assert_eq '1m 5s' "$(__pure_human_time 65)" 'human time: minutes'
assert_eq '1d 21h 56m 32s' "$(__pure_human_time 165392)" 'human time: long duration'

assert_eq '31' "$(__pure_color_code red)" 'color: named'
assert_eq '38;5;242' "$(__pure_color_code 242)" 'color: 256 palette'
assert_eq '38;2;66;66;66' "$(__pure_color_code '#424242')" 'color: truecolor'

old_home=$HOME
old_pwd=$PWD
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
HOME=$tmp
mkdir -p "$tmp/a/b"
cd "$tmp/a/b"
assert_eq '~/a/b' "$(__pure_display_path)" 'path: home abbreviation'
HOME=$old_home
cd "$old_pwd"

repo="$tmp/repo"
mkdir -p "$repo"
command git -C "$repo" init -q
command git -C "$repo" config user.email test@example.com
command git -C "$repo" config user.name Test
printf 'one\n' > "$repo/file"
command git -C "$repo" add file
command git -C "$repo" commit -qm initial

cd "$repo"
assert_eq '' "$(__pure_git_dirty 0 1)" 'git: clean'
printf 'two\n' >> file
assert_eq '*' "$(__pure_git_dirty 0 1)" 'git: dirty simple'
assert_eq '*' "$(__pure_git_dirty 1 1)" 'git: detailed unstaged'
command git add file
assert_eq '+' "$(__pure_git_dirty 1 1)" 'git: detailed staged'
printf 'new\n' > untracked
assert_eq '+?' "$(__pure_git_dirty 1 1)" 'git: detailed staged + untracked'
assert_eq '+' "$(__pure_git_dirty 1 0)" 'git: detailed excludes untracked'

__pure_git_context
assert_eq "$repo" "$__PURE_GIT_TOP" 'git: top-level'
current_branch=$(command git branch --show-current)
assert_eq "$current_branch" "$__PURE_GIT_BRANCH" 'git: branch'

# Remote refresh: the local branch is one commit ahead while a second clone
# advances the configured upstream. The private fetch should report both arrows
# and leave no refs/pure-bash ref behind.
origin="$tmp/origin.git"
remote_work="$tmp/remote-work"
command git init -q --bare "$origin"
command git -C "$repo" remote add origin "$origin"
command git -C "$repo" push -qu origin "HEAD:refs/heads/$current_branch"
command git -C "$repo" branch --set-upstream-to="origin/$current_branch" >/dev/null
printf 'local-only\n' >> file
command git -C "$repo" add file
command git -C "$repo" commit -qm local-ahead
command git clone -q "$origin" "$remote_work"
command git -C "$remote_work" config user.email test@example.com
command git -C "$remote_work" config user.name Test
printf 'remote-only\n' > "$remote_work/remote"
command git -C "$remote_work" add remote
command git -C "$remote_work" commit -qm remote-ahead
command git -C "$remote_work" push -q origin "$current_branch"
assert_eq "${PURE_GIT_DOWN_ARROW}${PURE_GIT_UP_ARROW}" "$(__pure_fetch_upstream_arrows "$current_branch")" 'git: private fetch arrows'
if command git show-ref | grep -q 'refs/pure-bash/'; then
    printf 'not ok - git: private fetch ref cleanup\n'
    failures=$((failures + 1))
else
    printf 'ok - git: private fetch ref cleanup\n'
fi

# Capture helper must preserve the user's last status for pre-existing
# PROMPT_COMMAND hooks while retaining it for Pure's renderer.
set +e
(false)
__pure_capture_status
capture_rc=$?
set -e
assert_eq '1' "$capture_rc" 'prompt hook: preserves exit status'
assert_eq '1' "$__PURE_LAST_STATUS" 'prompt hook: stores exit status'
unset __PURE_LAST_STATUS

if (( failures > 0 )); then
    printf '\n%d test(s) failed.\n' "$failures" >&2
    exit 1
fi
printf '\nall tests passed\n'
