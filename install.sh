#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$DOTFILES_DIR/workflows/skills"
SHARED_SRC="$DOTFILES_DIR/workflows/shared"
BOOTSTRAP_SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bootstrap"
BOOTSTRAP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bootstrap"

# Load default paired models, with optional local user override
# shellcheck source=workflows/shared/models.env
source "$SHARED_SRC/models.env"
if [ -f "$BOOTSTRAP_CONFIG_DIR/models.env" ]; then
  # shellcheck disable=SC1091
  source "$BOOTSTRAP_CONFIG_DIR/models.env"
fi

echo "=== Universal AI Bootstrap Skills Installer ==="
echo "Scanning available AI tools on this machine..."

# detect <label> <command> <dir>...: succeeds when <command> is on PATH or any <dir> exists.
detect() {
  local label="$1" cmd="$2" dir
  shift 2
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  [✓] $label detected"
    return 0
  fi
  for dir in "$@"; do
    if [ -d "$dir" ]; then
      echo "  [✓] $label detected"
      return 0
    fi
  done
  echo "  [ ] $label not detected (skipping)"
  return 1
}

HAS_ANTIGRAVITY=false HAS_CLAUDE=false HAS_CODEX=false HAS_COPILOT=false
detect "Antigravity" agy "$HOME/.gemini" && HAS_ANTIGRAVITY=true
detect "Claude Code" claude "$HOME/.claude" && HAS_CLAUDE=true
detect "OpenAI Codex" codex "$HOME/.codex" && HAS_CODEX=true
detect "VS Code / GitHub Copilot" code "$HOME/.config/Code" "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" "$HOME/.config/github-copilot" && HAS_COPILOT=true

echo "---------------------------------------------"

# Host installation paths
AGY_SKILLS_DIR="$HOME/.gemini/config/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
CODEX_SKILLS_DIR="$HOME/.codex/skills"
COPILOT_PROMPT_DIRS=(
  "$HOME/.config/Code/User/prompts"
  "$HOME/.config/github-copilot/prompts"
  "$HOME/.vscode-server/data/User/prompts"
  "$HOME/.vscode-server-insiders/data/User/prompts"
)

# Directory-based Agent Skills hosts: "FLAG|LABEL|SKILLS_DIR"
SKILL_DIR_HOSTS=(
  "$HAS_ANTIGRAVITY|Antigravity|$AGY_SKILLS_DIR"
  "$HAS_CLAUDE|Claude Code|$CLAUDE_SKILLS_DIR"
  "$HAS_CODEX|Codex|$CODEX_SKILLS_DIR"
)

# Skills reference sibling installed skills via {{<SKILL_UPPER>_SKILL}} placeholders
# (e.g. {{BS_LOOP_SKILL}}, {{BS_PLAN_SKILL}}), built dynamically across workflows/skills/*/,
# plus shared docs and default paired models.
sed_escape() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

SHARED_SED_ARGS=(
  -e "s|{{BS_CONVENTIONS}}|$(sed_escape "$BOOTSTRAP_SHARE_DIR/conventions.md")|g"
  -e "s|{{BS_DISPATCH}}|$(sed_escape "$BOOTSTRAP_SHARE_DIR/dispatch.md")|g"
  -e "s|{{BS_MODEL_CLAUDE}}|$(sed_escape "$BS_MODEL_CLAUDE")|g"
  -e "s|{{BS_MODEL_AGY}}|$(sed_escape "$BS_MODEL_AGY")|g"
  -e "s|{{BS_MODEL_CODEX}}|$(sed_escape "$BS_MODEL_CODEX")|g"
)
# Helper scripts are referenced as {{<NAME_UPPER>}} (bs-commit -> {{BS_COMMIT}}). Added before
# the shared docs are rendered, because conventions.md references them too.
for script_path in "$SHARED_SRC"/scripts/*; do
  [ -f "$script_path" ] || continue
  script_name="$(basename "$script_path")"
  script_key="$(printf '%s' "$script_name" | tr '[:lower:]-' '[:upper:]_')"
  SHARED_SED_ARGS+=(-e "s|{{${script_key}}}|$(sed_escape "$BOOTSTRAP_SHARE_DIR/scripts/$script_name")|g")
done

# Install helper scripts, shared conventions, and dispatch rules once per user
mkdir -p "$BOOTSTRAP_SHARE_DIR/scripts"
for script_path in "$SHARED_SRC"/scripts/*; do
  [ -f "$script_path" ] || continue
  cp "$script_path" "$BOOTSTRAP_SHARE_DIR/scripts/"
  chmod 755 "$BOOTSTRAP_SHARE_DIR/scripts/$(basename "$script_path")"
done
for doc_path in "$SHARED_SRC"/*.md; do
  [ -f "$doc_path" ] || continue
  doc_name="$(basename "$doc_path")"
  sed "${SHARED_SED_ARGS[@]}" "$doc_path" > "$BOOTSTRAP_SHARE_DIR/$doc_name"
done
# The share dir holds only what this installer puts there: drop scripts and docs the repo no longer ships.
for installed_path in "$BOOTSTRAP_SHARE_DIR"/scripts/* "$BOOTSTRAP_SHARE_DIR"/*.md; do
  [ -f "$installed_path" ] || continue
  if [ ! -f "$SHARED_SRC/${installed_path#"$BOOTSTRAP_SHARE_DIR"/}" ]; then
    rm -f "$installed_path"
    echo "Removed stale $installed_path"
  fi
done
echo "Installed shared docs and helper scripts to $BOOTSTRAP_SHARE_DIR"
echo "  Models: claude=$BS_MODEL_CLAUDE, agy=$BS_MODEL_AGY, codex=$BS_MODEL_CODEX"

# Skill names and their placeholder keys, computed once (only the path pattern varies per render).
SKILL_NAMES=()
SKILL_KEYS=()
for s_dir in "$SKILLS_SRC"/*/; do
  [ -e "$s_dir" ] || continue
  s_name="$(basename "$s_dir")"
  SKILL_NAMES+=("$s_name")
  SKILL_KEYS+=("$(printf '%s' "$s_name" | tr '[:lower:]-' '[:upper:]_')_SKILL")
