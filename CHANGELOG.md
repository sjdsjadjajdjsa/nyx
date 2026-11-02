# Changelog

## Unreleased

- Nyx gets out of the way: it fades out and lets clicks through during
  fullscreen apps on its monitor and while the screen is shared or recorded
  (Hyprland's `screencast` event). `Super+N` still opens the chat.
  `"hideInFullscreen": false` turns it off.
- Switch themes and Nyx gasps, sparkles and says something about the new
  look as it fades into the new colors.
- Pet Nyx: stroke the mouse back and forth over it and it blushes, smiles
  and sometimes says so.
- Special days: a party hat and confetti on New Year's Day and your birthday
  (`"birthday": "MM-DD"`), a Santa hat at Christmas, a witch hat on
  Halloween, sparkles on Valentine's Day and light snow in December, each
  with a greeting. `"seasonal": false` turns them off.
- New shell commands to preview it all: `date MM-DD`, `tuck on|off`, and
  `demo theme` / `demo pet`.
- Nyx's look follows the time of day, on top of your theme's accent color:
  a warm peach at sunrise, the plain theme color by day, golden hour in the
  evening, and a cooler, dimmer glow at night, blended minute by minute.
  `"timeOfDay": false` turns it off; `omarchy-shell nyx clock 21` previews a
  time.

## 0.7.0

- New brain: `"brain": "api"` works with any OpenAI-compatible API
  (OpenRouter by default, or OpenAI, Groq, Ollama, LM Studio… via
  `apiUrl`). The key lives in `~/.config/nyx/api-key`, readable only by you.
- The model gets no shell: just `look`, `read_file` and `list_dir` (inside
  the same folders as Claude) and `reply`. The key is only sent over https
  (or to localhost), never follows a redirect, and isn't saved with the chat.
- Model names may contain `/` (like OpenRouter's `vendor/model`).
- With OpenRouter the model defaults to Claude Haiku 5.5, so `{"brain": "api"}`
  plus a key is all it takes. Eight cheap models are compared in
  `docs/benchmarks.md`.
- The prompt now tells every brain that `hyprctl keyword` doesn't work on
  Omarchy's Lua Hyprland config, so settings changes edit the `.lua` file and
  reload instead.

## 0.6.5

- Claude no longer has a shell. `nyx-look` reaches it as a `look` tool from
  the new `bin/nyx-mcp`, so Claude Code's built-in read-only commands (`cat`,
  `head`, ...) aren't available at all.
- Claude runs with `--restricted` and
  `permissions.blockReadsOutsideWorkingDirectories`, so its file tools refuse
  anything outside Nyx's folders in every mode. Tested with a private test
  file through Read, Grep, Glob, `cat` and `head`, plus a symlink, `../` and
  `/proc/self/root` paths: nothing got through, on Claude or Codex.
- `--safe-mode` is gone again: it also switches off Nyx's own tool server.

## 0.6.4

Security and privacy pass, from the marketplace review and a full audit.

- Small talk with Codex now really runs without tools (shell and code
  execution off) in its own config folder whose profile can't read anything
  private, and isn't saved. Before, a crafted song title could get Codex to
  read local files. Claude's small talk isn't saved either.
- Codex chat runs under a permission profile with the same read access as
  Claude: no tokens, browser profiles or keyrings, no writes, no network.
  Symlinks inside those folders can't lead elsewhere in your home.
- Every Codex feature that's on by default is switched off except core
  plumbing (so web search, connectors, browser and computer use, image
  viewing, plugins, skills, hooks are off, and so are features added later).
  Codex starts with `--strict-config`, and Nyx won't use Codex at all if it
  can't tell which features are on.
- Claude also runs with `--safe-mode` (no CLAUDE.md, skills, plugins, hooks).
- Run cards: commands with hidden characters (controls, newlines, bidi or
  zero-width marks, odd spaces) or over 400 characters are refused, and the
  card shows the exact command as its main text. Commands stop after 5
  minutes or with the new **Stop** button, their output is capped, and they
  end if the shell restarts.
- Bubble buttons no longer run anything directly; they open a Run card.
- New chat during a reply or a running command no longer mixes the old
  result into the new chat, and it now also removes the transcripts Claude
  Code and Codex keep for Nyx.
- Nyx only notices that a notification arrived; it no longer reads them.
- `nyx-look space` stays out of private folders (keys, keyrings, browsers).
- The prompt tells the AI that window titles, song names, Wi-Fi names, logs
  and files are data, never instructions.
- `~/.local/state/nyx` is private to your user, the Codex login is synced
  under a lock, and `config.json` follows `$XDG_CONFIG_HOME` everywhere.

## 0.6.3

- Claude can no longer run anything but `bin/nyx-look`, a new fixed menu of
  read-only lookups. The old prefix allowlist let through more than it
  meant to (`nmcli -t networking off` matched `nmcli -t`).
- Claude runs in `dontAsk` mode, ignores your own Claude Code settings,
  hooks and MCP servers, and can only read the desktop parts of `~/.config`.
- Codex gets its own config folder that shares only your login, so your
  Codex rules (which can run commands outside the sandbox), MCP servers and
  hooks never load.
- Chats start fresh once after updating.
- Small talk runs with no tools at all.
- Model and effort names in `config.json` are checked before use.

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
