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
PLAN_STATE="$REPO_DIR/workflows/shared/scripts/bs-plan-state"
REVIEW_STATE="$REPO_DIR/workflows/shared/scripts/bs-review-state"
PLAN_BRANCH="$REPO_DIR/workflows/shared/scripts/bs-plan-branch"
DIFF_TARGET="$REPO_DIR/workflows/shared/scripts/bs-diff-target"
WORKTREE="$REPO_DIR/workflows/shared/scripts/bs-worktree"
PR_CI="$REPO_DIR/workflows/shared/scripts/bs-pr-ci"
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
expect_next() { # expect_next <label> <text>: the last stderr line is "next: ..." containing <text>
  local last
  last="$(tail -n 1 "$SANDBOX/stderr")"
  case "$last" in "next: "*"$2"*) pass "$1" ;; *) fail "$1 (last stderr line: '$last')" ;; esac
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

# Fake gh: logs each call to $FAKE_GH/calls and serves real JSON fixtures through the
# script's actual --json field filter and --jq expression (via jq if installed, else Python 3):
#   pr view: pr-view.json (or pr-view.err, exit 1); pr edit --body-file: copies the file to
#   pr-edit.body and into pr-view.json's body (or exits with pr-edit.rc);
#   pr checks --watch: prints pr-checks.<call#>.out (else pr-checks.out) to stderr and exits with
#   pr-checks.<call#>.rc (else pr-checks.rc, else 0); pr checks --json: pr-checks.json, else exit 1;
#   pr ready: exits with pr-ready.rc, else 0.
FAKE_GH="$SANDBOX/fake-gh"
mkdir -p "$SANDBOX/bin" "$FAKE_GH"
cat > "$SANDBOX/bin/gh" <<'EOF'
#!/bin/sh
set -eu
d="$FAKE_GH"
printf '%s\n' "$*" >> "$d/calls"
cmd="$1 $2"
shift 2
fields="" jq_expr="" body_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) fields="$2"; shift 2 ;;
    --jq|-q) jq_expr="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
render_json() {
  python3 - "$1" "$fields" "$jq_expr" <<'PY'
import json, re, shutil, subprocess, sys
path, fields_csv, expr = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
if fields_csv:
    want = set(fields_csv.split(","))
    filt = lambda o: {k: v for k, v in o.items() if k in want}
    data = [filt(x) for x in data] if isinstance(data, list) else filt(data)
if shutil.which("jq"):
    r = subprocess.run(["jq", "-r", expr], input=json.dumps(data), text=True, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr); sys.exit(r.returncode)
    sys.stdout.write(r.stdout); sys.exit(0)
# Minimal jq evaluator for the script expressions when jq is absent; fails loudly on unknown syntax.
def fmt(v):
    if v is None: return "null"
    if isinstance(v, bool): return "true" if v else "false"
    return str(v)
def eval_interp(sub, obj):
    m = re.fullmatch(r'\.([A-Za-z_][A-Za-z0-9_]*)', sub)
    if m:
        return fmt(obj[m.group(1)])
    m = re.fullmatch(r'\[\.([A-Za-z_][A-Za-z0-9_]*)\[\]\.([A-Za-z_][A-Za-z0-9_]*)\s*\|\s*select\(endswith\("([^"]*)"\)\)\]\s*\|\s*length', sub)
    if m:
        arr, key, suf = m.groups()
        return str(sum(1 for it in obj[arr] if str(it[key]).endswith(suf)))
    sys.exit(f"fake gh: unsupported --jq interpolation: {sub}")
def eval_tpl(tpl, obj):
    out, i, n = [], 0, len(tpl)
    while i < n:
        if tpl[i] == '\\' and i + 1 < n:
            c = tpl[i + 1]
            if c == '(':
                depth, j = 1, i + 2
                while j < n and depth:
                    if tpl[j] == '(': depth += 1
                    elif tpl[j] == ')': depth -= 1
                    j += 1
                out.append(eval_interp(tpl[i + 2:j - 1], obj))
                i = j; continue
            out.append({'t': '\t', 'n': '\n', '"': '"', '\\': '\\'}.get(c, c))
            i += 2; continue
        out.append(tpl[i]); i += 1
    return "".join(out)
items = data if expr.startswith(".[] | ") else [data]
body = expr[len(".[] | "):] if expr.startswith(".[] | ") else expr
if not (len(body) >= 2 and body[0] == '"' and body[-1] == '"'):
    sys.exit(f"fake gh: unsupported --jq expression: {expr}")
for it in items:
    print(eval_tpl(body[1:-1], it))
PY
}
case "$cmd" in
  "pr view")
    if [ -f "$d/pr-view.err" ]; then cat "$d/pr-view.err" >&2; exit 1; fi
    render_json "$d/pr-view.json" ;;
  "pr edit")
    if [ -f "$d/pr-edit.rc" ]; then echo "fake gh: pr edit failed" >&2; exit "$(cat "$d/pr-edit.rc")"; fi
    cp "$body_file" "$d/pr-edit.body"
    python3 - "$d/pr-view.json" "$body_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["body"] = open(sys.argv[2]).read()
json.dump(data, open(sys.argv[1], "w"))
PY
    ;;
  "pr checks")
    if [ -n "$fields" ]; then
      [ -f "$d/pr-checks.json" ] || { echo "no pull requests found" >&2; exit 1; }
      render_json "$d/pr-checks.json"; exit 0
    fi
    n=$(($(cat "$d/pr-checks.count" 2>/dev/null || echo 0) + 1))
    echo "$n" > "$d/pr-checks.count"
    for f in "pr-checks.$n" pr-checks; do [ -f "$d/$f.out" ] && { cat "$d/$f.out" >&2; break; }; done
    for f in "pr-checks.$n" pr-checks; do [ -f "$d/$f.rc" ] && exit "$(cat "$d/$f.rc")"; done
    exit 0 ;;
  "pr ready")
    if [ -f "$d/pr-ready.rc" ]; then echo "fake gh: pr ready failed" >&2; exit "$(cat "$d/pr-ready.rc")"; fi ;;
  *) echo "fake gh: unexpected call: $cmd $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$SANDBOX/bin/gh"
export FAKE_GH
GH_PATH="$SANDBOX/bin:$PATH"
fake_gh_reset() { rm -rf "$FAKE_GH"; mkdir -p "$FAKE_GH"; }
gh_calls() { if [ -f "$FAKE_GH/calls" ]; then grep -c "^$1" "$FAKE_GH/calls" || true; else echo 0; fi; }

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
ln -s a "$r/link"
run_in "$r" "$TREE_STATE" hash
h4="$OUT"
ln -sfn b "$r/link"
run_in "$r" "$TREE_STATE" hash
expect_ne "hash: sees untracked symlink retarget" "$OUT" "$h4"

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

