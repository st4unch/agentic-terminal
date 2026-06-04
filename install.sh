#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║  install.sh — Agentic Terminal Setup for macOS       ║
# ╚══════════════════════════════════════════════════════╝

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.config/agentic-terminal"
WEZTERM_CONFIG="${HOME}/.wezterm.lua"

echo "╔══════════════════════════════════════════╗"
echo "║  🚀 Agentic Terminal Installer           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Check / Install Wezterm ──
if ! command -v wezterm &>/dev/null; then
  echo "📦 Installing Wezterm..."
  if command -v brew &>/dev/null; then
    brew install --cask wezterm
  else
    echo "⚠ Homebrew not found. Install Wezterm manually:"
    echo "  https://wezfurlong.org/wezterm/install/macos.html"
    exit 1
  fi
else
  echo "✅ Wezterm found: $(wezterm --version 2>/dev/null || echo 'installed')"
fi

# ── 2. Install optional tools ──
echo ""
echo "📦 Checking optional dependencies..."

install_if_missing() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    echo "  Installing $pkg..."
    brew install "$pkg" 2>/dev/null || echo "  ⚠ Could not install $pkg, skipping"
  else
    echo "  ✅ $cmd"
  fi
}

install_if_missing "bat" "bat"       # syntax highlighting
install_if_missing "fzf" "fzf"       # fuzzy finder
install_if_missing "jq"  "jq"        # JSON processing

# ── 3. Deploy config files ──
echo ""
echo "📁 Setting up config..."

mkdir -p "$CONFIG_DIR/scripts"

# Copy scripts
cp "$SCRIPT_DIR/scripts/preview.sh"       "$CONFIG_DIR/scripts/"
cp "$SCRIPT_DIR/scripts/file-cache.sh"    "$CONFIG_DIR/scripts/"
cp "$SCRIPT_DIR/scripts/agent-bridge.sh"  "$CONFIG_DIR/scripts/"

chmod +x "$CONFIG_DIR/scripts/"*.sh

# Wezterm config
if [[ -f "$WEZTERM_CONFIG" ]]; then
  echo "  ⚠ Existing wezterm config found at $WEZTERM_CONFIG"
  echo "  Backing up to ${WEZTERM_CONFIG}.bak"
  cp "$WEZTERM_CONFIG" "${WEZTERM_CONFIG}.bak"
fi

cp "$SCRIPT_DIR/config/wezterm.lua" "$WEZTERM_CONFIG"
echo "  ✅ Wezterm config installed"

# ── 4. Shell integration (zsh) ──
echo ""
echo "🔧 Adding shell aliases..."

SHELL_RC="${HOME}/.zshrc"
MARKER="# --- Agentic Terminal ---"

if ! grep -q "$MARKER" "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'ALIASES'

# --- Agentic Terminal ---
export AGENTIC_TERMINAL_HOME="${HOME}/.config/agentic-terminal"

# File preview (read-only)
alias preview='${AGENTIC_TERMINAL_HOME}/scripts/preview.sh'

# File cache
alias fcache='${AGENTIC_TERMINAL_HOME}/scripts/file-cache.sh'

# Agent bridge
alias agent='${AGENTIC_TERMINAL_HOME}/scripts/agent-bridge.sh'

# Quick: cache current file after editing
# Usage: `cache myfile.py` after any edit
cache() {
  fcache set "$1"
  echo "📦 Cached: $1"
}

# Quick: preview + cache
peek() {
  preview "$1"
  cache "$1" 2>/dev/null
}

# Track files opened with common editors
for editor_cmd in vim nvim code nano; do
  eval "
    _agentic_${editor_cmd}() {
      command ${editor_cmd} \"\$@\"
      for f in \"\$@\"; do
        [[ -f \"\$f\" ]] && fcache set \"\$f\" 2>/dev/null &
      done
    }
    alias ${editor_cmd}='_agentic_${editor_cmd}'
  "
done
# --- End Agentic Terminal ---
ALIASES
  echo "  ✅ Aliases added to $SHELL_RC"
else
  echo "  ✅ Aliases already present"
fi

# ── 5. Summary ──
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ Installation complete!                       ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  Keybindings (Leader = Ctrl+A):                  ║"
echo "║    Leader → w     Workspace picker               ║"
echo "║    Leader → 1-4   Quick workspace switch         ║"
echo "║    Leader → |     Split right                    ║"
echo "║    Leader → -     Split down                     ║"
echo "║    Leader → p     File preview pane              ║"
echo "║    Leader → s     Send command to agent          ║"
echo "║    Leader → f     File cache browser             ║"
echo "║    Leader → z     Zoom pane                      ║"
echo "║    Leader → hjkl  Navigate panes                 ║"
echo "║                                                  ║"
echo "║  CLI commands:                                   ║"
echo "║    preview <file>      Visual preview             ║"
echo "║    cache <file>        Add to file memory         ║"
echo "║    peek <file>         Preview + cache            ║"
echo "║    fcache list         Show cached files          ║"
echo "║    fcache recall 5     Last 5 file contents       ║"
echo "║    agent ask claude    Send question to agent     ║"
echo "║    agent list          Show all panes             ║"
echo "║                                                  ║"
echo "║  Restart your shell:  source ~/.zshrc             ║"
echo "║  Launch terminal:     wezterm                     ║"
echo "╚══════════════════════════════════════════════════╝"
