-- ╔══════════════════════════════════════════════════════════╗
-- ║  AGENTIC TERMINAL — Wezterm Config                      ║
-- ║  Agent-aware terminal with file memory & pane grouping   ║
-- ╚══════════════════════════════════════════════════════════╝

local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local config = wezterm.config_builder()

-- ┌─────────────────────────────────────────┐
-- │  1. PERFORMANCE — Low Memory Settings   │
-- └─────────────────────────────────────────┘
config.scrollback_lines = 5000 -- default 3500, keep low
config.enable_scroll_bar = false
config.animation_fps = 1
config.max_fps = 30
config.front_end = "WebGpu" -- GPU-accelerated, less CPU
config.webgpu_power_preference = "LowPower"
config.enable_tab_bar = true
config.use_fancy_tab_bar = false -- simpler = less memory
config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }

-- ┌─────────────────────────────────────────┐
-- │  2. APPEARANCE                          │
-- └─────────────────────────────────────────┘
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 13.0
config.window_decorations = "RESIZE"
config.inactive_pane_hsb = {
  saturation = 0.7,
  brightness = 0.6,
}

-- ┌─────────────────────────────────────────┐
-- │  3. IMAGE / VISUAL FILE PREVIEW         │
-- └─────────────────────────────────────────┘
-- Wezterm supports iTerm2 image protocol & Sixel natively.
-- We add a keybinding that opens a preview pane for any file.
-- Preview is read-only — never saves, just displays.

local PREVIEW_SCRIPT = os.getenv("HOME") .. "/.config/agentic-terminal/scripts/preview.sh"
local AGENT_BRIDGE   = os.getenv("HOME") .. "/.config/agentic-terminal/scripts/agent-bridge.sh"
local FILE_CACHE     = os.getenv("HOME") .. "/.config/agentic-terminal/scripts/file-cache.sh"

-- ┌─────────────────────────────────────────┐
-- │  4. AGENT WORKSPACE DEFINITIONS         │
-- └─────────────────────────────────────────┘
-- Named workspaces for different agent contexts.
-- Each workspace = isolated group of panes.

local AGENT_WORKSPACES = {
  {
    name = "main",
    label = "🏠 Main",
    layout = {
      { title = "shell", cmd = { os.getenv("SHELL") or "/bin/zsh" } },
    },
  },
  {
    name = "agent-claude",
    label = "🤖 Claude Agent",
    layout = {
      { title = "agent",   cmd = { "claude" } },           -- Claude Code
      { title = "scratch", cmd = { os.getenv("SHELL") } }, -- side shell
    },
  },
  {
    name = "agent-codex",
    label = "🔧 Codex Agent",
    layout = {
      { title = "agent",   cmd = { "codex" } },
      { title = "scratch", cmd = { os.getenv("SHELL") } },
    },
  },
  {
    name = "security-ops",
    label = "🛡️ SecOps",
    layout = {
      { title = "scanner", cmd = { os.getenv("SHELL") } },
      { title = "logs",    cmd = { "tail", "-f", "/var/log/system.log" } },
      { title = "shell",   cmd = { os.getenv("SHELL") } },
    },
  },
}

-- ┌─────────────────────────────────────────┐
-- │  5. WORKSPACE LAUNCHER                  │
-- └─────────────────────────────────────────┘
-- CTRL+SHIFT+W opens a fuzzy workspace picker.

local function workspace_choices()
  local choices = {}
  for _, ws in ipairs(AGENT_WORKSPACES) do
    table.insert(choices, { id = ws.name, label = ws.label })
  end
  return choices
end

local function find_workspace(name)
  for _, ws in ipairs(AGENT_WORKSPACES) do
    if ws.name == name then return ws end
  end
  return nil
end

wezterm.on("spawn-workspace", function(window, pane, name)
  local ws = find_workspace(name)
  if not ws then return end

  -- First pane
  local tab, first_pane, _ = mux.spawn_window({
    workspace = ws.name,
    args = ws.layout[1].cmd,
  })
  first_pane:set_user_var("pane_title", ws.layout[1].title)

  -- Additional panes — split right
  for i = 2, #ws.layout do
    local p = first_pane:split({
      direction = "Right",
      args = ws.layout[i].cmd,
    })
    p:set_user_var("pane_title", ws.layout[i].title)
  end

  -- Switch to the new workspace
  mux.set_active_workspace(ws.name)
end)

