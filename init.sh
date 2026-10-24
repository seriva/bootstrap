#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bootstrap Project Initializer
# Scaffolds a new project with clean, profile-specific templates (Continuous or Versioned).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD_DIR="$SCRIPT_DIR/scaffold"
TEMPLATES_DIR="$SCAFFOLD_DIR/templates"

show_help() {
  cat <<EOF
Usage: $0 <target_directory> [options]

Initializes a new project with the agentic workflow bootstrap standard.

Arguments:
  target_directory    Directory to initialize (created if it does not exist)

Options:
  -t, --type TYPE     Project release model: 'continuous' (default) or 'versioned'
  -f, --force         Overwrite scaffold files that already exist in the target
  -h, --help          Show this help message and exit

Examples:
  $0 ~/dev/my-website --type continuous
  $0 ~/dev/my-compiler --type versioned
EOF
  exit "${1:-0}"
}

TARGET_DIR=""
PROJECT_TYPE="continuous"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -t|--type)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --type requires an argument ('continuous' or 'versioned')" >&2
        exit 1
      fi
      PROJECT_TYPE="$2"
      shift 2
      ;;
    --type=*)
      PROJECT_TYPE="${1#--type=}"
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
        shift
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: Target directory required." >&2
  show_help 1 >&2
fi

if [[ "$PROJECT_TYPE" != "continuous" && "$PROJECT_TYPE" != "versioned" ]]; then
  echo "Error: Invalid project type '$PROJECT_TYPE'. Must be 'continuous' or 'versioned'." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# target path (relative to TARGET_DIR) -> source path
FILES=(
  "AGENTS.md|$SCAFFOLD_DIR/AGENTS.md"
  "CLAUDE.md|$SCAFFOLD_DIR/CLAUDE.md"
  "lefthook.yml|$SCAFFOLD_DIR/lefthook.yml"
  ".gitignore|$SCAFFOLD_DIR/.gitignore"
  ".github/dependabot.yml|$SCAFFOLD_DIR/.github/dependabot.yml"
  ".github/copilot-instructions.md|$SCAFFOLD_DIR/.github/copilot-instructions.md"
  ".github/workflows/ci.yml|$SCAFFOLD_DIR/.github/workflows/ci.yml"
  "plans/template.md|$SCAFFOLD_DIR/plans/template.md"
  "plans/follow-ups.md|$SCAFFOLD_DIR/plans/follow-ups.md"
  "CHANGELOG.md|$TEMPLATES_DIR/$PROJECT_TYPE/CHANGELOG.md"
  "plans/roadmap.md|$TEMPLATES_DIR/$PROJECT_TYPE/roadmap.md"
)

if [[ "$FORCE" != true ]]; then
  existing=()
  for entry in "${FILES[@]}"; do
    rel="${entry%%|*}"
    if [[ -e "$TARGET_DIR/$rel" ]]; then existing+=("$rel"); fi
  done
  if [[ ${#existing[@]} -gt 0 ]]; then
    echo "Error: these files already exist in $TARGET_DIR:" >&2
    printf '  %s\n' "${existing[@]}" >&2
    echo "Re-run with --force to overwrite them." >&2
    exit 1
  fi
fi

echo "=== Initializing Project Scaffold ==="
echo "Target:  $TARGET_DIR"
echo "Profile: $PROJECT_TYPE"
echo "-------------------------------------"

# 1. Scaffold + profile files
echo "Copying workflow scaffold ($PROJECT_TYPE profile)..."
for entry in "${FILES[@]}"; do
  rel="${entry%%|*}"
  mkdir -p "$(dirname "$TARGET_DIR/$rel")"
  cp "${entry#*|}" "$TARGET_DIR/$rel"
done

if [[ "$PROJECT_TYPE" == "continuous" ]]; then
  mkdir -p "$TARGET_DIR/plans/archive"
  touch "$TARGET_DIR/plans/archive/.gitkeep"
  release_model="Continuous"
else
  release_model="Semantic Versioning"
fi
# Temp file instead of `sed -i`, whose syntax differs between GNU and BSD/macOS sed.
sed "s/- \*\*Release Model\*\*: \[.*\]/- **Release Model**: $release_model/" "$TARGET_DIR/AGENTS.md" > "$TARGET_DIR/AGENTS.md.tmp"
mv "$TARGET_DIR/AGENTS.md.tmp" "$TARGET_DIR/AGENTS.md"

# 2. Git repo check
if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "Initializing git repository..."
  git -C "$TARGET_DIR" init -q
fi

echo "-------------------------------------"
echo "Project initialized successfully!"
echo ""
echo "Next steps:"
echo "  1. Fill in Part 2 of $TARGET_DIR/AGENTS.md (Tech Stack & Commands)"
echo "  2. Configure $TARGET_DIR/lefthook.yml with format/lint/test commands"
echo "  3. Replace [INSTALL_COMMAND] and the runtime setup in .github/workflows/ci.yml"
echo "  4. Adjust .github/dependabot.yml (remove the npm entry if the project does not use npm)"
echo "  5. Install lefthook and gitleaks (>= 8.19), then run 'lefthook install' in $TARGET_DIR"

