#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$DOTFILES_DIR/skills"

echo "=== Universal AI Bootstrap Skills Installer ==="
echo "Scanning available AI tools on this machine..."

# Detection flags
HAS_ANTIGRAVITY=false
HAS_CLAUDE=false
HAS_CODEX=false
HAS_OPENCODE=false
HAS_PI=false
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

if command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] || [ -d "$HOME/.opencode" ]; then
  HAS_OPENCODE=true
  echo "  [✓] OpenCode detected"
else
  echo "  [ ] OpenCode not detected (skipping)"
fi

if command -v pi >/dev/null 2>&1 || [ -d "$HOME/.pi" ]; then
  HAS_PI=true
  echo "  [✓] Pi detected"
else
  echo "  [ ] Pi not detected (skipping)"
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

# Single table of host installation paths (shared by legacy cleanup and skill install)
AGY_SKILLS_DIR="$HOME/.gemini/config/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
CODEX_SKILLS_DIR="$HOME/.codex/skills"
OPENCODE_SKILLS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
PI_SKILLS_DIR="$HOME/.pi/agent/skills"
CURSOR_RULES_DIR="$HOME/.cursor/rules"
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
  "$HAS_OPENCODE|OpenCode|$OPENCODE_SKILLS_DIR"
  "$HAS_PI|Pi|$PI_SKILLS_DIR"
)

# Skills reference sibling installed skills via {{<SKILL_UPPER>_SKILL}} placeholders
# (e.g. {{BS_LOOP_SKILL}}, {{BS_PLAN_SKILL}}), built dynamically across skills/*/.
sed_escape() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

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
  local sed_args=() i
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

# Remove legacy unprefixed skills (design-plan, execute-plan, dev-loop) ONLY when their
# normalized body SHA-256 matches an exact unmodified historical version from bootstrap.
LEGACY_BODY_HASHES=" 000a644529c8f944 003f97d9413ce640 0054a9c8b26372cf 0185dfe6c5ab7b3a 0457b1c756c9b4f5 09360a7f1c2f46a3 09c6722b8aca7e1b 11893b0d3e804bcb 155aedd4fd192712 15994a58f518a691 161ca3bc9d095e92 165333ceaeb8a964 1726e78e8781eaef 17a62633fa1a1072 18f6d9253a209295 1ff95eb1b00d150d 26dca86acb175ca4 2715d8a7361d9c90 2a303e3c717da7b4 2b1743e4dfaabfb3 2cb6c81f8ae7f64b 2d0dc84a784ca120 2d44f825c356ce53 2e7421ea3aee89ce 307ff87aad1ac4dd 309f9158becf3c3c 31a9e0058ac69eab 3272696a553d5d12 38106710ea9000b5 3834f666a4fd68c2 3a4a2592db58fef7 3d5939e2896f6599 3f44a4bd4bc37969 40fdd64f535b56cf 43a34afcbd29c643 44d87c71f2a3a9cb 4d56113344900f8e 4e4dfb7fa8e79399 5690bfa80ddff4cf 5789179f51a2a37d 57ade1aeca77f58a 5e36106def6e464d 61b0bd0c9163ca05 661518c780fde42d 68c1de741cce8b1f 6ae7f5e0b0b1a3bd 6cad2c7f5c1d1d83 6ddcca28fec8bdf1 73940e384859093c 743e6fc40ea672d2 77341aa3e765e0d1 7f0a810e9f37e836 81dba4a25799f598 848e8af6ade2231c 853bcdcc0d9d9980 8c48113e73e4269c 8d636f9ad9b51b56 8d87502222af0254 8f8a85519c4e3038 8fd2eb01e39257a5 8ffbf1677731862f 90f353bdf06f1af1 91a271f24cfe83c7 9c156e274d37413f 9ea8d0b7e82e3dbf a3c42411d03be1a4 a94266f8a1464d7e ae303ac4d25cf0c6 afd1da64e7c2f75b b157f2f1ec4ebf96 b2bea239d1f4be7b b76732b26e382156 bab227bbf3ee77c7 bd1bddc6d0029954 c5520fee0dbece94 c5e4fd3b2b863c16 c7df69bfc1656b32 c8605db65e4497c2 cd79c6d6dee48e79 d705aabf5ca3a6d7 d9d1a872f26725d1 dc46f658003450b7 dd21a10f587874b8 df0a059c72032b67 df6cf4d68fcea520 e11795b2339def61 e5d6163f61be22a4 e6851a8582f23733 e762e724febd38b5 e8bc3261584533b6 ea0f0d5869834245 f4471020450b0c54 f601d9277cc06383 f77110b2038a59c9 f8f3ac5b9cab67e1 fbad6c8a508552e5 fc7f28204a0729c8 0e3038f521714e78 6b20310e72d7ac46 72c4e96710e6116d 736d182778f38f6d a3c33751851d03f1 b4201b2d132e0252 d56f840ac7e9a3d0 df536a1ddd8d2392 f46685c91125055b "