r="$(new_repo)"
run_in "$r" "$TREE_STATE" hash
c1="$OUT"
git -C "$r" commit -q --allow-empty -m "empty"
run_in "$r" "$TREE_STATE" hash
expect_ne "hash: sees a new commit on a clean tree" "$OUT" "$c1"

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
expect_next "stray staged path: next action restores it" "git restore --staged"
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
expect_next "hook stages an extra file: next action stops" "stop and report"
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

add_hook "$r" 'touch "$(git rev-parse --git-dir)/hook-ran"'
echo long >> "$r/base.txt"
git -C "$r" add base.txt
h="$(head_of "$r")" i="$(index_hash "$r")"
long_subject="feat(some-plan-slug): $(printf 'x%.0s' $(seq 1 51))" # 73 chars
run_in "$r" "$COMMIT" -m "$long_subject" -- base.txt
expect_code "subject over 72 chars: exit 2" 2
expect_eq "subject over 72 chars: nothing committed" "$(head_of "$r")" "$h"
expect_eq "subject over 72 chars: index unchanged" "$(index_hash "$r")" "$i"
check "subject over 72 chars: no hook ran" test ! -e "$r/.git/hook-ran"
check "subject over 72 chars: length on stderr" grep -q 'subject is 73 chars' "$SANDBOX/stderr"
expect_next "subject over 72 chars: next action fixes the call" "fix the call"
run_in "$r" "$COMMIT" -m "${long_subject%x}" -m "$long_subject in the body is fine" -- base.txt
expect_code "subject of exactly 72 chars (long body): exit 0" 0
rm -f "$r/.git/hooks/pre-commit" "$r/.git/hook-ran"

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

echo "== bs-plan-state"
# write_plan <file> <status line> <body>: write a plan file with a Status line and a body
write_plan() {
  mkdir -p "$(dirname "$1")"
  printf '# Plan\n\n**Version:** continuous  \n%s\n\n---\n\n%s\n' "$2" "$3" > "$1"
}
TASKS_OPEN='## Implementation Tasks

```markdown
- [ ] Task 9.9: example inside a fence
```

### Phase 1: Core
- [x] Task 1.1: done
  - Files: `a`
- [x] Task 1.2: done

### Phase 2: More
- [x] Task 2.1: done
- [ ] Task 2.2: pending

### Phase 3: Last
- [ ] Task 3.1: pending

## Notes
- [ ] Task 8.1: not a task, after the section'
TASKS_DONE='## Implementation Tasks

### Phase 1: Core
- [x] Task 1.1: done
- [X] Task 1.2: done'
r="$(new_repo)"
run_in "$r" "$PLAN_STATE" active
expect_code "active: no plans/ dir exits 0" 0
expect_eq "active: no plans/ dir prints nothing" "$OUT" ""
write_plan "$r/plans/a-plan.md" '**Status:** In Progress  ' "$TASKS_OPEN"
write_plan "$r/plans/v1.0.0/b-plan.md" '**Status:** Draft' "$TASKS_DONE"
write_plan "$r/plans/c-plan.md" '**Status:** Completed (2026-01-01)' "$TASKS_OPEN"
write_plan "$r/plans/archive/d-plan.md" '**Status:** In Progress' "$TASKS_OPEN"
write_plan "$r/plans/template.md" '**Status:** Draft' "$TASKS_OPEN"
write_plan "$r/plans/follow-ups.md" '**Status:** Draft' ""
write_plan "$r/plans/roadmap.md" '**Status:** Draft' ""
write_plan "$r/plans/e-plan.md" '**Status:** Draft' 'No tasks yet.'
run_in "$r" "$PLAN_STATE" active
expect_eq "active: active plans only, sorted" "$OUT" "$(printf 'plans/a-plan.md\nplans/e-plan.md\nplans/v1.0.0/b-plan.md')"
mkdir -p "$r/sub"
run_in "$r/sub" "$PLAN_STATE" active
expect_eq "active: same repo-root-relative paths from a subdirectory" "$OUT" "$(printf 'plans/a-plan.md\nplans/e-plan.md\nplans/v1.0.0/b-plan.md')"
run_in "$r" "$PLAN_STATE" plans/a-plan.md
expect_eq "open: first pending phase, counts skip fences and later sections" "$OUT" "open 2 3/5"
run_in "$r/sub" "$PLAN_STATE" plans/a-plan.md
expect_eq "open: plan path is repo-root-relative from a subdirectory" "$OUT" "open 2 3/5"
run_in "$r" "$PLAN_STATE" plans/v1.0.0/b-plan.md
expect_eq "finishing: every task checked" "$OUT" "finishing 2/2"
run_in "$r" "$PLAN_STATE" plans/c-plan.md
expect_eq "closed: Completed status wins over unchecked tasks" "$OUT" "closed"
run_in "$r" "$PLAN_STATE" plans/archive/d-plan.md
expect_eq "closed: under plans/archive/" "$OUT" "closed"
run_in "$r" "$PLAN_STATE" plans/e-plan.md
expect_code "no task boxes: exit 2" 2
run_in "$r" "$PLAN_STATE" plans/missing-plan.md
expect_code "missing plan file: exit 2" 2
printf '# Plan\n\n- [ ] Task 1.1: x\n' > "$r/plans/f-plan.md"
run_in "$r" "$PLAN_STATE" plans/f-plan.md
expect_code "no Status line: exit 2" 2
run_in "$r" "$PLAN_STATE"
expect_code "no argument: usage error" 2

