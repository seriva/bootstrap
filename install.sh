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

copy_skill() {
  local src="$1"
  local dest="$2"

  if [ -L "$dest" ]; then
    rm -f "$dest"
  fi
  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dest/"
  else
    cp -a "$src/." "$dest/"
  fi
}

for skill_path in "$SKILLS_SRC"/*/; do
  [ -e "$skill_path" ] || continue
  skill_name="$(basename "$skill_path")"
  skill_file="$skill_path/SKILL.md"

  echo "Deploying skill: $skill_name"

  # 1. Google Antigravity
  if [ "$HAS_ANTIGRAVITY" = true ]; then
    target="$HOME/.gemini/config/skills/$skill_name"
    copy_skill "$skill_path" "$target"
    echo "  -> [Antigravity] Installed to ~/.gemini/config/skills/$skill_name"
  fi

  # 2. Claude Code
  if [ "$HAS_CLAUDE" = true ]; then
    # Native Agent Skill format
    claude_skill_target="$HOME/.claude/skills/$skill_name"
    copy_skill "$skill_path" "$claude_skill_target"

    # Slash command shim (~/.claude/commands/<skill>.md)
    claude_cmd_dir="$HOME/.claude/commands"
    mkdir -p "$claude_cmd_dir"
    cat << 'EOF' > "$claude_cmd_dir/$skill_name.md"
Execute the autonomous dev-loop workflow for the following task:
$ARGUMENTS
EOF
    echo "  -> [Claude Code] Installed skill (~/.claude/skills/$skill_name) and command (/dev-loop)"
  fi

  # 3. OpenAI Codex CLI
  if [ "$HAS_CODEX" = true ]; then
    codex_target="$HOME/.codex/skills/$skill_name"
    copy_skill "$skill_path" "$codex_target"
    echo "  -> [Codex] Installed to ~/.codex/skills/$skill_name"
  fi

  # 4. Cursor (MDC Rule)
  if [ "$HAS_CURSOR" = true ]; then
    cursor_rules_dir="$HOME/.cursor/rules"
    mkdir -p "$cursor_rules_dir"
    cat << EOF > "$cursor_rules_dir/$skill_name.mdc"
---
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
globs: *
alwaysApply: false
---

$(cat "$skill_file")
EOF
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
        cat << EOF > "$pdir/$skill_name.prompt.md"
---
name: $skill_name
description: End-to-end autonomous development loop.
---

$(cat "$skill_file")
EOF
        echo "  -> [Copilot] Installed prompt to $pdir/$skill_name.prompt.md"
      fi
    done
  fi
done

echo "=== Installation Finished ==="
