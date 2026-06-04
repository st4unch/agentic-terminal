#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  agent-bridge.sh — External agent orchestration          ║
# ║  Send commands to named panes, capture output,           ║
# ║  pipe file context to agents                             ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

CACHE_SCRIPT="$(dirname "$0")/file-cache.sh"
WEZTERM_CLI="wezterm cli"

# ── Discover panes in current workspace ──
list_panes() {
  $WEZTERM_CLI list --format json 2>/dev/null | python3 -c "
import json, sys
panes = json.load(sys.stdin)
print(f'Found {len(panes)} pane(s):')
print()
for p in panes:
    ws = p.get('workspace', 'default')
    title = p.get('title', 'untitled')
    pane_id = p.get('pane_id', '?')
    cwd = p.get('cwd', '?')
    print(f'  [{pane_id}] {ws} / {title}')
    print(f'       cwd: {cwd}')
    print()
"
}

# ── Find pane by title substring ──
find_pane() {
  local search="$1"
  $WEZTERM_CLI list --format json 2>/dev/null | python3 -c "
import json, sys
panes = json.load(sys.stdin)
for p in panes:
    title = p.get('title', '')
    if '$search'.lower() in title.lower():
        print(p.get('pane_id', ''))
        sys.exit(0)
sys.exit(1)
"
}

# ── Send text to a specific pane ──
send_to_pane() {
  local pane_id="$1"
  local text="$2"
  $WEZTERM_CLI send-text --pane-id "$pane_id" -- "$text"
}

# ── Send command + Enter to a pane ──
exec_in_pane() {
  local pane_id="$1"
  local cmd="$2"
  send_to_pane "$pane_id" "${cmd}
"
}

# ── Send file context to agent pane ──
# Recalls cached file content and sends it as context
feed_context() {
  local pane_id="$1"
  local count="${2:-3}"

  echo "📡 Feeding last $count file(s) as context to pane $pane_id..."

  local context
  context=$("$CACHE_SCRIPT" recall "$count")

  # Send as a heredoc-style block
  send_to_pane "$pane_id" "# --- File Context (last $count files) ---"
  send_to_pane "$pane_id" "$context"
  send_to_pane "$pane_id" "# --- End Context ---
"
}

# ── Capture pane output (last N lines) ──
capture_output() {
  local pane_id="$1"
  local lines="${2:-50}"
  $WEZTERM_CLI get-text --pane-id "$pane_id" 2>/dev/null | tail -n "$lines"
}

# ── Spawn a new agent pane ──
spawn_agent() {
  local agent_cmd="$1"
  local direction="${2:-Right}"

  local new_pane_id
  new_pane_id=$($WEZTERM_CLI split-pane "--${direction,,}" -- "$agent_cmd")
  echo "$new_pane_id"
}

# ── High-level: ask agent a question with file context ──
ask_agent() {
  local pane_title="$1"
  local question="$2"
  local context_files="${3:-3}"

  local pane_id
  pane_id=$(find_pane "$pane_title") || {
    echo "⚠ Agent pane '$pane_title' not found"
    echo "  Available panes:"
    list_panes
    return 1
  }

  echo "🤖 Sending to agent in pane $pane_id..."

  # Feed file context first
  if [[ "$context_files" -gt 0 ]]; then
    feed_context "$pane_id" "$context_files"
    sleep 0.5
  fi

  # Send the question
  exec_in_pane "$pane_id" "$question"
  echo "✅ Sent. Watch pane $pane_id for response."
}

# ── Watch a pane and pipe output somewhere ──
watch_pane() {
  local pane_id="$1"
  local output_file="${2:-/tmp/agent-output-$$.log}"

  echo "👁 Watching pane $pane_id → $output_file"
  echo "   Press Ctrl+C to stop"

  local prev_hash=""
  while true; do
    local current
    current=$($WEZTERM_CLI get-text --pane-id "$pane_id" 2>/dev/null | tail -20)
    local curr_hash
    curr_hash=$(echo "$current" | md5 2>/dev/null || echo "$current" | md5sum 2>/dev/null | cut -d' ' -f1)

    if [[ "$curr_hash" != "$prev_hash" ]]; then
      echo "$current" >> "$output_file"
      prev_hash="$curr_hash"
    fi
    sleep 2
  done
}

# ── Router ──
case "${1:-help}" in
  list)     list_panes ;;
  find)     find_pane "${2:?search term required}" ;;
  send)     exec_in_pane "${2:?pane_id required}" "${3:?command required}" ;;
  feed)     feed_context "${2:?pane_id required}" "${3:-3}" ;;
  capture)  capture_output "${2:?pane_id required}" "${3:-50}" ;;
  spawn)    spawn_agent "${2:?agent command required}" "${3:-Right}" ;;
  ask)      ask_agent "${2:?pane title required}" "${3:?question required}" "${4:-3}" ;;
  watch)    watch_pane "${2:?pane_id required}" "${3:-}" ;;
  help|*)
    cat << 'EOF'
╔══════════════════════════════════════════╗
║  🤖 Agent Bridge — Command Reference    ║
╚══════════════════════════════════════════╝

  list                          Show all panes with workspace info
  find <title>                  Find pane ID by title substring
  send <pane_id> <command>      Execute command in a pane
  feed <pane_id> [count]        Send cached file context to pane
  capture <pane_id> [lines]     Capture last N lines from pane
  spawn <agent_cmd> [direction] Spawn new agent pane (Right/Bottom)
  ask <pane_title> <question>   Send question + context to named agent
  watch <pane_id> [logfile]     Tail pane output to a file

Examples:
  agent-bridge.sh ask "claude" "bu dosyayı analiz et"
  agent-bridge.sh spawn "claude" Right
  agent-bridge.sh send 3 "ls -la"
  agent-bridge.sh feed 3 5
  agent-bridge.sh capture 3 100
EOF
    ;;
esac