echo "== bs-review-state"
r="$(new_repo)"
PH='*Automated AI review & fix cycle in progress...*'
# pr_record <state> <isDraft> <fix commits> <body>: writes real gh pr view JSON
pr_record() {
  fake_gh_reset
  python3 - "$1" "$2" "$3" "$4" "$FAKE_GH/pr-view.json" <<'PY'
import json, sys
state, draft, fixes, body, out = sys.argv[1], sys.argv[2] == "true", int(sys.argv[3]), sys.argv[4], sys.argv[5]
commits = [{"messageHeadline": "feat(plan): implement phase (Task 1.1)"}]
commits += [{"messageHeadline": "fix(plan): address review feedback"}] * fixes
json.dump({"state": state, "isDraft": draft, "baseRefName": "feat/base", "body": body, "commits": commits, "extra": 1}, open(out, "w"))
PY
}
review_state() { run_in "$r" env PATH="$GH_PATH" "$REVIEW_STATE" "$@"; }
fake_gh_reset
echo 'no pull requests found for branch "feat/x"' > "$FAKE_GH/pr-view.err"
review_state feat/x
expect_eq "no PR: none" "$OUT" "none"
expect_code "no PR: exit 0" 0
fake_gh_reset
echo 'HTTP 502: bad gateway' > "$FAKE_GH/pr-view.err"
review_state feat/x
expect_code "gh failure: exit 3" 3
check "gh failure: error passed through" grep -q 'bad gateway' "$SANDBOX/stderr"
expect_next "gh failure: next action retries once" "retry once"
pr_record MERGED false 0 "**Gate:** PASSED"
review_state feat/x
expect_eq "merged" "$OUT" "merged feat/base"
check "one gh pr view call for the branch with --json" grep -q '^pr view feat/x --json state,isDraft,baseRefName,body,commits --jq ' "$FAKE_GH/calls"
pr_record CLOSED true 0 "$PH"
review_state feat/x
expect_eq "closed beats a placeholder" "$OUT" "closed feat/base"
pr_record OPEN true 0 "## Review Status: $PH"
review_state feat/x
expect_eq "draft with placeholder: in-review" "$OUT" "in-review feat/base"
pr_record OPEN true 1 "## Review Status: $PH"
review_state feat/x
expect_eq "placeholder and a fix commit: fix-used" "$OUT" "fix-used feat/base"
pr_record OPEN true 1 "$(printf '## Review Status\n**Gate:** BLOCKED_BY_DEFECTS (2 passes)')"
review_state feat/x
expect_eq "draft gated: BLOCKED_BY_DEFECTS" "$OUT" "gated:BLOCKED_BY_DEFECTS feat/base"
pr_record OPEN true 0 "**Gate**: BLOCKED_BY_CI"
review_state feat/x
expect_eq "draft gated: BLOCKED_BY_CI (**Gate**: form)" "$OUT" "gated:BLOCKED_BY_CI feat/base"
pr_record OPEN true 0 "**Gate:** PASSED"
review_state feat/x
expect_eq "draft gated: PASSED" "$OUT" "gated:PASSED feat/base"
pr_record OPEN true 0 "$(printf '**Gate:** PASSED (1 pass)\n\n```\n**Gate:** BLOCKED_BY_CI (quoted probe output)\n```')"
review_state feat/x
expect_eq "later Gate line quoted in the report does not override the first" "$OUT" "gated:PASSED feat/base"
pr_record OPEN true 0 "**Gate:** BLOCKED_BY_CI: test"
review_state feat/x
expect_eq "draft gated: BLOCKED_BY_CI with a colon detail" "$OUT" "gated:BLOCKED_BY_CI feat/base"
pr_record OPEN true 0 "**Gate:** PASSED (1 pass; was BLOCKED_BY_DEFECTS)"
review_state feat/x
expect_eq "gate words in the detail do not override the gate" "$OUT" "gated:PASSED feat/base"
pr_record OPEN true 0 "**Gate:** pending"
review_state feat/x
expect_eq "unknown gate word: draft" "$OUT" "draft feat/base"
pr_record OPEN true 0 "$(printf '**Gate:** PASSED\n\nNotes mention BLOCKED_BY_CI in prose.')"
review_state feat/x
expect_eq "BLOCKED_BY_CI in prose does not override PASSED Gate" "$OUT" "gated:PASSED feat/base"
pr_record OPEN true 0 "$(printf 'Notes mention BLOCKED_BY_CI without any Gate line.')"
review_state feat/x
expect_eq "BLOCKED_BY_CI without a Gate line: draft" "$OUT" "draft feat/base"
pr_record OPEN false 0 "**Gate:** PASSED"
review_state feat/x
expect_eq "not a draft: ready" "$OUT" "ready feat/base"
pr_record OPEN true 0 "Opened by hand. PASSED in prose is not a Gate."
review_state feat/x
expect_eq "draft without placeholder or Gate: draft" "$OUT" "draft feat/base"
review_state
expect_code "no branch: usage error" 2

echo "== bs-review-state set"
printf '### Findings\n- High: none\n<details>probes</details>\n' > "$SANDBOX/report.md"
pr_record OPEN true 0 "$(printf '## Summary\nDid things.\n\n## Review Status: %s\n\n## Tail\nkept' "$PH")"
review_state set feat/x PASSED "2 passes" "$SANDBOX/report.md"
expect_code "set: placeholder replaced, exit 0" 0
expect_eq "set: prints the state read back" "$OUT" "gated:PASSED feat/base"
check "set: Gate line written in the marker format" grep -qxF '**Gate:** PASSED (2 passes)' "$FAKE_GH/pr-edit.body"
check "set: heading without the placeholder" grep -qx '## Review Status' "$FAKE_GH/pr-edit.body"
check_not() { ! "$@"; }
check "set: placeholder gone" check_not grep -qF "$PH" "$FAKE_GH/pr-edit.body"
check "set: report inserted" grep -qxF '<details>probes</details>' "$FAKE_GH/pr-edit.body"
check "set: rest of the body kept" sh -c 'grep -qx "Did things." "$1" && grep -qx kept "$1"' _ "$FAKE_GH/pr-edit.body"
review_state set feat/x BLOCKED_BY_CI "2 passes; failing: test, lint"
expect_eq "set: Gate line rewritten to BLOCKED_BY_CI" "$OUT" "gated:BLOCKED_BY_CI feat/base"
expect_eq "set: still one Gate line" "$(grep -c 'Gate:' "$FAKE_GH/pr-edit.body")" "1"
check "set: report kept on rewrite" grep -qxF '<details>probes</details>' "$FAKE_GH/pr-edit.body"
review_state set feat/x PASSED "x" "$SANDBOX/report.md"
expect_code "set: report with an existing Gate line: usage error" 2
pr_record OPEN true 0 "## Review Status: $PH"
review_state set feat/x PASSED "1 pass"
expect_code "set: placeholder without a report: usage error" 2
review_state set feat/x LGTM "1 pass" "$SANDBOX/report.md"
expect_code "set: unknown gate: usage error" 2
pr_record OPEN true 0 "Opened by hand."
review_state set feat/x PASSED "1 pass"
expect_code "set: neither placeholder nor Gate line: exit 4" 4
expect_next "set: neither placeholder nor Gate line: next action stops" "stop and report"
expect_eq "set: nothing edited" "$(gh_calls 'pr edit')" "0"
pr_record OPEN true 0 "## Review Status: $PH"
echo 1 > "$FAKE_GH/pr-edit.rc"
review_state set feat/x PASSED "1 pass" "$SANDBOX/report.md"
expect_code "set: gh pr edit failure: exit 3" 3
mkdir -p "$SANDBOX/rs-tmp"
printf '### Findings\n- Mentioned BLOCKED_BY_CI in probe output\n' > "$SANDBOX/report-ci-prose.md"
pr_record OPEN true 0 "$(printf '## Review Status\n\n%s\n' "$PH")"
run_in "$r" env PATH="$GH_PATH" TMPDIR="$SANDBOX/rs-tmp" "$REVIEW_STATE" set feat/x PASSED "1 pass" "$SANDBOX/report-ci-prose.md"
expect_code "set: separate-line placeholder + prose BLOCKED_BY_CI: exit 0" 0
expect_eq "set: prose BLOCKED_BY_CI still reads back PASSED" "$OUT" "gated:PASSED feat/base"
expect_eq "set: separate-line placeholder does not duplicate Review Status heading" "$(grep -c '^## Review Status' "$FAKE_GH/pr-edit.body")" "1"
check "set: no leaked temp files in TMPDIR" test -z "$(ls -A "$SANDBOX/rs-tmp")"
printf '### Findings\n<details>\n\n```\n**Gate:** BLOCKED_BY_CI (probe)\n```\n</details>\n' > "$SANDBOX/report-gate-quote.md"
pr_record OPEN true 0 "## Review Status: $PH"
review_state set feat/x PASSED "1 pass" "$SANDBOX/report-gate-quote.md"
expect_eq "set: report quoting a Gate line still reads back PASSED" "$OUT" "gated:PASSED feat/base"
pr_record OPEN true 0 "$(printf '## Review Status\n\nold notes\n\n## Checklist\n%s\n' "$PH")"
review_state set feat/x PASSED "1 pass" "$SANDBOX/report.md"
expect_eq "set: placeholder under another heading gets its own Review Status heading" \
  "$(grep -c '^## Review Status' "$FAKE_GH/pr-edit.body")" "2"