# SHA-256 of stdin as hex: GNU coreutils, else macOS/BSD shasum, else openssl.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_hex() { sha256sum | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_hex() { shasum -a 256 | cut -d' ' -f1; }
elif command -v openssl >/dev/null 2>&1; then
  sha256_hex() { openssl dgst -sha256 -r | cut -d' ' -f1; }
else
  sha256_hex() { return 1; }
  echo "  [!] No sha256sum, shasum or openssl found: legacy design-plan/execute-plan/dev-loop copies are left in place."
fi

# Rendered paths start with $HOME or $XDG_CONFIG_HOME. The path normalization below stops at
# whitespace and quotes, so replace those characters in these prefixes before normalizing.
LEGACY_PATH_PREFIXES=()
for prefix in "${XDG_CONFIG_HOME:-}" "$HOME"; do
  if [ -n "$prefix" ] && [[ "$prefix" == *[[:space:]\`\"\']* ]]; then
    LEGACY_PATH_PREFIXES+=("$prefix")
  fi
done

sanitize_legacy_prefixes() {
  if [ ${#LEGACY_PATH_PREFIXES[@]} -eq 0 ]; then
    cat
    return
  fi
  local content prefix safe
  content="$(cat; printf x)"
  content="${content%x}"
  for prefix in "${LEGACY_PATH_PREFIXES[@]}"; do
    safe=${prefix//[[:space:]\`\"\']/_}
    content=${content//"$prefix"/"$safe"}
  done
  printf '%s' "$content"
}

legacy_body_hash() {
  sanitize_legacy_prefixes \
    | sed -E "s#[^[:space:]\`\"']*dev-loop(/SKILL\.md|\.mdc|\.prompt\.md)#{{DEV_LOOP_SKILL}}#g" \
    | sha256_hex | cut -c1-16
}

is_bootstrap_legacy_file() {
  local file="$1"
  [ -f "$file" ] || return 1
  local h
  if head -n 1 "$file" | grep -q '^---$'; then
    h=$(strip_frontmatter < "$file" | legacy_body_hash) || return 1
    [[ "$LEGACY_BODY_HASHES" == *" $h "* ]] && return 0
    # Installers before 467cfef wrote Cursor/Copilot files as their own frontmatter, a blank
    # line, then the full SKILL.md including its frontmatter: strip that second block too.
    h=$(strip_frontmatter < "$file" | strip_frontmatter | legacy_body_hash) || return 1
  else
    h=$(legacy_body_hash < "$file") || return 1
  fi
  [[ "$LEGACY_BODY_HASHES" == *" $h "* ]]
}

remove_legacy_skill_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  if is_bootstrap_legacy_file "$dir/SKILL.md"; then
    # Refuse to delete if the directory contains anything other than SKILL.md
    if [ -z "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name 'SKILL.md' -print -quit 2>/dev/null)" ]; then
      rm -rf "$dir"
    fi
  fi
}

remove_legacy_file() {
  local file="$1"
  if is_bootstrap_legacy_file "$file"; then
    rm -f "$file"
  fi
}

for legacy in design-plan execute-plan dev-loop; do
  for entry in "${SKILL_DIR_HOSTS[@]}"; do
    IFS='|' read -r enabled _ host_dir <<< "$entry"
    [ "$enabled" = true ] && remove_legacy_skill_dir "$host_dir/$legacy"
  done
  [ "$HAS_CLAUDE" = true ] && remove_legacy_file "$CLAUDE_COMMANDS_DIR/$legacy.md"
  [ "$HAS_CURSOR" = true ] && remove_legacy_file "$CURSOR_RULES_DIR/$legacy.mdc"
  if [ "$HAS_COPILOT" = true ]; then
    for pdir in "${COPILOT_PROMPT_DIRS[@]}"; do
      remove_legacy_file "$pdir/$legacy.prompt.md"
    done
  fi
done

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

  # 1–5. Directory-based Agent Skills hosts (Antigravity, Claude Code, Codex, OpenCode, Pi)
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

  # 6. Cursor (MDC Rule) — description-triggered; no `globs` so it is not auto-attached to every file
  if [ "$HAS_CURSOR" = true ]; then
    mkdir -p "$CURSOR_RULES_DIR"
    {
      printf -- '---\ndescription: "%s"\nalwaysApply: false\n---\n' "$skill_desc_yaml"
      render_skill "$skill_file" "$CURSOR_RULES_DIR/{SKILL}.mdc" | strip_frontmatter
    } > "$CURSOR_RULES_DIR/$skill_name.mdc"
    echo "  -> [Cursor] Installed rule to $CURSOR_RULES_DIR/$skill_name.mdc"
  fi

  # 7. VS Code / GitHub Copilot (Prompt File)
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

echo "=== Installation Finished ==="
