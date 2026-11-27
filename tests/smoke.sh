#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bootstrap smoke test
# Runs init.sh, sync.sh, and install.sh against throwaway targets in a temp dir
# and checks the results. Never touches the real $HOME or sibling repositories.
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-smoke.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

FAILURES=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILURES=$((FAILURES + 1)); }
check() { # check <label> <command...>: passes when the command succeeds
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}
check_not() { # check_not <label> <command...>: passes when the command fails
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi
}
# Content fingerprint of a directory tree (paths + contents, .git excluded).
tree_hash() {
  (cd "$1" && find . -type f -not -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(git hash-object --no-filters "$f")"
  done) | git hash-object --stdin
}

INIT="$REPO_DIR/init.sh"
SYNC="$REPO_DIR/sync.sh"
INSTALL="$REPO_DIR/install.sh"

echo "== init.sh"
for profile in continuous versioned; do
  target="$SANDBOX/init-$profile"
  check "$profile: init succeeds" "$INIT" "$target" --type "$profile"
  for f in AGENTS.md CLAUDE.md lefthook.yml lefthook-bootstrap.yml .gitignore \
    .github/dependabot.yml .github/copilot-instructions.md .github/workflows/ci.yml \
    plans/template.md plans/follow-ups.md plans/roadmap.md CHANGELOG.md; do
    check "$profile: creates $f" test -f "$target/$f"
  done
  check "$profile: creates a git repo" test -d "$target/.git"
  check_not "$profile: follow-ups format has no route suffix" grep -qF ') →' "$target/plans/follow-ups.md"
  check_not "$profile: CI does not skip phase PRs" grep -qF -- '-phase-' "$target/.github/workflows/ci.yml"
  check_not "$profile: CI has no workflow_dispatch trigger" grep -qE '^  workflow_dispatch:' "$target/.github/workflows/ci.yml"
  check_not "$profile: fills in Release Model" grep -q '^- \*\*Release Model\*\*: \[' "$target/AGENTS.md"
  check_not "$profile: refuses to overwrite without --force" "$INIT" "$target" --type "$profile"
  check "$profile: overwrites with --force" "$INIT" "$target" --type "$profile" --force
done
check "continuous: Release Model is Continuous" grep -q '^- \*\*Release Model\*\*: Continuous$' "$SANDBOX/init-continuous/AGENTS.md"
check "versioned: Release Model is Semantic Versioning" grep -q '^- \*\*Release Model\*\*: Semantic Versioning$' "$SANDBOX/init-versioned/AGENTS.md"
check "continuous: creates plans/archive/" test -f "$SANDBOX/init-continuous/plans/archive/.gitkeep"
check_not "versioned: no plans/archive/" test -e "$SANDBOX/init-versioned/plans/archive"
check_not "rejects an unknown --type" "$INIT" "$SANDBOX/init-bad" --type nightly

echo "== sync.sh"
target="$SANDBOX/init-continuous"
check "--check passes on a fresh scaffold" "$SYNC" --check "$target"

# Introduce drift in every synced file type.
printf '\n- drifted rule\n' > "$SANDBOX/part1-drift"
awk 'NR==FNR{extra=extra $0 "\n"; next} /^## 2\. Git Standards/{printf "%s", extra} {print}' \
  "$SANDBOX/part1-drift" "$target/AGENTS.md" > "$target/AGENTS.md.tmp" && mv "$target/AGENTS.md.tmp" "$target/AGENTS.md"
rm "$target/CLAUDE.md"
echo "# drift" >> "$target/plans/template.md"
echo "# drift" >> "$target/lefthook-bootstrap.yml"
part2_before="$(sed -n '/^# Part 2/,$p' "$target/AGENTS.md")"

check_not "--check fails on drift" "$SYNC" --check "$target"
before="$(tree_hash "$target")"
check "--dry-run succeeds" "$SYNC" --dry-run "$target"
check "--dry-run writes nothing" test "$(tree_hash "$target")" = "$before"
check "sync repairs drift" "$SYNC" "$target"
check "--check passes after sync" "$SYNC" --check "$target"
check "sync restores CLAUDE.md" cmp -s "$REPO_DIR/scaffold/CLAUDE.md" "$target/CLAUDE.md"
check "sync keeps AGENTS.md Part 2" test "$(sed -n '/^# Part 2/,$p' "$target/AGENTS.md")" = "$part2_before"
before="$(tree_hash "$target")"
check "second sync succeeds" "$SYNC" "$target"
check "second sync is a no-op" test "$(tree_hash "$target")" = "$before"

