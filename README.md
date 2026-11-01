# Nyx

A little AI buddy that lives in the corner of your Omarchy desktop.

- Glowing orb with moods: blinks, bobs, follows your mouse, dozes off when you're away.
- Click it or press **Super+N** to chat.
- Powered by Claude Code (`claude -p`). Nyx can *look* at your system on its own
  (read-only commands); anything that *changes* something shows a **Run / Cancel** card.
- Matches your Omarchy theme automatically.
- **Reacts to your computer:** bops to music, worries at low battery, perks up at
  notifications, yawns late at night.
- **Speaks up on its own** with little speech bubbles (low battery → power saver,
  late night → night light, new song, plugged in, welcome back). Click a bubble to
  continue in chat.

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
Add `"speakUp": false` to stop the speech bubbles (reactions stay).

## IPC

```bash
omarchy-shell nyx toggle | open | close | reset
omarchy-shell nyx ask "how's my battery?"
omarchy-shell nyx say "hello!"          # make Nyx say something
omarchy-shell nyx demo music            # try a reaction: music | battery | plug | night | notify | sleep | yawn
```

After editing the QML, run `omarchy restart shell` if changes don't show up.
