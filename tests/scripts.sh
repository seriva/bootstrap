#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Helper script tests
# Runs workflows/shared/scripts/bs-tree-state and bs-commit against throwaway
# git repos in a temp dir. Every call must leave the working tree unchanged.
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE_STATE="$REPO_DIR/workflows/shared/scripts/bs-tree-state"
COMMIT="$REPO_DIR/workflows/shared/scripts/bs-commit"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-scripts.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# Isolate git from the user's config (hooks path, signing, identity).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset LEFTHOOK_EXCLUDE GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

FAILURES=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILURES=$((FAILURES + 1)); }
check() { # check <label> <command...>: passes when the command succeeds
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}
# Content + mode fingerprint of a directory tree (.git excluded).
tree_hash() {
  (cd "$1" && find . -not -path './.git' -not -path './.git/*' -not -path '*/.git' -not -path '*/.git/*' \
    | LC_ALL=C sort | while IFS= read -r f; do
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        printf '%s %s %s\n' "$f" "$(test -x "$f" && echo x || echo -)" "$(git hash-object --no-filters "$f")"
      else
        printf '%s other\n' "$f"
      fi
    done) | git hash-object --stdin
}
index_hash() { git -C "$1" ls-files -s | git hash-object --stdin; }
head_of() { git -C "$1" rev-parse -q --verify HEAD || echo none; }
# run_in <dir> <cmd...>: run a script from <dir>, capture stdout and exit code, check the tree is unchanged.
OUT="" CODE=0
run_in() {
  local dir="$1" top before
  shift
  top="$(git -C "$dir" rev-parse --show-toplevel)"
  before="$(tree_hash "$top")"
  set +e
  OUT="$(cd "$dir" && "$@" 2>"$SANDBOX/stderr")"
  CODE=$?
  set -e
  if [ "$(tree_hash "$top")" != "$before" ]; then
    fail "working tree changed by: ${*##*/}"
  fi
}
expect_code() { # expect_code <label> <code>
  if [ "$CODE" = "$2" ]; then pass "$1"; else fail "$1 (exit $CODE, want $2: $(head -c 300 "$SANDBOX/stderr"))"; fi
}
expect_eq() { # expect_eq <label> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
expect_ne() { # expect_ne <label> <a> <b>
  if [ "$2" != "$3" ]; then pass "$1"; else fail "$1 (both '$2')"; fi
}
new_repo() { # new_repo [--empty]: print the path of a fresh repo (with one commit unless --empty)
  local r
  r="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
  git -C "$r" init -q
  if [ "${1:-}" != "--empty" ]; then
    echo base > "$r/base.txt"
    git -C "$r" add base.txt
    git -C "$r" commit -q -m init
  fi
  echo "$r"
}
add_hook() { # add_hook <repo> <script body>: install a pre-commit hook
  printf '#!/bin/sh\n%s\n' "$2" > "$1/.git/hooks/pre-commit"
  chmod +x "$1/.git/hooks/pre-commit"
}

echo "== bs-tree-state"
r="$(new_repo)"
run_in "$r" "$TREE_STATE" hash
expect_code "hash: clean tree" 0
h1="$OUT"
run_in "$r" "$TREE_STATE" hash
expect_eq "hash: identical across two calls" "$OUT" "$h1"
run_in "$r" "$TREE_STATE" dirty
expect_code "dirty: clean tree" 0
expect_eq "dirty: clean tree lists nothing" "$OUT" ""

e="$(new_repo --empty)"
run_in "$e" "$TREE_STATE" hash
expect_code "hash: unborn HEAD" 0
run_in "$e" "$TREE_STATE" dirty
expect_code "dirty: unborn HEAD" 0
echo x > "$e/staged.txt"
git -C "$e" add staged.txt
echo y > "$e/staged.txt"
run_in "$e" "$TREE_STATE" hash
expect_code "hash: unborn HEAD with staged file" 0
eh1="$OUT"
echo z > "$e/staged.txt"
run_in "$e" "$TREE_STATE" hash
expect_ne "hash: unborn HEAD sees unstaged edits" "$OUT" "$eh1"
run_in "$e" "$TREE_STATE" dirty
expect_eq "dirty: unborn HEAD lists staged file" "$OUT" "staged.txt"

echo a > "$r/sp ace.txt"
echo a > "$r/café.txt"
run_in "$r" "$TREE_STATE" dirty
expect_eq "dirty: spaces and UTF-8 names listed literally" "$OUT" "$(printf 'café.txt\nsp ace.txt')"
run_in "$r" "$TREE_STATE" hash
h2="$OUT"
expect_ne "hash: sees new untracked files" "$h2" "$h1"
echo b > "$r/sp ace.txt"
run_in "$r" "$TREE_STATE" hash
h3="$OUT"
expect_ne "hash: sees untracked content change" "$h3" "$h2"
chmod +x "$r/sp ace.txt"
run_in "$r" "$TREE_STATE" hash
expect_ne "hash: sees untracked exec-bit change" "$OUT" "$h3"

r="$(new_repo)"
mkdir -p "$r/nested"
git -C "$r/nested" init -q
echo one > "$r/nested/file.txt"
run_in "$r" "$TREE_STATE" hash
n1="$OUT"
echo two > "$r/nested/file.txt"
run_in "$r" "$TREE_STATE" hash
expect_ne "hash: sees changes inside an untracked nested repo" "$OUT" "$n1"

r="$(new_repo)"
echo changed > "$r/base.txt"
run_in "$r" "$TREE_STATE" hash
s1="$OUT"
git -C "$r" add base.txt
run_in "$r" "$TREE_STATE" hash
expect_ne "hash: sees a staged-only change" "$OUT" "$s1"
mkdir -p "$r/sub"
echo u > "$r/sub/untracked.txt"
run_in "$r" "$TREE_STATE" hash
root_hash="$OUT"
run_in "$r" "$TREE_STATE" dirty
root_dirty="$OUT"
run_in "$r/sub" "$TREE_STATE" hash
expect_eq "hash: same from a subdirectory" "$OUT" "$root_hash"
run_in "$r/sub" "$TREE_STATE" dirty
expect_eq "dirty: same root-relative paths from a subdirectory" "$OUT" "$root_dirty"

echo "== bs-tree-state baseline"
r="$(new_repo)"
echo a > "$r/a.txt"
echo b > "$r/b.txt"
echo c > "$r/c.txt"
mkdir -p "$r/d"
git -C "$r" add a.txt b.txt c.txt
git -C "$r" commit -q -m files
echo a2 > "$r/a.txt"
echo c2 > "$r/c.txt"
set -- a.txt b.txt d c.txt
run_in "$r" "$TREE_STATE" baseline -- "$@"
expect_code "baseline: succeeds" 0
b0="$OUT"
expect_eq "baseline: one line per path plus staged" "$(printf '%s\n' "$b0" | wc -l | tr -d ' ')" 5
expect_eq "baseline: directory is non-file" "$(printf '%s\n' "$b0" | sed -n 3p)" "non-file d"
# changed_lines <before> <after>: line numbers that differ
changed_lines() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | sed -n 's/^\([0-9][0-9]*\)c.*/\1/p' | tr '\n' ' '; }
echo a3 > "$r/a.txt"
run_in "$r" "$TREE_STATE" baseline -- "$@"
expect_eq "baseline: edited file changes only its line" "$(changed_lines "$b0" "$OUT")" "1 "
b1="$OUT"
rm "$r/b.txt"
run_in "$r" "$TREE_STATE" baseline -- "$@"
expect_eq "baseline: deleted file changes only its line" "$(changed_lines "$b1" "$OUT")" "2 "
expect_eq "baseline: deleted file is missing" "$(printf '%s\n' "$OUT" | sed -n 2p)" "missing b.txt"
b2="$OUT"
git -C "$r" add c.txt
run_in "$r" "$TREE_STATE" baseline -- "$@"
expect_eq "baseline: staging changes only the staged line" "$(changed_lines "$b2" "$OUT")" "5 "
run_in "$r" "$TREE_STATE" baseline
expect_code "baseline: no paths is a usage error" 2