# lefthook.yml is project-owned: drift is reported, never rewritten.
sed 's/lefthook-bootstrap.yml/other.yml/' "$target/lefthook.yml" > "$target/lefthook.yml.tmp" && mv "$target/lefthook.yml.tmp" "$target/lefthook.yml"
check_not "--check fails when lefthook.yml drops the shared hooks" "$SYNC" --check "$target"
"$SYNC" "$target" >/dev/null 2>&1 || true
check "sync leaves lefthook.yml alone" grep -q 'other.yml' "$target/lefthook.yml"

# .gitignore managed block: replaced in place even when the end marker has no trailing newline.
target="$SANDBOX/init-versioned"
"$SYNC" "$target" >/dev/null 2>&1 || true
printf '%s' "$(cat "$target/.gitignore")" > "$target/.gitignore"
check "sync accepts a managed block at EOF without a newline" "$SYNC" "$target"
check "managed block is not duplicated" test "$(grep -c '^# >>> bootstrap-managed$' "$target/.gitignore")" = 1
check "--check passes after the EOF fix" "$SYNC" --check "$target"

# A legacy CI `if:` that skips phase PRs is reported, never rewritten.
ci="$target/.github/workflows/ci.yml"
cp "$ci" "$ci.orig"
sed -i "/^jobs:/{n;a\\    if: \"!contains(github.head_ref, 'phase')\"
}" "$ci"
check "test setup adds the legacy phase-skip line" grep -q "head_ref, 'phase'" "$ci"
check_not "--check fails on a CI if: that skips phase PRs" "$SYNC" --check "$target"
"$SYNC" "$target" >/dev/null 2>&1 || true
check "sync leaves the workflow alone" grep -q "head_ref, 'phase'" "$ci"
mv "$ci.orig" "$ci"
check "--check passes once the line is gone" "$SYNC" --check "$target"

# .gitignore without a managed block: block appended once, legacy broad ignores dropped, own lines kept.
printf 'my-local-dir/\n.claude/\n.codex/\n' > "$target/.gitignore"
check "sync adds the managed block" "$SYNC" "$target"
check "managed block appended once" test "$(grep -c '^# >>> bootstrap-managed$' "$target/.gitignore")" = 1
check_not "legacy broad ignores removed" grep -qxE '\.claude/|\.codex/' "$target/.gitignore"
check "project ignores kept" grep -qx 'my-local-dir/' "$target/.gitignore"
check "--check passes after adding the block" "$SYNC" --check "$target"

# AGENTS.md without Part 1 (e.g. a third-party clone next to bootstrap): reported, never written to.
target="$SANDBOX/foreign"
mkdir -p "$target"
printf '# Agents\nOwn notes.\n' > "$target/AGENTS.md"
printf 'Own Claude notes.\n' > "$target/CLAUDE.md"
before="$(tree_hash "$target")"
check_not "--check fails on a repo without Part 1" "$SYNC" --check "$target"
"$SYNC" "$target" >/dev/null 2>&1 || true
check "sync writes nothing into a repo without Part 1" test "$(tree_hash "$target")" = "$before"

