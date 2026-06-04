#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  preview.sh — Read-only file previewer   ║
# ║  Uses iTerm2/Sixel image protocol        ║
# ║  Never saves, only displays              ║
# ╚══════════════════════════════════════════╝

set -euo pipefail

CACHE_SCRIPT="$(dirname "$0")/file-cache.sh"
SUPPORTED_IMG="png|jpg|jpeg|gif|webp|bmp|svg|ico"
SUPPORTED_DOC="pdf|md|txt|json|yaml|yml|toml|xml|csv"
SUPPORTED_CODE="py|js|ts|jsx|tsx|rs|go|lua|sh|zsh|bash|rb|swift|kt|java|c|cpp|h"

# ── iTerm2 image display (works in Wezterm too) ──
show_image() {
  local file="$1"
  local width="${2:-auto}"
  local height="${3:-auto}"

  if command -v wezterm &>/dev/null; then
    wezterm imgcat --width "$width" "$file" 2>/dev/null && return
  fi

  if command -v imgcat &>/dev/null; then
    imgcat "$file" 2>/dev/null && return
  fi

  # Fallback: base64 iTerm2 protocol
  local b64
  b64=$(base64 < "$file")
  printf '\033]1337;File=inline=1;width=%s;height=%s;preserveAspectRatio=1:%s\a' \
    "$width" "$height" "$b64"
}

# ── Syntax highlighted text preview ──
show_text() {
  local file="$1"
  if command -v bat &>/dev/null; then
    bat --style=plain,numbers --color=always --paging=never "$file"
  elif command -v highlight &>/dev/null; then
    highlight -O ansi "$file"
  else
    cat -n "$file"
  fi
}

# ── PDF preview (first page as image) ──
show_pdf() {
  local file="$1"
  local tmp="/tmp/.agentic-preview-$$.png"
  if command -v sips &>/dev/null; then
    # macOS native
    qlmanage -t -s 800 -o /tmp/ "$file" 2>/dev/null
    local ql_out="/tmp/$(basename "$file").png"
    if [[ -f "$ql_out" ]]; then
      show_image "$ql_out"
      rm -f "$ql_out"
      return
    fi
  fi
  if command -v convert &>/dev/null; then
    convert "${file}[0]" -resize 800x "$tmp" 2>/dev/null
    show_image "$tmp"
    rm -f "$tmp"
    return
  fi
  echo "⚠ PDF preview requires ImageMagick or macOS Quick Look"
  echo "  brew install imagemagick"
}

# ── Main interactive loop ──
preview_file() {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}" # lowercase

  echo "┌──────────────────────────────────────┐"
  echo "│  📄 $(basename "$file")"
  echo "│  📁 $(dirname "$file")"
  echo "│  📏 $(wc -c < "$file" 2>/dev/null | tr -d ' ') bytes"
  echo "│  🔒 READ-ONLY PREVIEW"
  echo "└──────────────────────────────────────┘"
  echo ""

  if [[ "$ext" =~ ^($SUPPORTED_IMG)$ ]]; then
    show_image "$file"
  elif [[ "$ext" == "pdf" ]]; then
    show_pdf "$file"
  elif [[ "$ext" =~ ^($SUPPORTED_CODE)$ ]] || [[ "$ext" =~ ^($SUPPORTED_DOC)$ ]]; then
    show_text "$file"
  else
    echo "⚠ Unknown file type: .$ext"
    echo "  Attempting text preview..."
    file "$file"
    echo ""
    head -100 "$file" 2>/dev/null || xxd "$file" | head -50
  fi

  # Cache the file content hash (not content itself — low memory)
  "$CACHE_SCRIPT" set "$file" 2>/dev/null || true
}

# ── Entry point ──
if [[ $# -ge 1 ]]; then
  preview_file "$1"
else
  # Interactive mode: fzf file picker
  echo "🔍 Select a file to preview (read-only)..."
  echo ""
  if command -v fzf &>/dev/null; then
    local selected
    selected=$(find . -maxdepth 4 -type f \
      ! -path '*/node_modules/*' \
      ! -path '*/.git/*' \
      ! -path '*/venv/*' \
      | fzf --preview 'bat --style=plain --color=always {} 2>/dev/null || head -50 {}' \
             --preview-window=right:60%:wrap)
    if [[ -n "$selected" ]]; then
      preview_file "$selected"
    fi
  else
    echo "💡 Usage: preview.sh <filepath>"
    echo "   Install fzf for interactive mode: brew install fzf"
  fi
fi