mkdir -p "$SANDBOX/plain"
OUT="$(cd "$SANDBOX/plain" && "$TREE_STATE" hash 2>/dev/null)" && CODE=0 || CODE=$?
expect_code "not a repo: exit 2" 2

echo "== bs-commit"
r="$(new_repo)"
echo t > "$r/task.txt"
echo s > "$r/stray.txt"
git -C "$r" add task.txt stray.txt
h="$(head_of "$r")" i="$(index_hash "$r")"
run_in "$r" "$COMMIT" -m "feat: task" -- task.txt
expect_code "stray staged path: exit 3" 3
expect_eq "stray staged path: nothing committed" "$(head_of "$r")" "$h"
expect_eq "stray staged path: index untouched" "$(index_hash "$r")" "$i"
check "stray staged path: named on stderr" grep -qx 'stray.txt' "$SANDBOX/stderr"
run_in "$r" "$COMMIT" -m "feat: task" -m "Body explains why." -- task.txt stray.txt
expect_code "allowed paths: exit 0" 0
expect_eq "allowed paths: prints short SHA" "$OUT" "$(git -C "$r" rev-parse --short HEAD)"
expect_eq "two -m: subject and body" "$(git -C "$r" log -1 --format=%B | sed '/^$/d' | tr '\n' '|')" "feat: task|Body explains why.|"

