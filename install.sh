#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_CFG="$HOME/.gemini/config"
BIN_DIR="$HOME/.local/bin"
TS="$(date +%Y%m%d-%H%M%S)"

LINKS_ONLY=false
WITH_OPTIONAL=false
UPDATE_ONLY=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --links-only)    LINKS_ONLY=true ;;
    --with-optional) WITH_OPTIONAL=true ;;
    --update)        UPDATE_ONLY=true ;;
    --uninstall)     UNINSTALL=true ;;
    -h|--help)
      cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --links-only     Only create symlinks and copy mcp_config.json (skip upstream installs)
  --with-optional  Also symlink optional modules (cpp-embedded-gem5 rule, academic-tutor skill)
  --update         Update installed upstream MCP servers and git plugins
  --uninstall      Replace repo symlinks with regular file copies (safe before deleting repo)
  -h, --help       Show this help message
EOF
      exit 0
      ;;
    *)
      echo "[ERR] Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

link_item() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "${dst}.bak.${TS}"
    echo "[BACKUP] ${dst} -> ${dst}.bak.${TS}"
  fi
  ln -sfn "$src" "$dst"
  echo "[LINK] ${dst} -> ${src}"
}

unlink_to_copy() {
  local dst="$1"
  if [ -L "$dst" ]; then
    local target
    target="$(readlink -f "$dst")"
    rm "$dst"
    cp -r "$target" "$dst"
    echo "[DETACH] ${dst} is now a standalone copy"
  fi
}

if [ "$UNINSTALL" = true ]; then
  unlink_to_copy "$AGY_CFG/GEMINI.md"
  unlink_to_copy "$AGY_CFG/templates/AGENTS.md.template"
  unlink_to_copy "$AGY_CFG/rules/cpp-embedded-gem5.md"
  unlink_to_copy "$AGY_CFG/skills/academic-tutor"
  for f in "$REPO_DIR"/config/agents/*.md; do
    unlink_to_copy "$AGY_CFG/agents/$(basename "$f")"
  done
  for f in "$REPO_DIR"/bin/ai-*; do
    unlink_to_copy "$BIN_DIR/$(basename "$f")"
  done
  echo "[OK] Symlinks detached. You can now safely move or delete $REPO_DIR."
  exit 0
fi

if [ "$UPDATE_ONLY" = true ]; then
  echo "=== Updating upstream MCP servers & plugins ==="
  command -v npm >/dev/null && npm update -g context-mode repomix
  if [ -d "$AGY_CFG/plugins/gemini-skills/.git" ]; then
    git -C "$AGY_CFG/plugins/gemini-skills" pull --ff-only
  fi
  echo "[INFO] To update RTK: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
  echo "[INFO] To update Matt Pocock skills: npx skills@latest add mattpocock/skills"
  exit 0
fi

echo "=== Linking configuration into $AGY_CFG and $BIN_DIR ==="
mkdir -p "$AGY_CFG"/{agents,rules,skills,templates} "$BIN_DIR"

link_item "$REPO_DIR/config/GEMINI.md" "$AGY_CFG/GEMINI.md"
link_item "$REPO_DIR/config/templates/AGENTS.md.template" "$AGY_CFG/templates/AGENTS.md.template"

for f in "$REPO_DIR"/config/agents/*.md; do
  link_item "$f" "$AGY_CFG/agents/$(basename "$f")"
done

chmod +x "$REPO_DIR"/bin/ai-*
for f in "$REPO_DIR"/bin/ai-*; do
  link_item "$f" "$BIN_DIR/$(basename "$f")"
done

if [ "$WITH_OPTIONAL" = true ]; then
  link_item "$REPO_DIR/config/optional/rules/cpp-embedded-gem5.md" "$AGY_CFG/rules/cpp-embedded-gem5.md"
  link_item "$REPO_DIR/config/optional/skills/academic-tutor" "$AGY_CFG/skills/academic-tutor"
fi

# mcp_config.json is copied (not symlinked) because MCP installers may rewrite it atomically
MCP_DST="$AGY_CFG/mcp_config.json"
if [ ! -f "$MCP_DST" ]; then
  cp "$REPO_DIR/config/mcp_config.json" "$MCP_DST"
  echo "[COPY] $MCP_DST"
elif ! cmp -s "$REPO_DIR/config/mcp_config.json" "$MCP_DST"; then
  cp "$MCP_DST" "${MCP_DST}.bak.${TS}"
  cp "$REPO_DIR/config/mcp_config.json" "$MCP_DST"
  echo "[COPY] Updated $MCP_DST (previous saved to ${MCP_DST}.bak.${TS})"
else
  echo "[SKIP] $MCP_DST already up to date"
fi

if [ "$LINKS_ONLY" = true ]; then
  echo "[OK] Links applied. Reload VS Code window or run /skills reload in agy."
  exit 0
fi

echo "=== Installing upstream tools & skills (from official sources) ==="
if ! command -v npm >/dev/null; then
  echo "[WARN] npm not found. Install Node.js first, then re-run ./install.sh."
else
  command -v context-mode >/dev/null || npm i -g context-mode
  command -v repomix >/dev/null || npm i -g repomix
  context-mode setup || true
fi

if ! command -v rtk >/dev/null; then
  echo "[INFO] Installing RTK (Rust Token Killer) from upstream..."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi
command -v rtk >/dev/null && rtk init --agent antigravity || true

if command -v agy >/dev/null; then
  [ -d "$AGY_CFG/plugins/gemini-skills" ] || agy plugin install https://github.com/google-gemini/gemini-skills
else
  echo "[WARN] agy CLI not found on PATH. Install Antigravity CLI, then run: agy plugin install https://github.com/google-gemini/gemini-skills"
fi

if command -v npx >/dev/null; then
  echo "[INFO] Installing upstream skills (Ponytail + Matt Pocock)..."
  npx --yes skills add https://github.com/dietrichgebert/ponytail --skill ponytail || true
  npx --yes skills@latest add mattpocock/skills || true
fi

echo "[OK] Setup complete. Reload VS Code window (Developer: Reload Window) or run /skills reload in agy."