check "set: new heading follows the other heading" \
  sh -c 'sed -n "/^## Checklist/,\$p" "$1" | grep -qx "## Review Status"' _ "$FAKE_GH/pr-edit.body"

echo "== bs-plan-branch"
# Origin with main, a release branch, and committed plans; the clone is what the script runs in.
origin="$SANDBOX/plan-origin.git"
git init -q --bare "$origin"
r="$(new_repo)"
git -C "$r" branch -M main
git -C "$r" remote add origin "$origin"
mkdir -p "$r/plans"
printf '# Demo\n\n**Status:** Draft  \n**Version:** continuous  \n\nBody line.  \n' > "$r/plans/demo-plan.md"
printf '# Tick\n\n**Status:** In Progress  \n**Base branch:** `main`  \n\nBody.\n' > "$r/plans/tick-plan.md"
printf '# None\n\nNo status here.\n' > "$r/plans/nostatus-plan.md"
git -C "$r" add plans; git -C "$r" commit -q -m plans
git -C "$r" push -q -u origin main
git -C "$r" remote set-head origin main
git -C "$r" checkout -q -b release/1.x
printf '# Rel\n\n**Status:** Draft\n**Base branch:** `gone`  \n**Base branch:** stale  \n' > "$r/plans/rel-plan.md"
git -C "$r" add plans; git -C "$r" commit -q -m rel
git -C "$r" push -q -u origin release/1.x
git -C "$r" checkout -q main
pb_field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
plan_branch() { # plan_branch <plan-file>: run from the repo, capturing stdout and exit code
  set +e
  OUT="$(cd "$r" && "$PLAN_BRANCH" "$@" 2>"$SANDBOX/stderr")"
  CODE=$?
  set -e
}
plan_branch plans/demo-plan.md
expect_code "new plan: exit 0" 0
expect_eq "new plan: branch from slug" "$(pb_field PLAN_BRANCH)" "feat/demo"
expect_eq "new plan: base is the starting main" "$(pb_field BASE_BRANCH)" "main"
expect_eq "new plan: created" "$(pb_field CREATED)" "true"
expect_eq "new plan: on the plan branch" "$(git -C "$r" symbolic-ref --short HEAD)" "feat/demo"
expect_eq "new plan: header rewritten, body untouched" "$(cat "$r/plans/demo-plan.md")" \
  "$(printf '# Demo\n\n**Status:** In Progress  \n**Base branch:** main  \n**Version:** continuous  \n\nBody line.  ')"
expect_eq "new plan: commit subject" "$(git -C "$r" log -1 --format=%s)" "docs(demo): start plan"
expect_eq "new plan: COMMITTED is HEAD" "$(pb_field COMMITTED)" "$(git -C "$r" rev-parse --short HEAD)"
expect_eq "new plan: pushed with tracking" "$(git -C "$r" rev-parse origin/feat/demo)" "$(git -C "$r" rev-parse HEAD)"
expect_eq "new plan: tree clean afterwards" "$(git -C "$r" status --porcelain)" ""
head_before="$(git -C "$r" rev-parse HEAD)"
plan_branch plans/demo-plan.md
expect_eq "rerun: nothing to commit" "$(pb_field COMMITTED)" "none"
expect_eq "rerun: not created" "$(pb_field CREATED)" "false"
expect_eq "rerun: no new commit" "$(git -C "$r" rev-parse HEAD)" "$head_before"
git -C "$r" checkout -q -b fix/other main
plan_branch plans/demo-plan.md
expect_eq "from a feature branch: checks out the plan branch" "$(git -C "$r" symbolic-ref --short HEAD)" "feat/demo"
expect_eq "from a feature branch: recorded base wins" "$(pb_field BASE_BRANCH)" "main"
expect_eq "from a feature branch: START_BRANCH recorded" "$(pb_field START_BRANCH)" "fix/other"
echo junk > "$r/junk.txt"
plan_branch plans/demo-plan.md
expect_code "dirty tree: exit 4" 4
check "dirty tree: paths listed" grep -q 'junk.txt' "$SANDBOX/stderr"
expect_next "dirty tree: next action asks the user" "ask the user to commit or clean"
expect_eq "dirty tree: HEAD unchanged" "$(git -C "$r" rev-parse HEAD)" "$head_before"
rm "$r/junk.txt"
git -C "$r" checkout -q main
git -C "$r" worktree add -q "$SANDBOX/demo-wt" feat/demo
plan_branch plans/demo-plan.md
expect_code "plan branch held by another worktree: exit 2" 2
expect_next "plan branch held by another worktree: next action frees the branch" "continue in that worktree or free the branch"
git -C "$r" worktree remove "$SANDBOX/demo-wt"
git -C "$r" checkout -q release/1.x
plan_branch plans/rel-plan.md
expect_eq "release start with a stale base: base is the release branch" "$(pb_field BASE_BRANCH)" "release/1.x"
expect_eq "stale base lines replaced by one" "$(grep -c '^\*\*Base branch:\*\*' "$r/plans/rel-plan.md")" "1"
check "stale base replaced after Status" grep -qxF '**Base branch:** release/1.x  ' "$r/plans/rel-plan.md"
check "Draft without trailing spaces flips too" grep -qxF '**Status:** In Progress  ' "$r/plans/rel-plan.md"
git -C "$r" checkout -q main
plan_branch plans/tick-plan.md
expect_eq "matching backticked base: kept, nothing committed" "$(pb_field COMMITTED)" "none"
check "matching backticked base: line kept as written" grep -qxF '**Base branch:** `main`  ' "$r/plans/tick-plan.md"
git -C "$r" checkout -q -b topic/side main
printf '# Side\n\n**Status:** Draft\n' > "$r/plans/side-plan.md"
git -C "$r" add plans; git -C "$r" commit -q -m side
plan_branch plans/side-plan.md
expect_code "plan only on a feature branch: exit 2" 2
check "plan only on a feature branch: no plan branch created" check_not git -C "$r" show-ref --verify --quiet refs/heads/feat/side
expect_eq "plan only on a feature branch: still on the start branch" "$(git -C "$r" symbolic-ref --short HEAD)" "topic/side"
plan_branch plans/nostatus-plan.md
expect_code "no Status line: exit 2" 2
check "no Status line: no branch created" check_not git -C "$r" show-ref --verify --quiet refs/heads/feat/nostatus
plan_branch plans/missing-plan.md
expect_code "missing plan file: exit 2" 2
plan_branch "$r/plans/demo-plan.md"
expect_code "absolute path inside repo: exit 0" 0
expect_eq "absolute path inside repo: branch resolved" "$(pb_field PLAN_BRANCH)" "feat/demo"
outside_plan="$SANDBOX/outside-plan.md"
printf '# Outside\n\n**Status:** Draft\n' > "$outside_plan"
plan_branch "$outside_plan"
expect_code "absolute path outside repo: exit 2" 2
check "absolute path outside repo: no branch created" check_not git -C "$r" show-ref --verify --quiet refs/heads/feat/outside
git -C "$r" checkout -q main
git -C "$r" checkout -q -b feat/localonly
printf '# LocalOnly\n\n**Status:** In Progress  \n**Base branch:** main  \n' > "$r/plans/localonly-plan.md"
git -C "$r" add plans/localonly-plan.md; git -C "$r" commit -q -m localonly
plan_branch plans/localonly-plan.md
expect_code "local-only plan branch without upstream: exit 0" 0
expect_eq "local-only plan branch: pushed with tracking" "$(git -C "$r" rev-parse '@{upstream}')" "$(git -C "$r" rev-parse HEAD)"
# Stale local main behind origin/main: plan merged on origin/main must still branch from origin/main.
other_clone="$SANDBOX/plan-other"
git clone -q -b main "$origin" "$other_clone"
git -C "$other_clone" config user.email test@example.com
git -C "$other_clone" config user.name Test
printf '# Fresh\n\n**Status:** Draft\n' > "$other_clone/plans/fresh-plan.md"
git -C "$other_clone" add plans/fresh-plan.md
git -C "$other_clone" commit -q -m "add fresh plan"
git -C "$other_clone" push -q origin main
fresh_origin_sha="$(git -C "$other_clone" rev-parse HEAD)"
git -C "$r" checkout -q main
git -C "$r" checkout -q -b topic/unrelated
git -C "$r" fetch -q origin
cp "$other_clone/plans/fresh-plan.md" "$r/plans/fresh-plan.md"
git -C "$r" add plans/fresh-plan.md; git -C "$r" commit -q -m "copy fresh"
plan_branch plans/fresh-plan.md
expect_code "stale local main behind origin/main: exit 0" 0
expect_eq "stale local main: branched from origin/main" "$(git -C "$r" rev-parse HEAD~1)" "$fresh_origin_sha"