git -C "$r" mv task.txt renamed.txt
run_in "$r" "$COMMIT" -m "refactor: rename" -- renamed.txt
expect_code "rename: old side must be allowed (exit 3)" 3
run_in "$r" "$COMMIT" -m "refactor: rename" -- task.txt renamed.txt
expect_code "rename: both sides allowed (exit 0)" 0

mkdir -p "$r/docs/deep"
echo d > "$r/docs/deep/guide.md"
git -C "$r" add docs
run_in "$r" "$COMMIT" -m "docs: guide" -- docs/
expect_code "docs/ prefix matches nested paths" 0

mkdir -p "$r/sub"
echo s > "$r/sub/f.txt"
git -C "$r" add sub/f.txt
run_in "$r/sub" "$COMMIT" -m "feat: sub" -- sub/f.txt
expect_code "from a subdirectory with root-relative paths" 0

echo "extra" > "$r/extra.txt"
echo more >> "$r/base.txt"
git -C "$r" add base.txt
add_hook "$r" 'git add extra.txt'
h="$(head_of "$r")"
run_in "$r" "$COMMIT" -m "feat: base" -- base.txt
expect_code "hook stages an extra file: exit 4" 4
expect_eq "hook stages an extra file: HEAD restored" "$(head_of "$r")" "$h"
check "hook stages an extra file: named on stderr" grep -qx 'extra.txt' "$SANDBOX/stderr"
check "hook stages an extra file: index not resynced (still staged)" test -n "$(git -C "$r" diff --cached --name-only -- extra.txt)"
git -C "$r" reset -q -- extra.txt

add_hook "$r" 'exit 1'
h="$(head_of "$r")" i="$(index_hash "$r")"
run_in "$r" "$COMMIT" -m "feat: base" -- base.txt
expect_code "failing hook: exit 5" 5
expect_eq "failing hook: HEAD unchanged" "$(head_of "$r")" "$h"
expect_eq "failing hook: index unchanged" "$(index_hash "$r")" "$i"

add_hook "$r" 'printf "%s" "$LEFTHOOK_EXCLUDE" > "$(git rev-parse --git-dir)/seen-exclude"'
run_in "$r" "$COMMIT" -m "feat: base" -- base.txt
expect_eq "default excluded hook is test" "$(cat "$r/.git/seen-exclude")" "test"
echo again >> "$r/base.txt"
git -C "$r" add base.txt
run_in "$r" "$COMMIT" --exclude-hook unit -m "feat: base" -- base.txt
expect_eq "--exclude-hook name reaches LEFTHOOK_EXCLUDE" "$(cat "$r/.git/seen-exclude")" "unit"
rm "$r/.git/hooks/pre-commit"

e="$(new_repo --empty)"
echo one > "$e/one.txt"
git -C "$e" add one.txt
run_in "$e" "$COMMIT" -m "feat: first" -- one.txt
expect_code "first commit in an empty repo" 0
e="$(new_repo --empty)"
echo one > "$e/one.txt"
echo extra > "$e/extra.txt"
git -C "$e" add one.txt
add_hook "$e" 'git add extra.txt'
run_in "$e" "$COMMIT" -m "feat: first" -- one.txt
expect_code "first commit with hook-staged extra: exit 4" 4
expect_eq "first commit undone: no HEAD" "$(head_of "$e")" "none"

add_hook "$r" 'printf "%s" "${LEFTHOOK_EXCLUDE-unset}" > "$(git rev-parse --git-dir)/seen-exclude"'
echo third >> "$r/base.txt"
git -C "$r" add base.txt
run_in "$r" "$COMMIT" --exclude-hook '' -m "feat: base" -- base.txt
expect_code "--exclude-hook '': exit 0" 0
expect_eq "--exclude-hook '': LEFTHOOK_EXCLUDE left unset" "$(cat "$r/.git/seen-exclude")" "unset"
rm "$r/.git/hooks/pre-commit"

h="$(head_of "$r")"
run_in "$r" "$COMMIT" -m "feat: nothing" -- base.txt
expect_code "nothing staged: exit 6" 6
expect_eq "nothing staged: nothing committed" "$(head_of "$r")" "$h"

echo dot > "$r/dot.txt"
git -C "$r" add dot.txt
run_in "$r" "$COMMIT" -m "feat: dot" -- ./dot.txt
expect_code "./ prefix is normalized: exit 0" 0
expect_eq "./ prefix is normalized: commits the file" "$(git -C "$r" show --name-only --format= HEAD)" "dot.txt"
echo dot2 > "$r/dot.txt"
git -C "$r" add dot.txt
h="$(head_of "$r")" i="$(index_hash "$r")"
for bad in "$r/dot.txt" ../dot.txt sub/../dot.txt . ./; do
  run_in "$r" "$COMMIT" -m "feat: dot" -- "$bad"
  expect_code "not repo-root-relative ($bad): exit 2" 2
