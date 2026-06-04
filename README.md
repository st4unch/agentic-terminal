# Agentic Terminal

Wezterm tabanlı, agent-aware terminal ortamı. macOS için tasarlandı.

## Ne Yapıyor?

**Workspace'ler** — Her agent (Claude Code, Codex, vb.) kendi izole pane grubunda çalışır. `Ctrl+A → w` ile workspace picker açılır, `Ctrl+A → 1-4` ile hızlı geçiş yapılır.

**File Memory** — Açtığın dosyaların metadata + ilk 4KB content snippet'i otomatik cache'lenir. Agent'a context olarak gönderilebilir. Max 50 dosya, ~2MB disk.

**Read-Only Preview** — `Ctrl+A → p` ile dosya preview pane'i açılır. Image'lar iTerm2 protocol ile render edilir, kod dosyaları syntax highlighting ile gösterilir. Hiçbir şey kaydedilmez.

**Agent Bridge** — Dışarıdan herhangi bir pane'e komut gönderilebilir, output capture edilebilir, file context pipe'lanabilir.

## Kurulum

```bash
git clone <repo-url> agentic-terminal
cd agentic-terminal
chmod +x install.sh
./install.sh
```

## Mimari

```
┌─────────────────────────────────────────────────────────┐
│  Wezterm (GPU-accelerated, Lua scriptable)              │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Workspace:   │  │ Workspace:   │  │ Workspace:   │  │
│  │ main         │  │ agent-claude │  │ security-ops │  │
│  │              │  │              │  │              │  │
│  │  [shell]     │  │ [claude] [sh]│  │ [scan][logs] │  │
│  └──────────────┘  └──────────────┘  │ [shell]      │  │
│                                       └──────────────┘  │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Status Bar: workspace │ last cached file         │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         │                      │
         ▼                      ▼
  ┌─────────────┐    ┌──────────────────┐
  │ preview.sh  │    │ agent-bridge.sh  │
  │ (read-only) │    │ (orchestration)  │
  │ imgcat/bat  │    │ send/capture/    │
  └─────────────┘    │ feed/watch       │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │ file-cache.sh    │
                     │ index.json +     │
                     │ content snippets │
                     │ (max 2MB)        │
                     └──────────────────┘
```

## Keybinding Cheatsheet

| Kısayol | İşlev |
|---------|-------|
| `Ctrl+A → w` | Workspace picker |
| `Ctrl+A → 1-4` | Hızlı workspace geçişi |
| `Ctrl+A → \|` | Dikey split |
| `Ctrl+A → -` | Yatay split |
| `Ctrl+A → p` | File preview pane |
| `Ctrl+A → s` | Agent'a komut gönder |
| `Ctrl+A → f` | File cache listesi |
| `Ctrl+A → z` | Pane zoom toggle |
| `Ctrl+A → x` | Pane kapat |
| `Ctrl+A → hjkl` | Pane navigasyon |
| `Ctrl+A → HJKL` | Pane resize |

## CLI Komutları

```bash
# File preview (read-only)
preview myfile.py
preview screenshot.png

# File cache
cache myfile.py              # cache'e ekle
fcache list                  # tüm cache'lenmiş dosyalar
fcache get myfile             # dosya ara
fcache recall 5               # son 5 dosya içeriğini çıkar

# Agent bridge
agent list                    # tüm pane'leri göster
agent ask "claude" "bu kodu refactor et"
agent send 3 "ls -la"         # pane 3'e komut gönder
agent feed 3 5                # pane 3'e son 5 dosyayı context olarak gönder
agent capture 3 100           # pane 3'ün son 100 satırını yakala
agent spawn "claude" Right    # yeni agent pane'i aç
```

## Özelleştirme

`~/.wezterm.lua` içindeki `AGENT_WORKSPACES` tablosuna yeni workspace ekle:

```lua
{
  name = "my-agent",
  label = "🔬 My Agent",
  layout = {
    { title = "agent", cmd = { "my-agent-cli" } },
    { title = "shell", cmd = { "/bin/zsh" } },
  },
},
```

## Memory Kullanımı

- Wezterm base: ~30-50MB (Electron alternatiflerinin 1/5'i)
- Scrollback: 5000 satır (varsayılan, düşük tutuldu)
- File cache: max 2MB disk, max 50 dosya
- GPU rendering: CPU yükü minimum
