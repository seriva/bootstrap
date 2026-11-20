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
PLAN_CI="$REPO_DIR/workflows/shared/scripts/bs-plan-ci"
DIFF_TARGET="$REPO_DIR/workflows/shared/scripts/bs-diff-target"
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

# Fake gh: logs each call to $FAKE_GH/calls and serves real JSON fixtures through the
# script's actual --json field filter and --jq expression (via jq if installed, else Python 3):
#   pr-view.json (or pr-view.err, exit 1); run-list.<call#>.json or run-list.json;
#   run-watch.rc (exit code of gh run watch). gh workflow run only logs.
FAKE_GH="$SANDBOX/fake-gh"
mkdir -p "$SANDBOX/bin" "$FAKE_GH"
cat > "$SANDBOX/bin/gh" <<'EOF'
#!/bin/sh
set -eu
d="$FAKE_GH"
printf '%s\n' "$*" >> "$d/calls"
cmd="$1 $2"
shift 2
fields="" jq_expr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) fields="$2"; shift 2 ;;
    --jq|-q) jq_expr="$2"; shift 2 ;;
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
  "run list")
    n=$(($(cat "$d/run-list.count" 2>/dev/null || echo 0) + 1))
    echo "$n" > "$d/run-list.count"
    if [ -f "$d/run-list.$n.json" ]; then render_json "$d/run-list.$n.json"
    elif [ -f "$d/run-list.json" ]; then render_json "$d/run-list.json"
    else printf '[]\n' > "$d/empty.json"; render_json "$d/empty.json"
    fi ;;
  "run watch") exit "$(cat "$d/run-watch.rc" 2>/dev/null || echo 0)" ;;
  "workflow run") : ;;
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
pr_record OPEN true 0 "$(printf '**Gate:** PASSED\n**Gate:** BLOCKED_BY_CI: test')"
review_state feat/x
expect_eq "PASSED and BLOCKED_BY_CI: BLOCKED_BY_CI wins" "$OUT" "gated:BLOCKED_BY_CI feat/base"
pr_record OPEN true 0 "$(printf '**Gate:** PASSED\nCI: BLOCKED_BY_CI (test)')"
review_state feat/x
expect_eq "PASSED with non-Gate BLOCKED_BY_CI line: BLOCKED_BY_CI wins" "$OUT" "gated:BLOCKED_BY_CI feat/base"
pr_record OPEN true 0 "$(printf '**Gate:** PASSED\n\nCI: BLOCKED_BY_CI (test, lint failing)')"
review_state feat/x
expect_eq "BLOCKED_BY_CI on a line after the Gate line wins" "$OUT" "gated:BLOCKED_BY_CI feat/base"
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