# Failing commit hook (e.g. a linter not installed in a fresh worktree): the header edit is
# rolled back, so the re-run after fixing the cause does not trip over a dirty tree.
git -C "$r" checkout -q main
git -C "$r" merge -q --ff-only origin/main
printf '# Hook\n\n**Status:** Draft\n' > "$r/plans/hook-plan.md"
git -C "$r" add plans/hook-plan.md; git -C "$r" commit -q -m "add hook plan"; git -C "$r" push -q origin main
add_hook "$r" 'echo "biome: not found" >&2; exit 1'
plan_branch plans/hook-plan.md
expect_code "commit hook fails: exit 5" 5
check "commit hook fails: hook error on stderr" grep -q 'biome: not found' "$SANDBOX/stderr"
expect_next "commit hook fails with a missing tool: next action installs dependencies" "install the project's locked dependencies"
expect_eq "commit hook fails: bs-commit's own next line is not passed through" "$(grep -c '^next: ' "$SANDBOX/stderr")" "1"
expect_eq "commit hook fails: header edit rolled back, tree clean" "$(git -C "$r" status --porcelain)" ""
rm "$r/.git/hooks/pre-commit"
plan_branch plans/hook-plan.md
expect_code "re-run after fixing the hook: exit 0" 0
expect_eq "re-run after fixing the hook: header committed" "$(git -C "$r" log -1 --format=%s)" "docs(hook): start plan"

# Push of the header commit fails: the re-run pushes it instead of reporting success with
# the commit only local.
git -C "$r" checkout -q main
printf '# Push\n\n**Status:** Draft\n' > "$r/plans/push-plan.md"
git -C "$r" add plans/push-plan.md; git -C "$r" commit -q -m "add push plan"; git -C "$r" push -q origin main
git -C "$r" push -q origin main:feat/push
git -C "$r" branch -q --track feat/push origin/feat/push
git -C "$r" remote set-url --push origin "$SANDBOX/no-such-origin.git"
plan_branch plans/push-plan.md
expect_code "header push fails: exit 3" 3
expect_next "header push fails: next action re-runs once" "re-run once"
git -C "$r" remote set-url --push origin "$origin"
plan_branch plans/push-plan.md
expect_code "re-run after a failed header push: exit 0" 0
expect_eq "re-run after a failed header push: nothing new committed" "$(pb_field COMMITTED)" "none"
expect_eq "re-run after a failed header push: header commit pushed" \
  "$(git -C "$r" rev-parse origin/feat/push)" "$(git -C "$r" rev-parse feat/push)"

echo "== bs-worktree"
r="$(new_repo)"
first="$(git -C "$r" rev-parse HEAD)"
echo two > "$r/two.txt"; git -C "$r" add two.txt; git -C "$r" commit -q -m two
run_in "$r" "$WORKTREE" add HEAD~1 base
expect_code "add: exit 0" 0
wt="$OUT"
expect_eq "add: worktree is at <ref>" "$(git -C "$wt" rev-parse HEAD)" "$first"
check "add: worktree is outside the repo" test "${wt#"$r"/}" = "$wt"
check "add: label in the directory name" test "$(basename "$wt" | cut -d. -f1)" = bs-base
check "add: detached HEAD" test -z "$(git -C "$wt" symbolic-ref -q HEAD || true)"
run_in "$r" "$WORKTREE" add no-such-ref
expect_code "add: unknown ref: exit 2" 2
run_in "$r" "$WORKTREE" add HEAD ../x
expect_code "add: label with a path: exit 2" 2
run_in "$r" "$WORKTREE" remove "$r"
expect_code "remove refuses the main checkout: exit 2" 2
plain="$(mktemp -d "$SANDBOX/plain-dir.XXXXXX")"
run_in "$r" "$WORKTREE" remove "$plain"
expect_code "remove refuses a plain directory: exit 2" 2
check "remove refusal leaves the plain directory" test -d "$plain"
other="$(new_repo)"
other_wt="$(cd "$other" && "$WORKTREE" add HEAD)"
run_in "$r" "$WORKTREE" remove "$other_wt"
expect_code "remove refuses another repo's worktree: exit 2" 2
check "remove refusal leaves the other worktree" test -d "$other_wt"
(cd "$other" && "$WORKTREE" remove "$other_wt")
run_in "$r" "$WORKTREE" remove "$wt"
expect_code "remove: exit 0" 0
check "remove: worktree deleted" test ! -e "$wt"
check "remove: worktree unregistered" test -z "$(git -C "$r" worktree list --porcelain | grep -F "$wt" || true)"
mkdir -p "$SANDBOX/wt-tmp"
rm -rf "$r/.git/worktrees"; touch "$r/.git/worktrees"  # git cannot register the new worktree
run_in "$r" env TMPDIR="$SANDBOX/wt-tmp" "$WORKTREE" add HEAD
expect_code "add: git worktree add fails: exit 3" 3
check "add failure: git's error is passed through" test -s "$SANDBOX/stderr"
check "add failure: temp directory removed" test -z "$(ls -A "$SANDBOX/wt-tmp")"
rm "$r/.git/worktrees"

