#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bootstrap Agentic Workflow Sync Script
# Propagates canonical Part 1 from scaffold/AGENTS.md, standard tool bridge
# files, docs/feature-plan-template.md, and the bootstrap-managed .gitignore
# block to sibling repositories.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(dirname "$SCRIPT_DIR")"
SCAFFOLD_DIR="$SCRIPT_DIR/scaffold"
BOOTSTRAP_AGENTS="$SCAFFOLD_DIR/AGENTS.md"

CHECK=false
DRY_RUN=false
TARGETS=()

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "Usage: $0 [options] [target_dir ...]"
    echo ""
    echo "Synchronizes Part 1 of AGENTS.md, bridge files, docs/feature-plan-template.md,"
    echo "and the bootstrap-managed .gitignore block from the bootstrap repository to"
    echo "sibling repositories."
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
    if [[ -f "$dir/AGENTS.md" ]]; then
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

# Shell values reach Python via env/argv only (quoted heredoc), so target paths
# containing quotes or backslashes cannot break the embedded source.
BOOTSTRAP_AGENTS="$BOOTSTRAP_AGENTS" SCRIPT_DIR="$SCRIPT_DIR" SCAFFOLD_DIR="$SCAFFOLD_DIR" \
CHECK="$CHECK" DRY_RUN="$DRY_RUN" \
python3 - "${TARGETS[@]}" <<'EOF'
import os
import re
import sys

canonical_path = os.environ["BOOTSTRAP_AGENTS"]
self_dir = os.environ["SCRIPT_DIR"]
scaffold_dir = os.environ["SCAFFOLD_DIR"]
check_mode = os.environ["CHECK"] == "true"
dry_run = os.environ["DRY_RUN"] == "true"
has_drift = False
targets = sys.argv[1:]

PART1_RE = re.compile(r"(# Part 1: Agent Workflow\n[\s\S]*?\n---\n)")
GITIGNORE_BLOCK_RE = re.compile(r"# >>> bootstrap-managed\n[\s\S]*?# <<< bootstrap-managed\n")
LEGACY_CURSOR_FILE = ".cursorrules"


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_text(path, content):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def report(label, state):
    """Print one status line; state is 'up to date', 'drift' (dry-run) or 'written'."""
    if state == "up to date":
        print(f"  - {label}: up to date")
    elif state == "drift":
        print(f"  - {label}: [WOULD CREATE/UPDATE]")
    else:
        print(f"  - {label}: CREATED/UPDATED")


def sync_file(label, target_file, content):
    """Make target_file equal content; returns True when drift was found."""
    if os.path.isfile(target_file) and read_text(target_file) == content:
        report(label, "up to date")
        return False
    if dry_run:
        report(label, "drift")
    else:
        write_text(target_file, content)
        report(label, "written")
    return True


canonical_text = read_text(canonical_path)
part1_match = PART1_RE.search(canonical_text)
if not part1_match:
    sys.exit("Error: Could not extract Part 1 from " + canonical_path)
canonical_part1 = part1_match.group(1)

bridge_rel_paths = [
    "CLAUDE.md",
    os.path.join(".cursor", "rules", "agents.mdc"),
    os.path.join(".github", "copilot-instructions.md"),
]
bridges = {}
for rel_path in bridge_rel_paths:
    src_path = os.path.join(scaffold_dir, rel_path)
    if os.path.isfile(src_path):
        bridges[rel_path] = read_text(src_path)

# Managed .gitignore block: everything between the markers (inclusive) in scaffold/.gitignore
managed_gitignore_block = None
scaffold_gitignore = os.path.join(scaffold_dir, ".gitignore")
if os.path.isfile(scaffold_gitignore):
    block_match = GITIGNORE_BLOCK_RE.search(read_text(scaffold_gitignore))
    if block_match:
        managed_gitignore_block = block_match.group(0)
    else:
        print(f"Warning: no bootstrap-managed markers in {scaffold_gitignore}; skipping .gitignore sync")


def sync_gitignore(target_dir):
    """Replace/append/create the managed block; content outside the markers is untouched."""
    target_file = os.path.join(target_dir, ".gitignore")
    existing = read_text(target_file) if os.path.isfile(target_file) else None

    if existing is None:
        new_text = managed_gitignore_block
    else:
        existing_block = GITIGNORE_BLOCK_RE.search(existing)
        if existing_block:
            new_text = existing[:existing_block.start()] + managed_gitignore_block + existing[existing_block.end():]
        else:
            separator = "" if existing == "" or existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
            new_text = existing + separator + managed_gitignore_block

    if existing == new_text:
        report(".gitignore (managed block)", "up to date")
        return False
    if dry_run:
        report(".gitignore (managed block)", "drift")
    else:
        write_text(target_file, new_text)
        report(".gitignore (managed block)", "written")
    return True


def remove_legacy_cursorrules(target_dir):
    """Legacy .cursorrules is superseded by .cursor/rules/agents.mdc; remove only in write mode."""
    legacy_file = os.path.join(target_dir, LEGACY_CURSOR_FILE)
    if not os.path.isfile(legacy_file):
        return False
    if dry_run:
        print(f"  - {LEGACY_CURSOR_FILE}: [WOULD REMOVE] (replaced by .cursor/rules/agents.mdc)")
    else:
        os.remove(legacy_file)
        print(f"  - {LEGACY_CURSOR_FILE}: REMOVED (replaced by .cursor/rules/agents.mdc)")
    return True


for target_dir in targets:
    proj_name = os.path.basename(target_dir)
    agents_path = os.path.join(target_dir, "AGENTS.md")

    print(f"\n[{proj_name}]")
    if not os.path.isfile(agents_path):
        print(f"  - Skipped: AGENTS.md not found in {target_dir}")
        continue

    target_text = read_text(agents_path)
    target_part1_match = PART1_RE.search(target_text)
    if not target_part1_match:
        has_drift = True
        print(f"  - AGENTS.md Part 1: [DRIFT] '# Part 1: Agent Workflow ... ---' markers not found in {agents_path}; fix manually")
    elif target_part1_match.group(1) == canonical_part1:
        print("  - AGENTS.md Part 1: up to date")
    else:
        has_drift = True
        if dry_run:
            print("  - AGENTS.md Part 1: [WOULD UPDATE]")
        else:
            write_text(
                agents_path,
                target_text[:target_part1_match.start(1)]
                + canonical_part1
                + target_text[target_part1_match.end(1):],
            )
            print("  - AGENTS.md Part 1: UPDATED")

    if os.path.abspath(target_dir) == os.path.abspath(self_dir):
        continue

    for rel_path, content in bridges.items():
        if sync_file(rel_path, os.path.join(target_dir, rel_path), content):
            has_drift = True

    if remove_legacy_cursorrules(target_dir):
        has_drift = True

    # Feature plan template (sync if target has docs/ dir)
    template_rel_path = os.path.join("docs", "feature-plan-template.md")
    template_src_path = os.path.join(scaffold_dir, template_rel_path)
    if os.path.isfile(template_src_path) and os.path.isdir(os.path.join(target_dir, "docs")):
        if sync_file(template_rel_path, os.path.join(target_dir, template_rel_path), read_text(template_src_path)):
            has_drift = True

    if managed_gitignore_block is not None and sync_gitignore(target_dir):
        has_drift = True

if check_mode and has_drift:
    print("\n[FAIL] Workflow drift detected across repositories.")
    sys.exit(1)
elif check_mode:
    print("\n[PASS] All repositories are in sync.")

EOF

echo "--------------------------------"
echo "Sync complete."
