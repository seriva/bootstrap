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
  check "$profile: CI accepts workflow_dispatch (plan-branch runs)" grep -qE '^  workflow_dispatch:' "$target/.github/workflows/ci.yml"
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

# .gitignore without a managed block: block appended once, legacy broad ignores dropped, own lines kept.
printf 'my-local-dir/\n.claude/\n.codex/\n' > "$target/.gitignore"
check "sync adds the managed block" "$SYNC" "$target"
check "managed block appended once" test "$(grep -c '^# >>> bootstrap-managed$' "$target/.gitignore")" = 1
check_not "legacy broad ignores removed" grep -qxE '\.claude/|\.codex/' "$target/.gitignore"
check "project ignores kept" grep -qx 'my-local-dir/' "$target/.gitignore"
check "--check passes after adding the block" "$SYNC" --check "$target"

echo "== install.sh"
home="$SANDBOX/home"
# Create every host's config dir so all install targets are exercised.
mkdir -p "$home/.gemini" "$home/.claude" "$home/.codex" "$home/.config/opencode" "$home/.pi" \
  "$home/.cursor" "$home/.config/Code/User"
install_env=(env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share")
# Local model override replaces one default and leaves the others alone.
mkdir -p "$home/.config/bootstrap"
echo 'BS_MODEL_CODEX="smoke-override-model"' > "$home/.config/bootstrap/models.env"
check "install succeeds" "${install_env[@]}" "$INSTALL"
check "models.env override is rendered" grep -q 'smoke-override-model' "$home/.local/share/bootstrap/dispatch.md"
default_claude="$(sed -n 's/^BS_MODEL_CLAUDE="\(.*\)"$/\1/p' "$REPO_DIR/workflows/shared/models.env")"
check "non-overridden models keep their defaults" grep -qF "$default_claude" "$home/.local/share/bootstrap/dispatch.md"
check "second install succeeds" "${install_env[@]}" "$INSTALL"

skills=()
for d in "$REPO_DIR"/workflows/skills/*/; do skills+=("$(basename "$d")"); done
for s in "${skills[@]}"; do
  for f in "$home/.gemini/config/skills/$s/SKILL.md" "$home/.claude/skills/$s/SKILL.md" \
    "$home/.claude/commands/$s.md" "$home/.codex/skills/$s/SKILL.md" \
    "$home/.config/opencode/skills/$s/SKILL.md" "$home/.pi/agent/skills/$s/SKILL.md" \
    "$home/.cursor/rules/$s.mdc" "$home/.config/Code/User/prompts/$s.prompt.md"; do
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
missing="$(grep -rhoE "$home/[^\`\"' )]+\.(md|mdc)" "$home" | sort -u | while IFS= read -r p; do
  [[ -f "$p" ]] || echo "$p"
done)"
missing+="$(grep -rhoE "$home/[^\`\"' )]+/scripts/[A-Za-z0-9_-]+" "$home" | sort -u | while IFS= read -r p; do
  [[ -x "$p" ]] || echo "$p"
done)"
check "conventions.md references helper scripts" grep -qF "$home/.local/share/bootstrap/scripts/" "$home/.local/share/bootstrap/conventions.md"
check "skills reference helper scripts" grep -rqF "$home/.local/share/bootstrap/scripts/" "$home/.claude/skills"
# bs-review-state reads the markers /bs-loop writes: both must match its constants.
review_state_src="$REPO_DIR/workflows/shared/scripts/bs-review-state"
for name in PLACEHOLDER FIX_SUBJECT_SUFFIX; do
  marker="$(sed -n "s/^$name='\(.*\)'\$/\1/p" "$review_state_src" 2>/dev/null || true)"
  check "bs-loop writes the bs-review-state $name" test -n "$marker" -a -n "$(grep -F -- "$marker" "$REPO_DIR/workflows/skills/bs-loop/SKILL.md")"
done
check "bs-loop writes the **Gate:** line bs-review-state reads" grep -qF '`**Gate:** <PASSED' "$REPO_DIR/workflows/skills/bs-loop/SKILL.md"
for pair in conventions.md:bs-plan-state skills/bs-exec/SKILL.md:bs-plan-state skills/bs-exec/SKILL.md:bs-plan-ci \
  conventions.md:bs-review-state skills/bs-loop/SKILL.md:bs-review-state skills/bs-exec/SKILL.md:bs-review-state \
  skills/bs-review/SKILL.md:bs-diff-target; do
  doc="${pair%%:*}" script="${pair##*:}"
  case "$doc" in skills/*) path="$home/.claude/$doc" ;; *) path="$home/.local/share/bootstrap/$doc" ;; esac
  check "$doc calls $script" grep -qF "$home/.local/share/bootstrap/scripts/$script" "$path"
done
if [[ -z "$missing" ]]; then
  pass "rendered skill and doc paths all resolve"
else
  fail "rendered paths that do not exist: ${missing//$'\n'/, }"
fi

echo "== size budgets"
# Byte budgets for the skill and shared-doc text every bs-* run loads. Raising one is a
# deliberate, visible change here; a new file needs its own entry.
budget_of() {
  case "$1" in
    skills/bs-exec/SKILL.md) echo 10750 ;;
    skills/bs-loop/SKILL.md) echo 9000 ;;
    skills/bs-plan/SKILL.md) echo 9250 ;;
    skills/bs-probe/SKILL.md) echo 2250 ;;
    skills/bs-review/SKILL.md) echo 6500 ;;
    skills/bs-task/SKILL.md) echo 4250 ;;
    shared/conventions.md) echo 7500 ;;
    shared/dispatch.md) echo 9500 ;;
    *) echo 0 ;;
  esac
}
TOTAL_BUDGET=58250
total=0
for f in "$REPO_DIR"/workflows/skills/*/SKILL.md "$REPO_DIR"/workflows/shared/*.md; do
  rel="${f#"$REPO_DIR"/workflows/}"
  size="$(wc -c < "$f" | tr -d ' ')"
  budget="$(budget_of "$rel")"
  total=$((total + size))
  if [[ "$size" -le "$budget" ]]; then
    pass "$rel within budget ($size/$budget bytes)"
  else
    fail "$rel is $size bytes, over its budget of $budget (tests/smoke.sh budget_of)"
  fi
done
if [[ "$total" -le "$TOTAL_BUDGET" ]]; then
  pass "skills and shared docs total $total/$TOTAL_BUDGET bytes"
else
  fail "skills and shared docs total $total bytes, over $TOTAL_BUDGET"
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "[FAIL] $FAILURES check(s) failed."
  exit 1
fi
echo "[PASS] All smoke checks passed."