echo "== bs-pr-ci"
export BS_PR_CI_POLL_INTERVAL=0 BS_PR_CI_POLL_LIMIT=3
pr_ci() { run_in "$r" env PATH="$GH_PATH" "$PR_CI" "$@"; }
no_checks() { echo "no checks reported on the 'feat/x' branch" > "$FAKE_GH/$1.out"; echo 1 > "$FAKE_GH/$1.rc"; }
r="$(new_repo)"
mkdir -p "$r/.github/workflows"; echo 'name: CI' > "$r/.github/workflows/ci.yml"
git -C "$r" add .github; git -C "$r" commit -q -m ci
fake_gh_reset
pr_ci feat/x
expect_eq "all checks pass: pass" "$OUT" "pass"
check "watches the branch's checks, failing fast" grep -qx 'pr checks feat/x --watch --fail-fast' "$FAKE_GH/calls"
fake_gh_reset; echo 1 > "$FAKE_GH/pr-checks.rc"
printf '[{"name":"test","bucket":"fail","state":"FAILURE"},{"name":"lint","bucket":"pass"},{"name":"e2e","bucket":"cancel"}]\n' > "$FAKE_GH/pr-checks.json"
pr_ci feat/x
expect_eq "failing checks: fail <names>" "$OUT" "fail test,e2e"
fake_gh_reset; no_checks pr-checks
pr_ci feat/x
expect_eq "no checks reported with workflows: none-configured after retries" "$OUT" "none-configured"
expect_eq "no checks reported: 1 call + BS_PR_CI_POLL_LIMIT retries" "$(gh_calls 'pr checks feat/x --watch')" "4"
fake_gh_reset; no_checks pr-checks.1; no_checks pr-checks.2; echo 1 > "$FAKE_GH/pr-checks.3.rc"
printf '[{"name":"test","bucket":"fail"}]\n' > "$FAKE_GH/pr-checks.json"
pr_ci feat/x
expect_eq "checks register on retry 2: that run's result" "$OUT" "fail test"
expect_eq "checks register on retry 2: no further retries" "$(gh_calls 'pr checks feat/x --watch')" "3"
fake_gh_reset
printf '[{"name":"test","bucket":"skipping"},{"name":"publish","bucket":"skipping"}]\n' > "$FAKE_GH/pr-checks.json"
pr_ci feat/x
expect_eq "every check skipped: skipped, not pass" "$OUT" "skipped"
fake_gh_reset
printf '[{"name":"test","bucket":"pass"},{"name":"publish","bucket":"skipping"}]\n' > "$FAKE_GH/pr-checks.json"
pr_ci feat/x
expect_eq "some checks skipped, one passed: pass" "$OUT" "pass"
fake_gh_reset; no_checks pr-checks
printf '{"mergeable":"CONFLICTING"}\n' > "$FAKE_GH/pr-view.json"
pr_ci feat/x
expect_eq "no checks reported on a conflicting PR: conflict" "$OUT" "conflict"
expect_eq "conflicting PR: no retries" "$(gh_calls 'pr checks feat/x --watch')" "1"
fake_gh_reset; no_checks pr-checks
printf '{"mergeable":"UNKNOWN"}\n' > "$FAKE_GH/pr-view.json"
pr_ci feat/x
expect_eq "no checks, mergeability unknown: none-configured after retries" "$OUT" "none-configured"
fake_gh_reset; echo "no pull requests found for branch \"feat/x\"" > "$FAKE_GH/pr-checks.out"; echo 1 > "$FAKE_GH/pr-checks.rc"
pr_ci feat/x
expect_code "no PR: exit 3" 3
expect_next "no PR: next action is BLOCKED_BY_CI" "BLOCKED_BY_CI"
expect_eq "no PR: no retries" "$(gh_calls 'pr checks feat/x --watch')" "1"
fake_gh_reset; echo "GraphQL: Something went wrong while executing your query." > "$FAKE_GH/pr-checks.1.out"
echo 1 > "$FAKE_GH/pr-checks.1.rc"
pr_ci feat/x
expect_eq "transient gh error, then checks pass: pass" "$OUT" "pass"
expect_eq "transient gh error: retried once" "$(gh_calls 'pr checks feat/x --watch')" "2"
fake_gh_reset; echo "HTTP 502: bad gateway" > "$FAKE_GH/pr-checks.out"; echo 1 > "$FAKE_GH/pr-checks.rc"
pr_ci feat/x
expect_code "persistent gh error: exit 3" 3
expect_next "persistent gh error: next action is BLOCKED_BY_CI" "BLOCKED_BY_CI"
expect_eq "persistent gh error: 1 call + BS_PR_CI_POLL_LIMIT retries" "$(gh_calls 'pr checks feat/x --watch')" "4"
check "persistent gh error: gh's error is passed through" grep -q "HTTP 502" "$SANDBOX/stderr"
r="$(new_repo)"
fake_gh_reset; no_checks pr-checks
pr_ci feat/x
expect_eq "no workflows dir: none-configured" "$OUT" "none-configured"
expect_eq "no workflows dir: one call, no retries" "$(gh_calls 'pr checks')" "1"
pr_ci
expect_code "no branch: usage error" 2

echo "== bs-review-state ci"
r="$(new_repo)"
mkdir -p "$r/.github/workflows"; echo 'name: CI' > "$r/.github/workflows/ci.yml"
git -C "$r" add .github; git -C "$r" commit -q -m ci
GATED="$(printf '## Review Status\n\n**Gate:** PASSED (Pass 1)\n\nreport')"
# ci_record [<mergeable>]: a gated draft PR, optionally with a mergeable state for bs-pr-ci
ci_record() {
  pr_record OPEN true 0 "$GATED"
  python3 - "$FAKE_GH/pr-view.json" "${1:-MERGEABLE}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["mergeable"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"))
