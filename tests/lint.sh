#!/usr/bin/env bash
set -euo pipefail

# Lint every shell and Python script in the repo: bash -n on Bash scripts, ShellCheck
# (warnings and errors; style/info notes are advisory) on all shell scripts, and Python
# syntax compilation on all .py / python3-shebang scripts (without writing .pyc files).
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
sh_files=()
bash_files=()
py_files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  first=""
  IFS= read -r first <"$f" || true
  if [[ "$first" =~ ^#!.*[/[:space:]](ba)?sh([[:space:]]|$) ]]; then
    sh_files+=("$f")
    [[ "$first" =~ ^#!.*[/[:space:]]bash([[:space:]]|$) ]] && bash_files+=("$f")
  elif [[ "$f" == *.py || "$first" =~ ^#!.*[/[:space:]]python3?([[:space:]]|$) ]]; then
    py_files+=("$f")
  fi
done < <(git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -z)
[ "${#sh_files[@]}" -gt 0 ] || { echo "lint: no shell scripts found" >&2; exit 2; }

if [ "${#bash_files[@]}" -gt 0 ]; then
  bash -n "${bash_files[@]}"
  echo "[PASS] bash -n clean (${#bash_files[@]} scripts)."
fi

"$SHELLCHECK" --version | sed -n 2p
"$SHELLCHECK" --severity=warning --external-sources "${sh_files[@]}"
echo "[PASS] ShellCheck clean (${#sh_files[@]} scripts)."

if [ "${#py_files[@]}" -gt 0 ]; then
  python3 - "${py_files[@]}" <<'PY'
import sys
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as f:
        compile(f.read(), path, "exec")
PY
  echo "[PASS] Python syntax clean (${#py_files[@]} scripts)."
fi
