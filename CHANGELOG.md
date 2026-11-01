# Changelog

## 0.6.2

- All text is drawn as plain text, so HTML in an AI reply, song title or
  action can't be rendered or make the shell load a remote image.

## 0.6.1

- Chat messages and small-talk context now go to `nyx-ask` and the AI CLI on
  stdin instead of the command line, so other users on the machine can't read
  them from `ps` or `/proc/<pid>/cmdline`.

## 0.6.0

- Chattier, never repetitive: several lines per moment (`Lines.js`), and Nyx
  avoids the ones it used recently.
- New moments: good morning, stretch after 90 minutes, late-night coding,
  Wi-Fi lost and back, headphones on and off, running hot, disk almost full.
- Bubbles can carry a question: "Find out" asks Nyx about it in chat.
- AI small talk in `chatty` mode: fresh one-liners in a throwaway session
  that never touches your chat.
- `chattiness`: `quiet`, `normal` or `chatty` (`"speakUp": false` still works
  and means `quiet`).
- About 5x lighter: one clock drives all motion at 25 fps while idle (60 when
  moving) instead of redrawing at the screen's full refresh rate; sparkles
  only run when Nyx sparkles. Idle CPU went from ~19 % to ~4 % of one core.

## 0.5.0

- Liquid body: Nyx wobbles like jelly when clicked, when it hops and on beats.
- Sparkles that follow Nyx's mood.
- Beat glow: Nyx's glow pumps with the music you're playing (`bin/nyx-beat`,
  local only; `"beatGlow": false` turns it off).
- A soft violet halo, and the glow no longer gets cut off in straight lines.
- Music wakes Nyx up; waking for music skips "You're back".
- Wider speech bubbles.
- Claude can read battery and temperature directly, so "how's my laptop?"
  gets a full answer.
- README: thanks to DHH and Omarchy.

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