-- ┌─────────────────────────────────────────┐
-- │  6. EVENT HOOKS                         │
-- └─────────────────────────────────────────┘

-- Track last opened files per pane (lightweight memory)
wezterm.on("user-var-changed", function(window, pane, var_name, value)
  if var_name == "LAST_FILE" and value ~= "" then
    -- Store in pane's user vars for quick access
    pane:set_user_var("last_file_path", value)
    -- Also write to disk cache via the cache script
    local handle = io.popen(FILE_CACHE .. " set '" .. value .. "'")
    if handle then handle:close() end
  end
end)

-- Tab title shows workspace + pane role
wezterm.on("format-tab-title", function(tab)
  local pane = tab.active_pane
  local title = pane.user_vars.pane_title or pane.title
  local ws = mux.get_active_workspace()
  if ws ~= "default" then
    return " " .. ws .. " │ " .. title .. " "
  end
  return " " .. title .. " "
end)

-- Status bar — show active workspace + file cache count
wezterm.on("update-status", function(window, pane)
  local ws = window:active_workspace()
  local info = "  🗂 " .. ws
  local last_file = pane:get_user_vars().last_file_path
  if last_file then
    -- Show only filename, not full path
    local fname = last_file:match("([^/]+)$") or last_file
    info = info .. "  │  📄 " .. fname
  end
  window:set_left_status(wezterm.format({
    { Foreground = { Color = "#89b4fa" } },
    { Text = info },
  }))
end)

-- ┌─────────────────────────────────────────┐
-- │  7. KEYBINDINGS                         │
-- └─────────────────────────────────────────┘
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1500 }

config.keys = {
  -- ── Workspace Management ──
  {
    key = "w",
    mods = "LEADER",
    action = act.InputSelector({
      title = "🚀 Switch Agent Workspace",
      choices = workspace_choices(),
      action = wezterm.action_callback(function(window, pane, id, label)
        if id then
          -- Check if workspace already exists
          local existing = false
          for _, ws_name in ipairs(mux.get_workspace_names()) do
            if ws_name == id then
              existing = true
              break
            end
          end
          if existing then
            mux.set_active_workspace(id)
          else
            wezterm.emit("spawn-workspace", window, pane, id)
          end
        end
      end),
    }),
  },

  -- ── Pane Splitting ──
  { key = "|", mods = "LEADER|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "-", mods = "LEADER",       action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

  -- ── Pane Navigation (vim-style) ──
  { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
  { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
  { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
  { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

  -- ── Pane Resize ──
  { key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 3 }) },
  { key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 3 }) },

  -- ── File Preview (read-only, no save) ──
  { key = "p", mods = "LEADER", action = act.SplitPane({
      direction = "Right",
      size = { Percent = 40 },
      command = { args = { PREVIEW_SCRIPT } },
    }),
  },

  -- ── Quick Agent Send — type command in active agent pane ──
  {
    key = "s",
    mods = "LEADER",
    action = act.PromptInputLine({
      description = "📡 Send command to agent:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          pane:send_text(line .. "\n")
        end
      end),
    }),
  },

  -- ── File Cache: recall last file ──
  {
    key = "f",
    mods = "LEADER",
    action = act.SpawnCommandInNewTab({
      args = { FILE_CACHE, "list" },
    }),
  },

  -- ── Zoom pane toggle ──
  { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

  -- ── Close pane ──
  { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },

  -- ── Quick workspace switch (1-4) ──
  { key = "1", mods = "LEADER", action = act.SwitchToWorkspace({ name = "main" }) },
  { key = "2", mods = "LEADER", action = act.SwitchToWorkspace({ name = "agent-claude" }) },
  { key = "3", mods = "LEADER", action = act.SwitchToWorkspace({ name = "agent-codex" }) },
  { key = "4", mods = "LEADER", action = act.SwitchToWorkspace({ name = "security-ops" }) },
}

-- ┌─────────────────────────────────────────┐
-- │  8. UNIX DOMAIN (multiplexer daemon)    │
-- └─────────────────────────────────────────┘
-- Enables session persistence + remote pane control.
-- Agent bridge script uses this to send commands.
config.unix_domains = {
  { name = "agent-mux" },
}

-- Auto-connect to the mux domain on startup
-- config.default_gui_startup_args = { "connect", "agent-mux" }

return config
