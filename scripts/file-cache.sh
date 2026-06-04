#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║  file-cache.sh — Lightweight file memory store       ║
# ║  Tracks last N files with content hash + snippet     ║
# ║  Max ~2MB total cache, auto-evicts oldest entries    ║
# ╚══════════════════════════════════════════════════════╝

set -euo pipefail

CACHE_DIR="${HOME}/.cache/agentic-terminal"
CACHE_INDEX="${CACHE_DIR}/index.json"
CACHE_CONTENT_DIR="${CACHE_DIR}/content"
MAX_ENTRIES=50          # max files tracked
MAX_SNIPPET_BYTES=4096  # max content snapshot per file (4KB)
MAX_CACHE_MB=2          # total cache size limit

mkdir -p "$CACHE_DIR" "$CACHE_CONTENT_DIR"

# Init index if missing
if [[ ! -f "$CACHE_INDEX" ]]; then
  echo '{"files":[]}' > "$CACHE_INDEX"
fi

# ── Helpers ──
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

file_hash() {
  if command -v shasum &>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  else
    md5 -q "$1" 2>/dev/null || echo "nohash"
  fi
}

cache_size_mb() {
  du -sm "$CACHE_DIR" 2>/dev/null | cut -f1
}

# ── Commands ──

cmd_set() {
  local filepath="$1"
  local abs_path

  # Resolve absolute path
  if [[ "$filepath" == /* ]]; then
    abs_path="$filepath"
  else
    abs_path="$(cd "$(dirname "$filepath")" && pwd)/$(basename "$filepath")"
  fi

  if [[ ! -f "$abs_path" ]]; then
    echo "⚠ File not found: $abs_path"
    return 1
  fi

  local hash ext size fname snippet_file
  hash=$(file_hash "$abs_path")
  ext="${abs_path##*.}"
  size=$(wc -c < "$abs_path" | tr -d ' ')
  fname=$(basename "$abs_path")
  snippet_file="${CACHE_CONTENT_DIR}/${hash}.snippet"

  # Save content snippet (first N bytes for text files)
  local filetype
  filetype=$(file -b --mime-type "$abs_path" 2>/dev/null || echo "unknown")
  if [[ "$filetype" == text/* ]] || [[ "$filetype" == application/json ]] || [[ "$filetype" == application/xml ]]; then
    head -c "$MAX_SNIPPET_BYTES" "$abs_path" > "$snippet_file"
  else
    # Binary: just store metadata, no content
    echo "[binary: $filetype, $size bytes]" > "$snippet_file"
  fi

  # Update index using Python (lighter than jq dependency)
  python3 -c "
import json, sys

index_path = '$CACHE_INDEX'
with open(index_path, 'r') as f:
    data = json.load(f)

entry = {
    'path': '$abs_path',
    'name': '$fname',
    'ext': '$ext',
    'hash': '$hash',
    'size': int('$size'),
    'type': '$filetype',
    'seen_at': '$(timestamp)',
    'snippet_file': '$snippet_file'
}

# Remove existing entry for same path
data['files'] = [f for f in data['files'] if f['path'] != '$abs_path']

# Prepend new entry
data['files'].insert(0, entry)

# Evict oldest if over limit
if len(data['files']) > $MAX_ENTRIES:
    evicted = data['files'][$MAX_ENTRIES:]
    data['files'] = data['files'][:$MAX_ENTRIES]
    # Clean up evicted snippet files
    import os
    for e in evicted:
        sf = e.get('snippet_file', '')
        if sf and os.path.exists(sf):
            os.remove(sf)

with open(index_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f'✅ Cached: {entry[\"name\"]} ({entry[\"size\"]} bytes)')
"
}

cmd_get() {
  local query="$1"
  python3 -c "
import json
with open('$CACHE_INDEX', 'r') as f:
    data = json.load(f)
for entry in data['files']:
    if '$query' in entry['path'] or '$query' in entry['name']:
        print(f\"📄 {entry['name']}\")
        print(f\"   Path: {entry['path']}\")
        print(f\"   Type: {entry['type']} | Size: {entry['size']}B\")
        print(f\"   Hash: {entry['hash'][:16]}...\")
        print(f\"   Last seen: {entry['seen_at']}\")
        # Show snippet
        sf = entry.get('snippet_file', '')
        if sf:
            try:
                with open(sf, 'r') as s:
                    content = s.read()
                    if content:
                        print(f\"   ── Content Preview ──\")
                        for line in content.split('\\n')[:10]:
                            print(f\"   │ {line}\")
                        print(f\"   └──────────────────\")
            except: pass
        print()
        break
else:
    print(f'⚠ Not found in cache: $query')
"
}

cmd_list() {
  echo "┌─────────────────────────────────────────────┐"
  echo "│  📦 File Memory Cache                       │"
  echo "│  Max: ${MAX_ENTRIES} files, ${MAX_CACHE_MB}MB  │"
  echo "│  Current: $(cache_size_mb 2>/dev/null || echo '?')MB                              │"
  echo "└─────────────────────────────────────────────┘"
  echo ""
  python3 -c "
import json
with open('$CACHE_INDEX', 'r') as f:
    data = json.load(f)
if not data['files']:
    print('  (empty)')
else:
    for i, entry in enumerate(data['files'][:20], 1):
        icon = '📄'
        if entry.get('type','').startswith('image'): icon = '🖼'
        elif entry.get('ext') == 'pdf': icon = '📕'
        elif entry.get('ext') in ('py','js','ts','rs','go','lua','sh'): icon = '💻'
        size_kb = entry['size'] / 1024
        print(f'  {i:>2}. {icon} {entry[\"name\"]:30s}  {size_kb:>8.1f}KB  {entry[\"seen_at\"]}')
    remaining = len(data['files']) - 20
    if remaining > 0:
        print(f'  ... and {remaining} more')
"
}

cmd_recall() {
  # Recall last N files' content snippets (for feeding to agent)
  local count="${1:-5}"
  python3 -c "
import json
with open('$CACHE_INDEX', 'r') as f:
    data = json.load(f)
for entry in data['files'][:$count]:
    print(f'--- {entry[\"path\"]} ({entry[\"type\"]}) ---')
    sf = entry.get('snippet_file', '')
    if sf:
        try:
            with open(sf, 'r') as s:
                print(s.read())
        except:
            print('[content unavailable]')
    print()
"
}

cmd_clear() {
  rm -rf "$CACHE_CONTENT_DIR"/*
  echo '{"files":[]}' > "$CACHE_INDEX"
  echo "🗑 Cache cleared"
}

# ── Router ──
case "${1:-help}" in
  set)    cmd_set "${2:?filepath required}" ;;
  get)    cmd_get "${2:?query required}" ;;
  list)   cmd_list ;;
  recall) cmd_recall "${2:-5}" ;;
  clear)  cmd_clear ;;
  help|*)
    echo "Usage: file-cache.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  set <filepath>    Cache a file's metadata + content snippet"
    echo "  get <query>       Find a cached file by name/path"
    echo "  list              Show all cached files"
    echo "  recall [N]        Output last N files' content (for agent context)"
    echo "  clear             Wipe the cache"
    ;;
esac