PY
}
ci_gate() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["body"])' "$FAKE_GH/pr-view.json" | grep -m1 'Gate:'; }
ci_record
review_state ci feat/x "Pass 1"
expect_code "ci pass: exit 0" 0
expect_eq "ci pass: status line" "$(printf '%s\n' "$OUT" | head -n 1)" "PASSED pass"
expect_eq "ci pass: Gate line records CI" "$(ci_gate)" "**Gate:** PASSED (Pass 1; CI: pass)"
expect_eq "ci pass: PR marked ready" "$(gh_calls 'pr ready feat/x')" "1"
check "ci pass: next line returns PASSED" sh -c 'printf "%s\n" "$1" | grep -q "^next: return the PR URL with REVIEW_STATUS=PASSED"' _ "$OUT"
ci_record
printf '[{"name":"test","bucket":"skipping"}]\n' > "$FAKE_GH/pr-checks.json"
review_state ci feat/x "Pass 1"
expect_eq "ci skipped: still PASSED" "$(printf '%s\n' "$OUT" | head -n 1)" "PASSED skipped"
expect_eq "ci skipped: Gate line says no check ran" "$(ci_gate)" "**Gate:** PASSED (Pass 1; CI: skipped, no check ran)"
check "ci skipped: next line tells the user" sh -c 'printf "%s\n" "$1" | grep -q "^next: tell the user CI did not test this PR"' _ "$OUT"
ci_record; echo 1 > "$FAKE_GH/pr-checks.rc"
printf '[{"name":"test","bucket":"fail"},{"name":"lint","bucket":"pass"}]\n' > "$FAKE_GH/pr-checks.json"
review_state ci feat/x "Pass 1, Fix, Pass 2"
expect_eq "ci fail: BLOCKED_BY_CI with the checks" "$(printf '%s\n' "$OUT" | head -n 1)" "BLOCKED_BY_CI fail test"
expect_eq "ci fail: Gate line names the failing checks" "$(ci_gate)" "**Gate:** BLOCKED_BY_CI (Pass 1, Fix, Pass 2; failing: test)"
expect_eq "ci fail: PR stays a draft" "$(gh_calls 'pr ready')" "0"
check "ci fail: next line leaves the draft" sh -c 'printf "%s\n" "$1" | grep -q "^next: leave the PR in Draft"' _ "$OUT"
ci_record CONFLICTING; no_checks pr-checks
review_state ci feat/x "Pass 1"
expect_eq "ci conflict: BLOCKED_BY_CI" "$(printf '%s\n' "$OUT" | head -n 1)" "BLOCKED_BY_CI conflict"
expect_eq "ci conflict: Gate line names the base" "$(ci_gate)" "**Gate:** BLOCKED_BY_CI (Pass 1; merge conflict with feat/base)"
r_nowf="$(new_repo)"
ci_record; no_checks pr-checks
run_in "$r_nowf" env PATH="$GH_PATH" "$REVIEW_STATE" ci feat/x "Pass 1"
expect_eq "ci none-configured: PASSED" "$(printf '%s\n' "$OUT" | head -n 1)" "PASSED none-configured"
expect_eq "ci none-configured: Gate line" "$(ci_gate)" "**Gate:** PASSED (Pass 1; CI: none configured)"
ci_record; echo "HTTP 502: bad gateway" > "$FAKE_GH/pr-checks.out"; echo 1 > "$FAKE_GH/pr-checks.rc"
review_state ci feat/x "Pass 1"
expect_code "ci gh error while waiting: exit 0" 0
expect_eq "ci gh error while waiting: BLOCKED_BY_CI error" "$(printf '%s\n' "$OUT" | head -n 1)" "BLOCKED_BY_CI error"
check "ci gh error while waiting: Gate line carries the error" sh -c 'grep -q "CI wait failed: HTTP 502" "$1"' _ "$FAKE_GH/pr-edit.body"
check "ci gh error: bs-pr-ci's next line is not passed through" sh -c '! grep -q "^next: " "$1"' _ "$SANDBOX/stderr"
ci_record; echo 1 > "$FAKE_GH/pr-ready.rc"
review_state ci feat/x "Pass 1"
expect_code "ci: gh pr ready failure: exit 3" 3
expect_next "ci: gh pr ready failure: next action retries once" "retry once"
fake_gh_reset; echo 'no pull requests found for branch "feat/x"' > "$FAKE_GH/pr-view.err"
review_state ci feat/x "Pass 1"
expect_code "ci without a PR: exit 3" 3
review_state ci feat/x
expect_code "ci without passes: usage error" 2
expect_next "ci usage error: next action fixes the call" "fix the call"

echo "== bs-diff-target"
EMPTY_TREE="$(git hash-object -t tree /dev/null)"
diff_target() { run_in "$1" env PATH="$GH_PATH" "$DIFF_TARGET" "${@:2}"; }
field() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; } # field <KEY>: value(s) of KEY lines in $OUT
r="$(new_repo)"
git -C "$r" branch -q -M main
diff_target "$r"
expect_code "root commit, clean: exit 0" 0
expect_eq "root commit, clean: base is the empty tree" "$(field BASE)" "$EMPTY_TREE"
expect_eq "root commit, clean: diff of the whole commit" "$(field DIFF)" "git diff $EMPTY_TREE HEAD"
expect_eq "root commit, clean: says it reviews the last commit" "$(field NOTE)" "last-commit"
expect_eq "workdir is the repo root" "$(field WORKDIR)" "$(cd "$r" && pwd -P)"
expect_eq "no untracked files: none" "$(field UNTRACKED)" "none"
echo two > "$r/two.txt"; git -C "$r" add two.txt; git -C "$r" commit -q -m two
diff_target "$r"
expect_eq "clean main: base is HEAD~1" "$(field BASE)" "$(git -C "$r" rev-parse HEAD~1)"
expect_eq "clean main: diff of the last commit" "$(field DIFF)" "git diff $(git -C "$r" rev-parse HEAD~1) HEAD"
echo edit >> "$r/two.txt"
diff_target "$r"
head_sha="$(git -C "$r" rev-parse HEAD)"
expect_eq "dirty main without upstream: base is HEAD" "$(field BASE)" "$head_sha"
expect_eq "dirty main: one diff of base against the tree" "$(field DIFF)" "git diff $head_sha"
expect_eq "dirty main: no note" "$(field NOTE)" ""
git -C "$r" checkout -q -- two.txt
echo u > "$r/sp ace.txt"; echo u > "$r/café.txt"
mkdir -p "$r/sub"; echo u > "$r/sub/n.txt"
diff_target "$r"
expect_eq "untracked only: not the last-commit fallback" "$(field NOTE)" ""
expect_eq "untracked files listed literally" "$(field UNTRACKED)" "$(printf 'café.txt\nsp ace.txt\nsub/n.txt')"
root_out="$OUT"
diff_target "$r/sub"
expect_eq "same output from a subdirectory" "$OUT" "$root_out"
rm -rf "$r/sp ace.txt" "$r/café.txt" "$r/sub"

