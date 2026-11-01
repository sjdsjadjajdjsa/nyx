# Changelog

## 0.4.0

- Benchmarked eight models on real Nyx tasks ([docs/benchmarks.md](docs/benchmarks.md)).
- New defaults: Claude Sonnet and GPT-6.1-Terra, both at low effort.
- New `effort` setting.
- Codex falls back to its own default model if GPT-6.1-Terra isn't on your account.
- Nyx knows to read the battery from /sys when `upower` is blocked.

## 0.3.0

- Codex as a second brain: `"brain": "codex"` in `~/.config/nyx/config.json`.
  Runs in Codex's read-only sandbox, with the same Run / Cancel cards.
- The chat header shows which brain answered.
- Tested: the Run and Cancel buttons, end to end.

## 0.2.1

- Clicking outside the chat closes it, and the chat no longer holds the
  keyboard while it's open.
- Tested: installing with `omarchy plugin add`, and the new-song bubble
  with a real MPRIS player.

## 0.2.0

- Reactions: sways to music, worries at low battery, hops at notifications,
  yawns late at night, sleeps when you're away.
- Speech bubbles: low battery (power saver), late night (night light), new
  song, plugged in, welcome back. `"speakUp": false` turns them off.
- Nyx can check whether night light is on before offering it.
- New shell commands: `say`, `hush` and `demo`.

## 0.1.0

- Nyx: a glowing orb with eyes in the corner of the screen.
- Chat powered by Claude Code, with read-only tools to look at your system.
- Changes come back as Run / Cancel cards.