done

render_skill() {
  local src_file="$1"
  local pattern
  pattern=$(sed_escape "$2")
  local sed_args=("${SHARED_SED_ARGS[@]}") i
  for i in "${!SKILL_NAMES[@]}"; do
    sed_args+=(-e "s|{{${SKILL_KEYS[$i]}}}|${pattern//\{SKILL\}/${SKILL_NAMES[$i]}}|g")
  done
  sed "${sed_args[@]}" "$src_file"
}

copy_skill() {
  local src="$1"
  local dest="$2"
  local path_pattern="$3"

  if [ -L "$dest" ]; then
    rm -f "$dest"
  fi
  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dest/"
  else
    cp -a "$src/." "$dest/"
  fi
  render_skill "$src/SKILL.md" "$path_pattern" > "$dest/SKILL.md"
}

strip_frontmatter() {
  awk 'BEGIN{c=0} /^---$/{if(c<2){c++; next}} c>=2{print}'
}

# Host dirs are shared with the user's own skills, so only names this installer owns are pruned:
# the bs-* prefix and the skill names used before the bs-* rename.
RETIRED_SKILL_NAMES=(design-plan execute-plan dev-loop)

# prune_stale <dir> <suffix>: remove installer-owned entries (<skill><suffix>) of skills no longer shipped.
prune_stale() {
  local dir="$1" suffix="$2" path name current stale
  [ -d "$dir" ] || return 0
  local candidates=("$dir"/bs-*"$suffix")
  for name in "${RETIRED_SKILL_NAMES[@]}"; do
    candidates+=("$dir/$name$suffix")
  done
  for path in "${candidates[@]}"; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    name="$(basename "$path")"
    name="${name%"$suffix"}"
    stale=true
    for current in "${SKILL_NAMES[@]}"; do
      if [ "$current" = "$name" ]; then stale=false; fi
    done
    if [ "$stale" = true ]; then
      rm -rf "$path"
      echo "Removed stale $path"
    fi
  done
}

for skill_path in "$SKILLS_SRC"/*/; do
  [ -e "$skill_path" ] || continue
  skill_name="$(basename "$skill_path")"
  skill_file="$skill_path/SKILL.md"
  # Raw frontmatter value: strip one pair of surrounding quotes if present, then
  # escape backslashes and embedded double quotes so the emitted `description: "%s"`
  # is valid YAML even when the text contains `: `.
  skill_desc=$(grep -E "^description:" "$skill_file" 2>/dev/null | head -n 1 | sed -e 's/^description:[[:space:]]*//' -e 's/^"\(.*\)"$/\1/' || true)
  skill_desc=${skill_desc:-"Autonomous $skill_name workflow"}
  skill_desc_yaml=$(printf '%s' "$skill_desc" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

  echo "Deploying skill: $skill_name"

  # 1–3. Directory-based Agent Skills hosts (Antigravity, Claude Code, Codex)
  for entry in "${SKILL_DIR_HOSTS[@]}"; do
    IFS='|' read -r enabled label host_dir <<< "$entry"
    [ "$enabled" = true ] || continue
    copy_skill "$skill_path" "$host_dir/$skill_name" "$host_dir/{SKILL}/SKILL.md"
    if [ "$label" = "Claude Code" ]; then
      mkdir -p "$CLAUDE_COMMANDS_DIR"
      cat << EOF > "$CLAUDE_COMMANDS_DIR/$skill_name.md"
Execute the $skill_name workflow for the following input:
\$ARGUMENTS
EOF
      echo "  -> [$label] Installed skill ($host_dir/$skill_name) and command (/$skill_name)"
    else
      echo "  -> [$label] Installed to $host_dir/$skill_name"
    fi
  done

  # 4. VS Code / GitHub Copilot (Prompt File)
  if [ "$HAS_COPILOT" = true ]; then
    for pdir in "${COPILOT_PROMPT_DIRS[@]}"; do
      parent_dir="$(dirname "$pdir")"
      if [ -d "$parent_dir" ]; then
        mkdir -p "$pdir"
        {
          printf -- '---\nname: %s\ndescription: "%s"\n---\n' "$skill_name" "$skill_desc_yaml"
          render_skill "$skill_file" "$pdir/{SKILL}.prompt.md" | strip_frontmatter
        } > "$pdir/$skill_name.prompt.md"
        echo "  -> [Copilot] Installed prompt to $pdir/$skill_name.prompt.md"
      fi
    done
  fi
done

for entry in "${SKILL_DIR_HOSTS[@]}"; do
  IFS='|' read -r enabled label host_dir <<< "$entry"
  [ "$enabled" = true ] || continue
  prune_stale "$host_dir" ""
done
if [ "$HAS_CLAUDE" = true ]; then
  prune_stale "$CLAUDE_COMMANDS_DIR" ".md"
fi
if [ "$HAS_COPILOT" = true ]; then
  for pdir in "${COPILOT_PROMPT_DIRS[@]}"; do
    prune_stale "$pdir" ".prompt.md"
  done
fi

echo "=== Installation Finished ==="
