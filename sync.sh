#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bootstrap Agentic Workflow Sync Script
# Propagates canonical Part 1 from bootstrap/AGENTS.md, standard tool bridge
# files, and docs/feature-plan-template.md to sibling repositories.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(dirname "$SCRIPT_DIR")"
BOOTSTRAP_AGENTS="$SCRIPT_DIR/AGENTS.md"

CHECK=false
DRY_RUN=false
TARGETS=()

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "Usage: $0 [options] [target_dir ...]"
    echo ""
    echo "Synchronizes Part 1 of AGENTS.md, bridge files, and docs/feature-plan-template.md"
    echo "from the bootstrap repository to sibling repositories."
    echo ""
    echo "Options:"
    echo "  -c, --check    Check targets for drift; exit 1 if drift detected, 0 if clean"
    echo "  -n, --dry-run  Preview changes without modifying files"
    echo "  -h, --help     Show this help message and exit"
    echo ""
    echo "Arguments:"
    echo "  target_dir     Specific target repo directory or path to its AGENTS.md"
    echo "                 (defaults to all sibling directories containing AGENTS.md)"
    exit 0
  elif [[ "$arg" == "--check" || "$arg" == "-c" ]]; then
    CHECK=true
    DRY_RUN=true
  elif [[ "$arg" == "--dry-run" || "$arg" == "-n" ]]; then
    DRY_RUN=true
  elif [[ -d "$arg" ]]; then
    TARGETS+=("$(cd "$arg" && pwd)")
  elif [[ -f "$arg" && "$(basename "$arg")" == "AGENTS.md" ]]; then
    TARGETS+=("$(cd "$(dirname "$arg")" && pwd)")
  else
    echo "Unknown argument: $arg"
    echo "Usage: $0 [--check|-c] [--dry-run|-n] [--help|-h] [target_dir ...]"
    exit 1
  fi
done

# If no specific targets provided, auto-discover sibling projects with AGENTS.md
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  for dir in "$DEV_DIR"/*/; do
    dir="${dir%/}"
    if [[ "$dir" != "$SCRIPT_DIR" && -f "$dir/AGENTS.md" ]]; then
      TARGETS+=("$dir")
    fi
  done
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "No target repositories with AGENTS.md found."
  exit 0
fi

echo "=== Bootstrap Workflow Sync ==="
echo "Source: $BOOTSTRAP_AGENTS"
if [[ "$CHECK" == true ]]; then
  echo "Mode:   CHECK (fails with exit code 1 if drift detected)"
elif [[ "$DRY_RUN" == true ]]; then
  echo "Mode:   DRY RUN (no changes written)"
fi
echo "Targets: ${#TARGETS[@]} repositories"
echo "--------------------------------"

python3 - <<EOF
import os
import re
import sys

canonical_path = "$BOOTSTRAP_AGENTS"
check_mode = ("$CHECK" == "true")
dry_run = ("$DRY_RUN" == "true")
has_drift = False
targets = [$(printf '"%s", ' "${TARGETS[@]}")]

with open(canonical_path, "r", encoding="utf-8") as f:
    canonical_text = f.read()

# Extract Part 1 block from bootstrap
part1_match = re.search(r"(# Part 1: Agent Workflow\n[\s\S]*?\n---\n)", canonical_text)
if not part1_match:
    sys.exit("Error: Could not extract Part 1 from " + canonical_path)

canonical_part1 = part1_match.group(1)

bridge_rel_paths = [
    "CLAUDE.md",
    ".cursorrules",
    os.path.join(".github", "copilot-instructions.md"),
]
bridges = {}
for rel_path in bridge_rel_paths:
    src_path = os.path.join("$SCRIPT_DIR", rel_path)
    if os.path.isfile(src_path):
        with open(src_path, "r", encoding="utf-8") as f:
            bridges[rel_path] = f.read()

for target_dir in targets:
    proj_name = os.path.basename(target_dir)
    agents_path = os.path.join(target_dir, "AGENTS.md")

    print(f"\n[{proj_name}]")
    if not os.path.isfile(agents_path):
        print(f"  - Skipped: AGENTS.md not found in {target_dir}")
        continue

    with open(agents_path, "r", encoding="utf-8") as f:
        target_text = f.read()

    # Match target Part 1 block
    target_part1_match = re.search(r"(# Part 1: Agent Workflow\n[\s\S]*?\n---\n)", target_text)
    if not target_part1_match:
        print(f"  - Warning: Could not locate '# Part 1: Agent Workflow ... ---' in {agents_path}")
    else:
        existing_part1 = target_part1_match.group(1)
        if existing_part1 == canonical_part1:
            print("  - AGENTS.md Part 1: up to date")
        else:
            has_drift = True
            if dry_run:
                print("  - AGENTS.md Part 1: [WOULD UPDATE]")
            else:
                new_target_text = (
                    target_text[:target_part1_match.start(1)]
                    + canonical_part1
                    + target_text[target_part1_match.end(1):]
                )
                with open(agents_path, "w", encoding="utf-8") as f:
                    f.write(new_target_text)
                print("  - AGENTS.md Part 1: UPDATED")

    # Bridge files
    for rel_path, content in bridges.items():
        bridge_file = os.path.join(target_dir, rel_path)
        parent_dir = os.path.dirname(bridge_file)

        already_valid = False
        if os.path.isfile(bridge_file):
            with open(bridge_file, "r", encoding="utf-8") as f:
                if f.read() == content:
                    already_valid = True

        if already_valid:
            print(f"  - {rel_path}: up to date")
        else:
            has_drift = True
            if dry_run:
                print(f"  - {rel_path}: [WOULD CREATE/UPDATE]")
            else:
                if parent_dir:
                    os.makedirs(parent_dir, exist_ok=True)
                with open(bridge_file, "w", encoding="utf-8") as f:
                    f.write(content)
                print(f"  - {rel_path}: CREATED/UPDATED")

    # Feature plan template (sync if target has docs/ dir)
    template_rel_path = os.path.join("docs", "feature-plan-template.md")
    template_src_path = os.path.join("$SCRIPT_DIR", template_rel_path)
    target_docs_dir = os.path.join(target_dir, "docs")
    if os.path.isfile(template_src_path) and os.path.isdir(target_docs_dir):
        with open(template_src_path, "r", encoding="utf-8") as f:
            template_content = f.read()

        template_target_file = os.path.join(target_dir, template_rel_path)
        already_valid = False
        if os.path.isfile(template_target_file):
            with open(template_target_file, "r", encoding="utf-8") as f:
                if f.read() == template_content:
                    already_valid = True

        if already_valid:
            print(f"  - {template_rel_path}: up to date")
        else:
            has_drift = True
            if dry_run:
                print(f"  - {template_rel_path}: [WOULD CREATE/UPDATE]")
            else:
                with open(template_target_file, "w", encoding="utf-8") as f:
                    f.write(template_content)
                print(f"  - {template_rel_path}: CREATED/UPDATED")

if check_mode and has_drift:
    print("\n[FAIL] Workflow drift detected across repositories.")
    sys.exit(1)
elif check_mode:
    print("\n[PASS] All repositories are in sync.")

EOF

echo "--------------------------------"
echo "Sync complete."
