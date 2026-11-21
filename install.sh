#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_CFG="$HOME/.gemini/config"
BIN_DIR="$HOME/.local/bin"
TS="$(date +%Y%m%d-%H%M%S)"

LINKS_ONLY=false
WITH_OPTIONAL=false
MINIMAL=false
DOCTOR=false
UPDATE_ONLY=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --links-only)    LINKS_ONLY=true ;;
    --with-optional) WITH_OPTIONAL=true ;;
    --minimal)       MINIMAL=true ;;
    --doctor)        DOCTOR=true ;;
    --update)        UPDATE_ONLY=true ;;
    --uninstall)     UNINSTALL=true ;;
    -h|--help)
      cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --minimal        Lightweight profile (GEMINI.md, RTK, Ponytail, ai-*, code-auditor, test-runner, remote docs MCP)
  --links-only     Only create symlinks and copy mcp_config.json (skip upstream installs)
  --with-optional  Also symlink optional modules (cpp-embedded-gem5 rule, academic-tutor skill)
  --doctor         Run health check on symlinks, RTK, MCP config, binaries, and live agy model IDs
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
    if [ ! -e "$dst" ]; then
      rm "$dst"
      echo "[CLEAN] Removed dangling symlink ${dst}"
      return
    fi
    local target
    target="$(readlink -f "$dst")"
    rm "$dst"
    cp -r "$target" "$dst"
    echo "[DETACH] ${dst} is now a standalone copy"
  fi
}

copy_mcp_file() {
  local src="$1" dst="$AGY_CFG/mcp_config.json"
  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"
    echo "[COPY] $dst"
  elif ! cmp -s "$src" "$dst"; then
    cp "$dst" "${dst}.bak.${TS}"
    cp "$src" "$dst"
    echo "[COPY] Updated $dst (previous saved to ${dst}.bak.${TS})"
  else
    echo "[SKIP] $dst already up to date"
  fi
}

