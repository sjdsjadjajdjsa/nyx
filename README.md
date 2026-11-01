# Nyx

A little AI buddy that lives in the corner of your Omarchy desktop.

- Glowing orb with moods: blinks, bobs, follows your mouse, dozes off when you're away.
- Click it or press **Super+N** to chat.
- Powered by Claude Code (`claude -p`). Nyx can *look* at your system on its own
  (read-only commands); anything that *changes* something shows a **Run / Cancel** card.
- Matches your Omarchy theme automatically.

## Files

| File | What it is |
|---|---|
| `manifest.json` | Plugin info for the Omarchy shell |
| `Nyx.qml` | Window, chat bubble, action cards, eye tracking |
| `Orb.qml` | Nyx's body and facial expressions |
| `bin/nyx-ask` | The brain: talks to Claude Code, returns JSON |
| `prompt.md` | Nyx's personality and rules |

## Install

```bash
ln -s ~/Work/nyx ~/.config/omarchy/plugins/cj.nyx
omarchy-shell shell rescanPlugins
omarchy plugin enable cj.nyx
```

Shortcut (in `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + N", "Nyx", "omarchy-shell nyx toggle")
```

## Settings

`~/.config/nyx/config.json` (optional):

```json
{ "model": "sonnet" }
```

Default model is `haiku` (fast). Use `sonnet` for a smarter, slower Nyx.

## IPC

```bash
omarchy-shell nyx toggle | open | close | reset
omarchy-shell nyx ask "how's my battery?"
```

After editing the QML, run `omarchy restart shell` if changes don't show up.