git -C "$r" checkout -q -b feat/x
echo f > "$r/f.txt"; git -C "$r" add f.txt; git -C "$r" commit -q -m f
main_sha="$(git -C "$r" rev-parse main)"
diff_target "$r"
expect_eq "feature branch: base is the merge-base with main" "$(field BASE)" "$main_sha"
expect_eq "feature branch: diff from the merge-base" "$(field DIFF)" "git diff $main_sha"
git -C "$r" update-ref refs/remotes/origin/main "$(git -C "$r" rev-parse main~1)"
diff_target "$r"
expect_eq "feature branch: origin/main preferred over main" "$(field BASE)" "$(git -C "$r" rev-parse main~1)"
git -C "$r" branch -q trunk main~1
git -C "$r" update-ref refs/remotes/origin/trunk "$(git -C "$r" rev-parse main~1)"
git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
git -C "$r" checkout -q main
diff_target "$r"
expect_eq "origin/HEAD names the default branch: main is a feature branch" "$(field BASE)" "$(git -C "$r" rev-parse main~1)"
git -C "$r" symbolic-ref --delete refs/remotes/origin/HEAD
git -C "$r" remote add origin "$SANDBOX/unused-origin.git"
git -C "$r" config branch.main.remote origin
git -C "$r" config branch.main.merge refs/heads/main
echo up >> "$r/two.txt"
diff_target "$r"
expect_eq "default branch with upstream: base is the merge-base with it" "$(field BASE)" "$(git -C "$r" rev-parse main~1)"
git -C "$r" checkout -q -- two.txt

diff_target "$r" feat/x
expect_eq "branch target: base is the branch" "$(field BASE)" "feat/x"
expect_eq "branch target: three-dot diff to HEAD" "$(field DIFF)" "git diff feat/x...HEAD"
expect_eq "branch target: no untracked list" "$(field UNTRACKED)" "none"
diff_target "$r" main~1...feat/x
expect_eq "range target: base is its left side" "$(field BASE)" "main~1"
expect_eq "range target: diff as given" "$(field DIFF)" "git diff main~1...feat/x"
diff_target "$r" no-such-branch
expect_code "unknown branch target: exit 2" 2
# Linked worktree (e.g. a T3 Code thread) whose local main is stale: origin/main moved on, and
# the task branch starts from origin/main, as /bs-loop creates it. Reviewing against the remote
# base shows only the task's change; the stale local main would add the upstream commit too.
up_tree="$(printf '100644 blob %s\tupstream.txt\n' "$(echo up | git -C "$r" hash-object -w --stdin)" |
  cat - <(git -C "$r" ls-tree main) | git -C "$r" mktree)"
up_sha="$(git -C "$r" commit-tree -p main -m upstream "$up_tree")"
git -C "$r" update-ref refs/remotes/origin/main "$up_sha"
wt="$SANDBOX/thread-wt"
git -C "$r" worktree add -q --no-track -b fix/wt "$wt" origin/main
echo t > "$wt/task.txt"; git -C "$wt" add task.txt; git -C "$wt" commit -q -m task
diff_target "$wt" origin/main
expect_code "worktree, remote base target: exit 0" 0
expect_eq "worktree, remote base target: base is origin/main" "$(field BASE)" "origin/main"
expect_eq "worktree, remote base target: workdir is the worktree" "$(field WORKDIR)" "$(cd "$wt" && pwd -P)"
expect_eq "worktree, remote base target: only the task's change" \
  "$(cd "$wt" && $(field DIFF) --name-only)" "task.txt"
check "worktree: stale local main would add the upstream commit" \
  sh -c 'git -C "$1" diff --name-only main...HEAD | grep -qx upstream.txt' _ "$wt"
git -C "$r" worktree remove --force "$wt"

e="$(new_repo --empty)"
diff_target "$e"
expect_code "unborn HEAD: exit 2" 2
OUT="$(cd "$SANDBOX/plain" && "$DIFF_TARGET" 2>/dev/null)" && CODE=0 || CODE=$?
expect_code "not a repo: exit 2" 2

echo "== bs-diff-target PR"
origin="$SANDBOX/origin.git"
git init -q --bare "$origin"
r="$(new_repo)"
git -C "$r" branch -q -M main
git -C "$r" remote add origin "$origin"
git -C "$r" push -q origin main
git -C "$r" checkout -q -b pr-head
echo pr > "$r/pr.txt"; git -C "$r" add pr.txt; git -C "$r" commit -q -m pr
pr_sha="$(git -C "$r" rev-parse HEAD)"
git -C "$r" push -q origin "HEAD:refs/pull/7/head"
git -C "$r" checkout -q main
git -C "$r" branch -q -D pr-head
fake_gh_reset; printf '{"baseRefName":"main","headRefOid":"%s"}\n' "$pr_sha" > "$FAKE_GH/pr-view.json"
diff_target "$r" '#7'
expect_code "PR #7: exit 0" 0
wt="$(field WORKDIR)"
expect_eq "PR: base is origin/<baseRefName>" "$(field BASE)" "origin/main"
expect_eq "PR: three-dot diff in the worktree" "$(field DIFF)" "git diff origin/main...HEAD"
expect_eq "PR: number reported for cleanup" "$(field PR)" "7"
expect_eq "PR: worktree HEAD is the PR head" "$(git -C "$wt" rev-parse HEAD)" "$pr_sha"
check "PR: worktree is outside the repo" test "${wt#"$r"/}" = "$wt"
check "PR: PR ref fetched" git -C "$r" rev-parse -q --verify refs/bs-review/pr-7
check "PR: gh asked for base and head" grep -q '^pr view 7 --json baseRefName,headRefOid' "$FAKE_GH/calls"
run_in "$r" "$DIFF_TARGET" cleanup "$r" 7
expect_code "cleanup refuses the main checkout: exit 2" 2
check "cleanup refusal leaves the worktree" test -d "$wt"
run_in "$r" "$DIFF_TARGET" cleanup "$wt" 7
expect_code "cleanup: exit 0" 0
check_not_dir() { [ ! -e "$1" ]; }
check "cleanup: worktree removed" check_not_dir "$wt"
check "cleanup: worktree unregistered" test -z "$(git -C "$r" worktree list --porcelain | grep -F "$wt" || true)"
check "cleanup: PR ref deleted" test -z "$(git -C "$r" rev-parse -q --verify refs/bs-review/pr-7 || true)"
fake_gh_reset; printf '{"baseRefName":"main","headRefOid":"%s"}\n' "$pr_sha" > "$FAKE_GH/pr-view.json"
diff_target "$r" https://github.com/o/r/pull/7/files
expect_eq "PR URL: number parsed" "$(field PR)" "7"
run_in "$r" "$DIFF_TARGET" cleanup "$(field WORKDIR)" 7

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "[FAIL] $FAILURES check(s) failed."
  exit 1
fi
echo "[PASS] All script checks passed."
