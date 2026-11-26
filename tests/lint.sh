#!/usr/bin/env bash
set -euo pipefail

# Lint every shell script in the repo with ShellCheck (warnings and errors; style/info notes are
# advisory). Scripts are found by their first-line shebang so extensionless helpers are covered too.
# Usage: tests/lint.sh   (SHELLCHECK=/path/to/shellcheck to pick a binary)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLCHECK="${SHELLCHECK:-shellcheck}"

command -v "$SHELLCHECK" >/dev/null 2>&1 || {
  echo "lint: shellcheck not found (install it, or set SHELLCHECK=/path/to/shellcheck)" >&2
  exit 2
}
# A relative path must survive the cd below.
case "$SHELLCHECK" in
  */*) SHELLCHECK="$(cd "$(dirname "$SHELLCHECK")" && pwd)/$(basename "$SHELLCHECK")" ;;
esac

cd "$REPO_DIR"
files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  first=""
  IFS= read -r first <"$f" || true
  [[ "$first" =~ ^#!.*[/[:space:]](ba)?sh([[:space:]]|$) ]] && files+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -z)
[ "${#files[@]}" -gt 0 ] || { echo "lint: no shell scripts found" >&2; exit 2; }

"$SHELLCHECK" --version | sed -n 2p
"$SHELLCHECK" --severity=warning --external-sources "${files[@]}"
echo "[PASS] ShellCheck clean (${#files[@]} scripts)."