echo "== install.sh"
home="$SANDBOX/home"
# Create every host's config dir so all install targets are exercised.
mkdir -p "$home/.gemini" "$home/.claude" "$home/.codex" "$home/.config/Code/User"
install_env=(env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share")
# Local model override replaces chosen defaults and leaves the others alone (empty disables fix escalation).
mkdir -p "$home/.config/bootstrap"
cat > "$home/.config/bootstrap/models.env" <<'EOF'
BS_MODEL_CODEX="smoke-override-model"
BS_FIX_MODEL_AGY="smoke-fix-model"
BS_FIX_MODEL_CODEX=""
EOF
# Leftovers of an earlier install (a dropped skill, a pre-rename skill, a dropped script) next to the user's own files.
mkdir -p "$home/.claude/skills/bs-dropped" "$home/.claude/skills/dev-loop" "$home/.claude/skills/own-skill" \
  "$home/.claude/commands" "$home/.config/Code/User/prompts" "$home/.local/share/bootstrap/scripts"
touch "$home/.claude/commands/bs-dropped.md" "$home/.claude/commands/own-command.md" \
  "$home/.config/Code/User/prompts/bs-dropped.prompt.md" "$home/.config/Code/User/prompts/own.prompt.md" \
  "$home/.local/share/bootstrap/conventions.md" "$home/.local/share/bootstrap/scripts/bs-dropped"
check "install succeeds" "${install_env[@]}" "$INSTALL"
for stale in .claude/skills/bs-dropped .claude/skills/dev-loop .claude/commands/bs-dropped.md \
  .config/Code/User/prompts/bs-dropped.prompt.md .local/share/bootstrap/conventions.md \
  .local/share/bootstrap/scripts/bs-dropped; do
  check_not "install removes stale $stale" test -e "$home/$stale"
done
for own in .claude/skills/own-skill .claude/commands/own-command.md .config/Code/User/prompts/own.prompt.md; do
  check "install keeps the user's $own" test -e "$home/$own"
done
check "models.env override is rendered" grep -q 'smoke-override-model' "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "models.env fix override is rendered" grep -q 'smoke-fix-model' "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "empty BS_FIX_MODEL_* renders as none" grep -q '_f_codex="none"' "$home/.local/share/bootstrap/scripts/bs-resolve-role"
default_claude="$(sed -n 's/^BS_MODEL_CLAUDE="\(.*\)"$/\1/p' "$REPO_DIR/workflows/shared/models.env")"
default_fix_claude="$(sed -n 's/^BS_FIX_MODEL_CLAUDE="\(.*\)"$/\1/p' "$REPO_DIR/workflows/shared/models.env")"
check "non-overridden models keep their defaults" grep -qF "$default_claude" "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "non-overridden fix models keep their defaults" grep -qF "$default_fix_claude" "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "installed bs-resolve-role uses rendered fix override" sh -c \
  '"$1" --host agy --host-model gemini-4-hydrogen --role fixer --reachable agy | grep -qx "MODEL=smoke-fix-model"' _ \
  "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "installed bs-resolve-role disables empty fix model" sh -c \
  '"$1" --host claude --role fixer --implementer codex --reachable codex | grep -qx "MODEL=smoke-override-model"' _ \
  "$home/.local/share/bootstrap/scripts/bs-resolve-role"
check "second install succeeds" "${install_env[@]}" "$INSTALL"

skills=()
for d in "$REPO_DIR"/workflows/skills/*/; do skills+=("$(basename "$d")"); done
for s in "${skills[@]}"; do
  for f in "$home/.gemini/config/skills/$s/SKILL.md" "$home/.claude/skills/$s/SKILL.md" \
    "$home/.claude/commands/$s.md" "$home/.codex/skills/$s/SKILL.md" \
    "$home/.config/Code/User/prompts/$s.prompt.md"; do
    check "installs ${f#"$home"/}" test -f "$f"
  done
done
for doc in "$REPO_DIR"/workflows/shared/*.md; do
  check "installs shared $(basename "$doc")" test -f "$home/.local/share/bootstrap/$(basename "$doc")"
done
for script in "$REPO_DIR"/workflows/shared/scripts/*; do
  check "installs executable script $(basename "$script")" test -x "$home/.local/share/bootstrap/scripts/$(basename "$script")"
done

leftover="$(grep -rlF '{{BS_' "$home" || true)"
if [[ -z "$leftover" ]]; then
  pass "no unrendered {{BS_*}} placeholders"
else
  fail "unrendered {{BS_*}} placeholders in: ${leftover//$'\n'/, }"
fi

# Every rendered path into the sandbox must point at a file install.sh created
# (docs and skills), or at an executable helper script.
missing="$(grep -rhoE "$home/[^\`\"' )]+\.md" "$home" | sort -u | while IFS= read -r p; do
  [[ -f "$p" ]] || echo "$p"
done)"
missing+="$(grep -rhoE "$home/[^\`\"' )]+/scripts/[A-Za-z0-9_.-]+" "$home" | sort -u | while IFS= read -r p; do
  [[ -x "$p" ]] || echo "$p"
done)"
check "conventions-core.md references helper scripts" grep -qF "$home/.local/share/bootstrap/scripts/" "$home/.local/share/bootstrap/conventions-core.md"
check "conventions-writer.md references helper scripts" grep -qF "$home/.local/share/bootstrap/scripts/" "$home/.local/share/bootstrap/conventions-writer.md"
check "skills reference helper scripts" grep -rqF "$home/.local/share/bootstrap/scripts/" "$home/.claude/skills"
# Retired workflow rules: resume never stashes; follow-ups are open or deferred, never routed;
# `.git` is a file in a linked worktree, so paths under it come from `git rev-parse --git-path`;
# orchestrated dispatch is T3 Code delegate_task only (no native subagent fallback).
for retired in 'git stash' 'unrouted' 'Route rule' 'Routed Follow-ups' 'belong' '.git/info/exclude' 'invoke_subagent' 'fallback:native'; do
  check_not "installed docs and skills never mention '$retired'" \
    grep -rqF -- "$retired" "$home/.local/share/bootstrap" "$home/.claude/skills"
done
# bs-loop writes the PR placeholder and the fix-commit subject that bs-review-state.py reads; the Gate
# line itself is written by `bs-review-state.py set`, so only these two markers live in prose.
review_state_src="$REPO_DIR/workflows/shared/scripts/bs-review-state.py"
for name in PLACEHOLDER FIX_SUBJECT_SUFFIX; do
  marker="$(sed -n "s/^$name = \"\(.*\)\"\$/\1/p" "$review_state_src" 2>/dev/null || true)"
  check "bs-loop writes the bs-review-state $name" test -n "$marker" -a -n "$(grep -F -- "$marker" "$REPO_DIR/workflows/skills/bs-loop/SKILL.md")"
done
for gate in PASSED BLOCKED_BY_DEFECTS BLOCKED_BY_CI; do
  check "bs-loop and bs-review-state agree on gate $gate" \
    sh -c 'grep -qF "$1" "$2" && grep -qF "$1" "$3"' _ "$gate" "$REPO_DIR/workflows/skills/bs-loop/SKILL.md" "$review_state_src"
done
check "bs-loop writes the Gate line through bs-review-state set" grep -qF 'bs-review-state.py" set ' "$home/.claude/skills/bs-loop/SKILL.md"
check "bs-loop persists triage state through bs-review-state record" grep -qF 'bs-review-state.py" record ' "$home/.claude/skills/bs-loop/SKILL.md"
check "bs-loop reads triage state through bs-review-state get" grep -qF 'bs-review-state.py" get ' "$home/.claude/skills/bs-loop/SKILL.md"
# A stale local base (normal in a worktree) must not leak upstream commits into reviews or Verify.
check "bs-loop branches from and reviews against origin/\$BASE_BRANCH" sh -c \
  'grep -qF "\"origin/\$BASE_BRANCH\"\`" "$1" && grep -qF "with target \`origin/\$BASE_BRANCH\`" "$1"' _ \
  "$home/.claude/skills/bs-loop/SKILL.md"
check "dispatch Verify uses bs-verify-commits" \
  grep -qF "$home/.local/share/bootstrap/scripts/bs-verify-commits" "$home/.local/share/bootstrap/dispatch.md"
check "conventions-core explains a branch held by another worktree" \
  grep -qF 'already used by worktree at' "$home/.local/share/bootstrap/conventions-core.md"
for pair in dispatch.md:bs-plan-state skills/bs-exec/SKILL.md:bs-plan-state skills/bs-exec/SKILL.md:bs-plan-branch \
  dispatch.md:bs-review-state.py skills/bs-loop/SKILL.md:bs-review-state.py skills/bs-exec/SKILL.md:bs-review-state.py \
  recovery.md:bs-review-state.py skills/bs-review/SKILL.md:bs-diff-target dispatch.md:bs-pr-ci dispatch.md:bs-resolve-role \
  dispatch.md:bs-verify-commits skills/bs-probe/SKILL.md:bs-worktree role-reviewer.md:bs-worktree \
  role-verifier.md:bs-worktree role-defect-fixer.md:bs-worktree conventions-core.md:bs-worktree \
  conventions-writer.md:bs-worktree conventions-writer.md:bs-gate-run conventions-writer.md:bs-commit \
  skills/bs-loop/SKILL.md:bs-check-review.py recovery.md:bs-check-review.py; do
  doc="${pair%%:*}" script="${pair##*:}"
  case "$doc" in skills/*) path="$home/.claude/$doc" ;; *) path="$home/.local/share/bootstrap/$doc" ;; esac
  check "$doc calls $script" grep -qF "$home/.local/share/bootstrap/scripts/$script" "$path"
done
# Each role brief is handed to its worker by an orchestrating skill.
for pair in role-implementer.md:bs-loop role-implementer.md:bs-exec role-defect-fixer.md:bs-loop \
  role-verifier.md:bs-loop role-reviewer.md:bs-review; do
  brief="${pair%%:*}" skill="${pair##*:}"
  check "$skill hands out $brief" grep -qF "$home/.local/share/bootstrap/$brief" "$home/.claude/skills/$skill/SKILL.md"
done
if [[ -z "$missing" ]]; then
  pass "rendered skill and doc paths all resolve"
else
  fail "rendered paths that do not exist: ${missing//$'\n'/, }"
fi

# Every tagged cross-file reference `**Name** (doc)` across workflows/ must resolve to a heading
# or bold anchor in the named doc (catches renamed or deleted sections).
if python3 - "$REPO_DIR" <<'PYEOF'
import glob, os, re, sys

repo = sys.argv[1]
docs = {
    "conventions-core": os.path.join(repo, "workflows/shared/conventions-core.md"),
    "conventions-writer": os.path.join(repo, "workflows/shared/conventions-writer.md"),
    "dispatch": os.path.join(repo, "workflows/shared/dispatch.md"),
    "recovery": os.path.join(repo, "workflows/shared/recovery.md"),
    "role-implementer": os.path.join(repo, "workflows/shared/role-implementer.md"),
    "role-defect-fixer": os.path.join(repo, "workflows/shared/role-defect-fixer.md"),
    "role-reviewer": os.path.join(repo, "workflows/shared/role-reviewer.md"),
    "role-verifier": os.path.join(repo, "workflows/shared/role-verifier.md"),
    "AGENTS.md": os.path.join(repo, "scaffold/AGENTS.md"),
}
for p in glob.glob(os.path.join(repo, "workflows/skills/*/SKILL.md")):
    docs[os.path.basename(os.path.dirname(p))] = p

anchors = {}
for name, path in docs.items():
    text = open(path, encoding="utf-8").read()
    found = set()
    for m in re.finditer(r'^#{1,4}\s+(.+?)\s*$', text, re.M):
        found.add(m.group(1).strip())
    # Bold lead-in anchors: `- **Name**:`, `1. **Name**:`, `**Name**:`, `**Name** (`
    for m in re.finditer(r'(?:^|\n)\s*(?:[-*]|\d+\.)?\s*\*\*([^*\n]+?)\*\*(?:[: (]|$)', text):
        found.add(m.group(1).strip().rstrip(':'))
    # Table first-column bold anchors: `| **Name**:`
    for m in re.finditer(r'^\|\s*\*\*([^*\n]+?)\*\*', text, re.M):
        found.add(m.group(1).strip().rstrip(':'))
    anchors[name] = found

non_doc_tags = {"terminal"}
ref_re = re.compile(r'\*\*([^*\n]+?)\*\*\s+\(([A-Za-z0-9._-]+)\)')
errors = []
ref_count = 0
for src in sorted(glob.glob(os.path.join(repo, "workflows/skills/*/SKILL.md")) +
                  glob.glob(os.path.join(repo, "workflows/shared/*.md"))):
    text = open(src, encoding="utf-8").read()
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in ref_re.finditer(line):
            target_label, target_doc = m.group(1).strip(), m.group(2)
            if target_doc in non_doc_tags:
                continue
            ref_count += 1
            if target_doc not in docs:
                rel = os.path.relpath(src, repo)
                errors.append(f"{rel}:{lineno}: unknown doc tag ({target_doc}) on **{target_label}**")
            elif target_label not in anchors[target_doc]:
                rel = os.path.relpath(src, repo)
                errors.append(f"{rel}:{lineno}: **{target_label}** ({target_doc}) not found")

if ref_count == 0:
    print("no tagged cross-file references found", file=sys.stderr)
    sys.exit(1)
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
PYEOF
then
  pass "all tagged cross-file doc references resolve"
else
  fail "broken cross-file doc reference(s) above"
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "[FAIL] $FAILURES check(s) failed."
  exit 1
fi
echo "[PASS] All smoke checks passed."