done
expect_eq "not repo-root-relative: nothing committed" "$(head_of "$r")" "$h"
expect_eq "not repo-root-relative: index untouched" "$(index_hash "$r")" "$i"
git -C "$r" commit -q -m dot2

run_in "$r" "$COMMIT" -- base.txt
expect_code "missing -m: usage error" 2
run_in "$r" "$COMMIT" -m "feat: x"
expect_code "no allowed paths: usage error" 2
OUT="$(cd "$SANDBOX/plain" && "$COMMIT" -m x -- a 2>/dev/null)" && CODE=0 || CODE=$?
expect_code "not a repo: exit 2" 2

echo "== bs-commit --only"
r="$(new_repo)"
echo user > "$r/user.txt"
git -C "$r" add user.txt
echo task > "$r/task.txt"
git -C "$r" add task.txt
run_in "$r" "$COMMIT" --only -m "feat: task" -- task.txt
expect_code "--only: exit 0" 0
expect_eq "--only: commits only the task file" "$(git -C "$r" show --name-only --format= HEAD)" "task.txt"
expect_eq "--only: user's staged change stays staged" "$(git -C "$r" diff --cached --name-only)" "user.txt"

echo task2 > "$r/task.txt"
git -C "$r" add task.txt
# The hook "formats" task.txt in the commit's index only, so the working tree stays untouched.
add_hook "$r" 'blob=$(printf fixed | git hash-object -w --stdin) && git update-index --cacheinfo "100644,$blob,task.txt"'
run_in "$r" "$COMMIT" --only -m "feat: task" -- task.txt
expect_code "--only with hook rewrite: exit 0" 0
expect_eq "--only with hook rewrite: commit has the hook's fix" "$(git -C "$r" show HEAD:task.txt)" "fixed"
check "--only with hook rewrite: index matches HEAD for the task file" git -C "$r" diff --cached --quiet -- task.txt
expect_eq "--only with hook rewrite: user's staged change still staged" "$(git -C "$r" diff --cached --name-only)" "user.txt"
rm "$r/.git/hooks/pre-commit"

mkdir -p "$r/sub"
echo s > "$r/sub/f.txt"
git -C "$r" add sub/f.txt
run_in "$r/sub" "$COMMIT" --only -m "feat: sub" -- sub/f.txt
expect_code "--only from a subdirectory with root-relative paths" 0
expect_eq "--only from a subdirectory: commits the file" "$(git -C "$r" show --name-only --format= HEAD)" "sub/f.txt"

mkdir -p "$r/docs"
echo d > "$r/docs/a.md"
h="$(head_of "$r")"
run_in "$r" "$COMMIT" --only -m "docs: a" -- docs/
expect_code "--only rejects a directory prefix: exit 2" 2
expect_eq "--only rejects a directory prefix: nothing committed" "$(head_of "$r")" "$h"

run_in "$r" "$COMMIT" --only -m "docs: a" -- docs/a.md
expect_code "--only with an unstaged untracked file: exit 2" 2
check "--only with an unstaged untracked file: named on stderr" grep -q 'docs/a.md' "$SANDBOX/stderr"
expect_eq "--only with an unstaged untracked file: nothing committed" "$(head_of "$r")" "$h"
run_in "$r" "$COMMIT" --only -m "feat: nothing" -- sub/f.txt
expect_code "--only with a path matching HEAD: exit 6" 6
expect_eq "--only with a path matching HEAD: nothing committed" "$(head_of "$r")" "$h"
expect_eq "--only with a path matching HEAD: user's staged change still staged" "$(git -C "$r" diff --cached --name-only)" "user.txt"
echo gone > "$r/gone.txt"
git -C "$r" add gone.txt
git -C "$r" commit -q --only -m gone -- gone.txt
git -C "$r" rm -q gone.txt
run_in "$r" "$COMMIT" --only -m "chore: remove gone" -- gone.txt
expect_code "--only with a staged deletion: exit 0" 0
expect_eq "--only with a staged deletion: commits the deletion" "$(git -C "$r" show --name-status --format= HEAD)" "$(printf 'D\tgone.txt')"

e="$(new_repo --empty)"
echo a > "$e/a.txt"
echo b > "$e/b.txt"
git -C "$e" add a.txt b.txt
run_in "$e" "$COMMIT" --only -m "feat: a" -- a.txt
expect_code "--only on an unborn HEAD: exit 0" 0
expect_eq "--only on an unborn HEAD: commits only the task file" "$(git -C "$e" show --name-only --format= HEAD)" "a.txt"
expect_eq "--only on an unborn HEAD: other staged file stays staged" "$(git -C "$e" diff --cached --name-only)" "b.txt"

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "[FAIL] $FAILURES check(s) failed."
  exit 1
fi
echo "[PASS] All script checks passed."