run_doctor() {
  local fails=0 warns=0
  pass() { echo "[PASS] $*"; }
  warn() { echo "[WARN] $*"; warns=$((warns + 1)); }
  fail() { echo "[FAIL] $*"; fails=$((fails + 1)); }

  check_link() {
    local dst="$1" required="$2"
    if [ -L "$dst" ] && [ ! -e "$dst" ]; then
      fail "Dangling symlink: $dst"
    elif [ -L "$dst" ]; then
      pass "Symlink OK: $dst -> $(readlink "$dst")"
    elif [ -e "$dst" ]; then
      warn "Regular file (not symlinked to repo): $dst"
    elif [ "$required" = "required" ]; then
      fail "Missing: $dst"
    else
      echo "[INFO] Optional/full-profile item not installed: $dst"
    fi
  }

  echo "=== zero-g-harness doctor ==="
  check_link "$AGY_CFG/GEMINI.md" required
  check_link "$AGY_CFG/templates/AGENTS.md.template" required
  check_link "$AGY_CFG/agents/code-auditor.md" required
  check_link "$AGY_CFG/agents/test-runner.md" required
  check_link "$AGY_CFG/agents/codebase-explorer.md" optional
  check_link "$AGY_CFG/agents/code-implementer.md" optional
  for f in "$REPO_DIR"/bin/ai-*; do
    check_link "$BIN_DIR/$(basename "$f")" required
  done

  # MCP config check
  local mcp="$AGY_CFG/mcp_config.json"
  if [ ! -f "$mcp" ]; then
    fail "Missing $mcp"
  elif command -v python3 >/dev/null && python3 -m json.tool "$mcp" >/dev/null 2>&1; then
    pass "Valid JSON: $mcp"
  elif command -v node >/dev/null && node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$mcp" 2>/dev/null; then
    pass "Valid JSON: $mcp"
  else
    fail "Invalid JSON (or no python3/node to validate): $mcp"
  fi

  # RTK verification (rtk gain distinguishes Rust Token Killer from Rust Type Kit)
  if command -v rtk >/dev/null; then
    if rtk gain >/dev/null 2>&1; then
      pass "RTK active: $(rtk --version 2>/dev/null || echo 'ok')"
    else
      fail "rtk found on PATH but 'rtk gain' failed (wrong binary? expected rtk-ai/rtk)"
    fi
  else
    fail "rtk not found on PATH"
  fi

  if [ -f "$AGY_CFG/plugins/rtk/hooks.json" ]; then
    pass "RTK Antigravity plugin hook present: $AGY_CFG/plugins/rtk/hooks.json"
  else
    warn "Missing $AGY_CFG/plugins/rtk/hooks.json (run: rtk init -g --agent antigravity)"
  fi

  # Local MCP binaries (only required if referenced in mcp_config.json)
  for tool in context-mode repomix; do
    if command -v "$tool" >/dev/null; then
      pass "$tool on PATH"
    elif [ -f "$mcp" ] && grep -q "\"$tool\"" "$mcp"; then
      fail "$tool referenced in $mcp but not found on PATH"
    else
      echo "[INFO] $tool not installed (not required in minimal profile)"
    fi
  done

  # Antigravity CLI & live model ID validation
  if command -v agy >/dev/null; then
    pass "agy CLI on PATH ($(agy --version 2>/dev/null || echo 'ok'))"
    local models_out
    if models_out="$(agy models 2>/dev/null)" && [ -n "$models_out" ]; then
      local m
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        if printf '%s\n' "$models_out" | grep -qF "$m"; then
          pass "Model ID active in agy: $m"
        else
          fail "Model ID NOT found in 'agy models': $m"
        fi
      done < <(
        {
          sed -n 's/^model:[[:space:]]*//p' "$REPO_DIR"/config/agents/*.md
          sed -n 's/.*--model[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR"/bin/ai-review
        } | sort -u
      )
    else
      warn "Could not fetch 'agy models' (offline or not authenticated); skipped model ID check"
    fi
  else
    fail "agy CLI not found on PATH"
  fi

  echo "=== Summary: $fails failed, $warns warnings ==="
  [ "$fails" -eq 0 ]
}

if [ "$DOCTOR" = true ]; then
  run_doctor
  exit $?
fi

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

if [ "$MINIMAL" = true ]; then
  for agent in code-auditor.md test-runner.md; do
    link_item "$REPO_DIR/config/agents/$agent" "$AGY_CFG/agents/$agent"
  done
else
  for f in "$REPO_DIR"/config/agents/*.md; do
    link_item "$f" "$AGY_CFG/agents/$(basename "$f")"
  done
fi

chmod +x "$REPO_DIR"/bin/ai-*
for f in "$REPO_DIR"/bin/ai-*; do
  link_item "$f" "$BIN_DIR/$(basename "$f")"
done

if [ "$WITH_OPTIONAL" = true ]; then
  link_item "$REPO_DIR/config/optional/rules/cpp-embedded-gem5.md" "$AGY_CFG/rules/cpp-embedded-gem5.md"
  link_item "$REPO_DIR/config/optional/skills/academic-tutor" "$AGY_CFG/skills/academic-tutor"
fi

# mcp_config.json is copied (not symlinked) because MCP installers may rewrite it atomically
if [ "$MINIMAL" = true ]; then
  TMP_MCP="$(mktemp)"
  trap 'rm -f "$TMP_MCP"' EXIT
  cat > "$TMP_MCP" <<'EOF'
{
  "mcpServers": {
    "context7": {
      "serverUrl": "https://mcp.context7.com/mcp"
    },
    "gemini-api-docs": {
      "serverUrl": "https://gemini-api-docs-mcp.dev"
    }
  }
}
EOF
  copy_mcp_file "$TMP_MCP"
else
  copy_mcp_file "$REPO_DIR/config/mcp_config.json"
fi

if [ "$LINKS_ONLY" = true ]; then
  echo "[OK] Links applied. Reload VS Code window or run /skills reload in agy."
  exit 0
fi

echo "=== Installing upstream tools & skills (from official sources) ==="
if ! command -v rtk >/dev/null; then
  echo "[INFO] Installing RTK (Rust Token Killer) from upstream..."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi
command -v rtk >/dev/null && rtk init -g --agent antigravity || true

if [ "$MINIMAL" = true ]; then
  if command -v npx >/dev/null; then
    echo "[INFO] Installing Ponytail skill (minimal profile)..."
    npx --yes skills add https://github.com/dietrichgebert/ponytail --skill ponytail || true
  else
    echo "[WARN] npx not found. Install Node.js to add Ponytail skill."
  fi
  echo "[OK] Minimal setup complete. Run ./install.sh --doctor to verify."
  exit 0
fi

if ! command -v npm >/dev/null; then
  echo "[WARN] npm not found. Install Node.js first, then re-run ./install.sh."
else
  command -v context-mode >/dev/null || npm i -g context-mode
  command -v repomix >/dev/null || npm i -g repomix
  context-mode setup || true
fi

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

echo "[OK] Setup complete. Run ./install.sh --doctor to verify, then reload VS Code or run /skills reload in agy."
