#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$DOTFILES_DIR/skills"

echo "=== Universal AI DevLoop Skills Installer ==="
echo "Scanning available AI tools on this machine..."

# Detection flags
HAS_ANTIGRAVITY=false
HAS_CLAUDE=false
HAS_CODEX=false
HAS_CURSOR=false
HAS_COPILOT=false

if command -v agy >/dev/null 2>&1 || [ -d "$HOME/.gemini" ]; then
  HAS_ANTIGRAVITY=true
  echo "  [✓] Antigravity detected"
else
  echo "  [ ] Antigravity not detected (skipping)"
fi

if command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ]; then
  HAS_CLAUDE=true
  echo "  [✓] Claude Code detected"
else
  echo "  [ ] Claude Code not detected (skipping)"
fi

if command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ]; then
  HAS_CODEX=true
  echo "  [✓] OpenAI Codex detected"
else
  echo "  [ ] OpenAI Codex not detected (skipping)"
fi

if command -v cursor >/dev/null 2>&1 || [ -d "$HOME/.cursor" ] || [ -d "$HOME/.config/Cursor" ]; then
  HAS_CURSOR=true
  echo "  [✓] Cursor detected"
else
  echo "  [ ] Cursor not detected (skipping)"
fi

if command -v code >/dev/null 2>&1 || [ -d "$HOME/.config/Code" ] || [ -d "$HOME/.vscode-server" ] || [ -d "$HOME/.vscode-server-insiders" ] || [ -d "$HOME/.config/github-copilot" ]; then
  HAS_COPILOT=true
  echo "  [✓] VS Code / GitHub Copilot detected"
else
  echo "  [ ] VS Code / GitHub Copilot not detected (skipping)"
fi

echo "---------------------------------------------"

# Skills reference the installed dev-loop skill file via the {{DEV_LOOP_SKILL}}
# placeholder; each host gets its own path substituted at install time.
render_skill() {
  local path
  path=$(printf '%s' "$2" | sed 's/[&|\\]/\\&/g')  # escape sed replacement metacharacters
  sed "s|{{DEV_LOOP_SKILL}}|$path|g" "$1"
}

copy_skill() {
  local src="$1"
  local dest="$2"
  local dev_loop_path="$3"

  if [ -L "$dest" ]; then
    rm -f "$dest"
  fi
  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dest/"
  else
    cp -a "$src/." "$dest/"
  fi
  render_skill "$src/SKILL.md" "$dev_loop_path" > "$dest/SKILL.md"
}

strip_frontmatter() {
  awk 'BEGIN{c=0} /^---$/{if(c<2){c++; next}} c>=2{print}'
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

  # 1. Google Antigravity
  if [ "$HAS_ANTIGRAVITY" = true ]; then
    target="$HOME/.gemini/config/skills/$skill_name"
    copy_skill "$skill_path" "$target" "$HOME/.gemini/config/skills/dev-loop/SKILL.md"
    echo "  -> [Antigravity] Installed to ~/.gemini/config/skills/$skill_name"
  fi

  # 2. Claude Code
  if [ "$HAS_CLAUDE" = true ]; then
    # Native Agent Skill format
    claude_skill_target="$HOME/.claude/skills/$skill_name"
    copy_skill "$skill_path" "$claude_skill_target" "$HOME/.claude/skills/dev-loop/SKILL.md"

    # Slash command shim (~/.claude/commands/<skill>.md)
    claude_cmd_dir="$HOME/.claude/commands"
    mkdir -p "$claude_cmd_dir"
    cat << EOF > "$claude_cmd_dir/$skill_name.md"
Execute the $skill_name workflow for the following input:
\$ARGUMENTS
EOF
    echo "  -> [Claude Code] Installed skill (~/.claude/skills/$skill_name) and command (/$skill_name)"
  fi

  # 3. OpenAI Codex CLI
  if [ "$HAS_CODEX" = true ]; then
    codex_target="$HOME/.codex/skills/$skill_name"
    copy_skill "$skill_path" "$codex_target" "$HOME/.codex/skills/dev-loop/SKILL.md"
    echo "  -> [Codex] Installed to ~/.codex/skills/$skill_name"
  fi

  # 4. Cursor (MDC Rule) — description-triggered; no `globs` so it is not auto-attached to every file
  if [ "$HAS_CURSOR" = true ]; then
    cursor_rules_dir="$HOME/.cursor/rules"
    mkdir -p "$cursor_rules_dir"
    {
      printf -- '---\ndescription: "%s"\nalwaysApply: false\n---\n' "$skill_desc_yaml"
      render_skill "$skill_file" "$cursor_rules_dir/dev-loop.mdc" | strip_frontmatter
    } > "$cursor_rules_dir/$skill_name.mdc"
    echo "  -> [Cursor] Installed rule to ~/.cursor/rules/$skill_name.mdc"
  fi

  # 5. VS Code / GitHub Copilot (Prompt File)
  if [ "$HAS_COPILOT" = true ]; then
    copilot_targets=(
      "$HOME/.config/Code/User/prompts"
      "$HOME/.config/github-copilot/prompts"
      "$HOME/.vscode-server/data/User/prompts"
      "$HOME/.vscode-server-insiders/data/User/prompts"
    )
    for pdir in "${copilot_targets[@]}"; do
      # If parent directory exists, install prompt file there
      parent_dir="$(dirname "$pdir")"
      if [ -d "$parent_dir" ]; then
        mkdir -p "$pdir"
        {
          printf -- '---\nname: %s\ndescription: "%s"\n---\n' "$skill_name" "$skill_desc_yaml"
          render_skill "$skill_file" "$pdir/dev-loop.prompt.md" | strip_frontmatter
        } > "$pdir/$skill_name.prompt.md"
        echo "  -> [Copilot] Installed prompt to $pdir/$skill_name.prompt.md"
      fi
    done
  fi
done

echo "=== Installation Finished ==="