echo "== bs-plan-ci"
export BS_PLAN_CI_POLL_INTERVAL=0 BS_PLAN_CI_POLL_LIMIT=3
# ci_repo [<ci.yml on line>]: repo whose origin/feat/p commit holds a ci.yml with that "on:" line
ci_repo() {
  local repo
  repo="$(new_repo)"
  if [ -n "${1:-}" ]; then
    mkdir -p "$repo/.github/workflows"
    printf 'name: CI\non:\n  pull_request:\n%s\njobs: {}\n' "$1" > "$repo/.github/workflows/ci.yml"
    git -C "$repo" add .github
    git -C "$repo" commit -q -m ci
  fi
  git -C "$repo" update-ref refs/remotes/origin/feat/p HEAD
  echo "$repo"
}
# runs_json <out-file> [<id> <sha> <status> <conclusion>]...: writes real gh run list JSON
runs_json() {
  python3 - "$@" <<'PY'
import json, sys
out, args = sys.argv[1], sys.argv[2:]
runs = []
for i in range(0, len(args), 4):
    rid, sha, status, concl = args[i:i+4]
    runs.append({"databaseId": int(rid), "headSha": sha, "status": status, "conclusion": concl,
                 "url": f"https://ci.example/runs/{rid}", "extra": True})
json.dump(runs, open(out, "w"))
PY
}
plan_ci() { run_in "$r" env PATH="$GH_PATH" "$PLAN_CI" "$@"; }
r="$(ci_repo '  workflow_dispatch:')"
head="$(git -C "$r" rev-parse HEAD)"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 9 "$head" completed success
plan_ci feat/p
expect_eq "run for HEAD succeeded: pass" "$OUT" "pass"
check "gh run list asks for workflow_dispatch runs of the plan branch" grep -q '^run list --workflow ci.yml --branch feat/p --event workflow_dispatch ' "$FAKE_GH/calls"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 9 "$head" in_progress ""
plan_ci feat/p
expect_eq "run for HEAD in progress: pending" "$OUT" "pending"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 9 "$head" completed failure
plan_ci feat/p
expect_eq "run for HEAD failed: fail <url>" "$OUT" "fail https://ci.example/runs/9"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 9 "$head" completed timed_out
plan_ci feat/p
expect_eq "run for HEAD timed out: fail <url>" "$OUT" "fail https://ci.example/runs/9"
fake_gh_reset
plan_ci feat/p
expect_eq "no run: dispatched" "$OUT" "dispatched"
expect_eq "no run: exactly one dispatch" "$(gh_calls 'workflow run ci.yml --ref feat/p')" "1"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 9 "$head" completed cancelled
plan_ci feat/p
expect_eq "cancelled run for HEAD is ignored: dispatched" "$OUT" "dispatched"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 8 0000000000000000000000000000000000000000 completed failure
plan_ci feat/p
expect_eq "no run for HEAD, earlier run failed: recheck" "$OUT" "recheck"
expect_eq "recheck: no dispatch" "$(gh_calls 'workflow run')" "0"
fake_gh_reset; runs_json "$FAKE_GH/run-list.json" 8 0000000000000000000000000000000000000000 completed success
plan_ci feat/p
expect_eq "no run for HEAD, earlier run passed: dispatched" "$OUT" "dispatched"

fake_gh_reset
runs_json "$FAKE_GH/run-list.1.json" 8 0000000000000000000000000000000000000000 completed failure
runs_json "$FAKE_GH/run-list.2.json" 8 0000000000000000000000000000000000000000 completed failure
runs_json "$FAKE_GH/run-list.3.json" 9 "$head" completed success 8 0000000000000000000000000000000000000000 completed failure
plan_ci --wait feat/p
expect_eq "--wait: run registers on the 2nd poll: pass" "$OUT" "pass"
expect_eq "--wait: one dispatch while polling" "$(gh_calls 'workflow run')" "1"
fake_gh_reset
plan_ci --wait feat/p
expect_eq "--wait: run never registers: fail registration-timeout" "$OUT" "fail registration-timeout"
expect_eq "--wait: still one dispatch on timeout" "$(gh_calls 'workflow run')" "1"
fake_gh_reset
runs_json "$FAKE_GH/run-list.1.json" 9 "$head" in_progress ""
runs_json "$FAKE_GH/run-list.2.json" 9 "$head" completed failure
echo 1 > "$FAKE_GH/run-watch.rc"
plan_ci --wait feat/p
expect_eq "--wait: watches a pending run, then reports its result" "$OUT" "fail https://ci.example/runs/9"
expect_eq "--wait: watches run 9" "$(gh_calls 'run watch 9')" "1"
expect_eq "--wait on a pending run: no dispatch" "$(gh_calls 'workflow run')" "0"
fake_gh_reset
runs_json "$FAKE_GH/run-list.1.json" 9 "$head" in_progress ""
runs_json "$FAKE_GH/run-list.2.json" 9 "$head" completed cancelled
plan_ci --wait feat/p
expect_eq "--wait: watched run gets cancelled: fail cancelled" "$OUT" "fail cancelled"

fake_gh_reset
r="$(ci_repo '  # workflow_dispatch:')"
plan_ci feat/p
expect_eq "commented workflow_dispatch: unavailable" "$OUT" "unavailable"
r="$(ci_repo)"
plan_ci feat/p
expect_eq "no ci.yml: unavailable" "$OUT" "unavailable"
r="$(ci_repo '  workflow_dispatch:')"
plan_ci feat/other
expect_eq "plan branch not pushed: unavailable" "$OUT" "unavailable"
expect_eq "unavailable: no gh calls" "$(gh_calls '')" "0"
plan_ci
expect_code "no branch: usage error" 2

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
