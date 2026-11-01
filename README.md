<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/banner-dark.svg">
  <img alt="nyx, a little AI buddy for your Omarchy desktop" src="docs/images/banner-light.svg" width="100%">
</picture>

<br><br>

[![omarchy](https://img.shields.io/badge/Omarchy%204-e8a2c8?style=flat-square&label=plugin%20for&labelColor=13111c)](https://omarchy.org)
[![brain](https://img.shields.io/badge/Claude%20Code-e8a2c8?style=flat-square&label=brain&labelColor=13111c)](https://claude.com/claude-code)
[![built with](https://img.shields.io/badge/QML%20·%20Quickshell-c6a0f6?style=flat-square&label=built%20with&labelColor=13111c)](https://quickshell.org)
[![license](https://img.shields.io/badge/MIT-c6a0f6?style=flat-square&label=license&labelColor=13111c)](LICENSE)

[Install](#install) &nbsp;·&nbsp; [What it does](#what-it-does) &nbsp;·&nbsp; [Use](#use) &nbsp;·&nbsp; [Settings](#settings) &nbsp;·&nbsp; [How it works](#how-it-works)

<br>

![Nyx chatting in the corner of an Omarchy desktop: it checked the night light, found it off, and offers a Run button to turn it on](docs/images/hero.webp)

</div>

<br>

Nyx is a small glowing orb that sits in the corner of your screen. It watches
your mouse, bops to your music, gets worried when the battery runs low and
falls asleep when you walk away. Click it and it talks back.

It knows your machine. Ask why the fan is loud, what's eating memory, or to
switch your theme, and it looks before it answers. It never changes anything
on its own: every change comes back as a **Run / Cancel** card.

## What it does

<div align="center">
  <img src="docs/images/reactions.webp" width="460" alt="Nyx hops at a notification, sways to music with notes floating up, looks worried at low battery with a power saver offer, yawns, then falls asleep">
</div>

- **Chat:** click the orb or press `Super+N`. Answers come from Claude Code,
  so it's actually smart.
- **Knows your machine:** reads battery, memory, processes, Hyprland windows,
  your config and the `omarchy` commands on its own, so answers are about
  *your* computer, not computers in general.
- **Asks first:** anything that changes something shows the exact command
  with **Run / Cancel**. Nothing runs until you click.
- **Reacts:** sways to music, worries under 20 % battery, hops at
  notifications, yawns after 11 pm, sleeps with little z's when you're away.
- **Speaks up:** small speech bubbles when it matters: low battery (one click
  to power saver), late night (one click to night light), a new song, being
  plugged in, you coming back. Click a bubble to keep talking.
- **Your theme:** uses your Omarchy colors, so switching themes restyles Nyx
  too.

## Install

Needs **Omarchy 4** and **[Claude Code](https://claude.com/claude-code)**
installed and logged in. Nyx uses your own Claude account and its normal
limits; there's no API key and nothing else to sign up for.

```bash
omarchy plugin add https://github.com/sjdsjadjajdjsa/nyx.git --enable
```

Then add a shortcut to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + N", "Nyx", "omarchy-shell nyx toggle")
```

<details>
<summary>Install from a local folder instead</summary>

```bash
git clone https://github.com/sjdsjadjajdjsa/nyx.git ~/Work/nyx
ln -s ~/Work/nyx ~/.config/omarchy/plugins/cj.nyx
omarchy-shell shell rescanPlugins
omarchy plugin enable cj.nyx
```

After editing the QML, run `omarchy restart shell` if a change doesn't show up.

</details>

## Use

- **Chat:** click Nyx or `Super+N`. Enter sends, Esc closes.
- **Run something:** Nyx shows the command; **Run** does it, **Cancel**
  doesn't. Nyx then tells you how it went.
- **New chat:** the ↺ button forgets the conversation.
- **Bubbles:** click one to open the chat, or **Nah** to dismiss it.

Things to try:

```
what's using the most memory?
why is my laptop so warm?
switch to a light theme for today
remind me to stretch in 20 minutes
make the window gaps smaller
```

While the chat is open it holds the keyboard, so close it (Esc) to type
elsewhere.

## Settings

Optional, in `~/.config/nyx/config.json`:

```json
{
  "model": "haiku",
  "speakUp": true
}
```

| Key | Default | What it does |
|---|---|---|
| `model` | `haiku` | Claude model. `haiku` is fast; `sonnet` is smarter and slower. |
| `speakUp` | `true` | `false` stops the speech bubbles. Reactions stay. |

Nyx sends what you type, plus whatever it reads on your system to answer,
to Claude, the same way Claude Code does.

## How it works

```
 you ──▶ Nyx.qml ──▶ bin/nyx-ask ──▶ claude -p (read-only tools)
           ▲                               │
           └──── reply + mood + action ◀───┘
                        │
              Run / Cancel card ──▶ bash
```

- **`Nyx.qml`** is an Omarchy shell plugin (a `panel`): the window, chat
  bubble, speech bubbles and the senses (music through MPRIS, battery through
  UPower, notifications through D-Bus, the time of day).
- **`Orb.qml`** is Nyx's body: glow, eyes, blinking and every mood.
- **`bin/nyx-ask`** runs `claude -p` with a JSON schema for the reply, a mood
  and an optional action. Claude may only use an allowlist of read-only
  commands (`ps`, `free`, `upower`, `hyprctl clients`, `omarchy theme current`
  and so on); everything else is denied, so changes can only come back as an
  action for you to approve.
- **`prompt.md`** is Nyx's personality and rules.

Shell commands, handy for scripts and testing:

```bash
omarchy-shell nyx toggle | open | close | reset | hush
omarchy-shell nyx ask "how's my battery?"
omarchy-shell nyx say "hello!"
omarchy-shell nyx demo music   # music | battery | plug | night | notify | sleep | yawn
```

## License

[MIT](LICENSE)
