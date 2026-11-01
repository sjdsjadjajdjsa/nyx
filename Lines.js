.pragma library

// Everything Nyx says on its own, a handful of ways per moment so it never
// sounds canned. Edit freely: {title}, {artist}, {pct}, {temp}, {app},
// {device} and {mins} are filled in when Nyx speaks.

var lines = {
  morning: [
    "Good morning ☀️ Ready when you are.",
    "Morning! I kept the desktop warm for you.",
    "Rise and shine ✨ What are we making today?",
    "Hey, good morning! Coffee first, then world domination?",
    "Morning ☕ I'm awake. Mostly.",
    "Oh hi! New day, fresh start 🌱",
  ],
  back: [
    "Oh! You're back 👋",
    "Welcome back! I missed you a little.",
    "There you are ✨",
    "Hey hey, you're back!",
    "Back already? I was having the best nap 😴",
    "Oh hi! I kept your spot.",
  ],
  plugged: [
    "Ahh, power ⚡ thank you!",
    "Charging up! I feel more alive already 🔋",
    "Mmm, electricity. Thanks!",
    "Plugged in ⚡ Crisis averted.",
    "Yay, juice! 🔌",
  ],
  battery20: [
    "Battery's at {pct}%. Want me to switch to power saver?",
    "We're down to {pct}% 🔋 Power saver mode?",
    "{pct}% left. Shall I stretch it with power saver?",
    "Getting low, {pct}%. Want power saver on?",
  ],
  battery10: [
    "Battery's at {pct}%! Plug me in pleeease 🔌",
    "{pct}%!! I'm fading here 😵 Charger?",
    "Only {pct}% left. A charger would be heroic right now 🦸",
    "{pct}% battery. This is not a drill 🔌",
  ],
  night: [
    "It's getting late 🌙 Want night light on?",
    "Late night, huh? Night light would be easier on your eyes 🌙",
    "The screen's pretty bright for this hour. Night light?",
    "Past 11 already 🌙 Want me to warm up the screen?",
  ],
  lateCoding: [
    "Coding after midnight? Respect. Don't forget water 💧",
    "It's {time}. The bugs will still be there tomorrow 🐛",
    "Late-night {app} session? I'll keep you company 🌙",
    "Night owl mode 🦉 Want me to set a bedtime reminder?",
    "Midnight commits hit different. Save often!",
  ],
  stretch: [
    "You've been at it for {mins} minutes. Quick stretch? 🙆",
    "{mins} minutes straight! Your back says hi. Stretch?",
    "Time for a tiny break? Even 2 minutes helps ✨",
    "Hydration check 💧 You've been going for {mins} minutes.",
    "Look away from the screen for 20 seconds 👀 Doctor's orders. Well, mine.",
  ],
  song: [
    "Ooh, {title} by {artist} 🎶",
    "{title}! Good choice 🎧",
    "Now playing: {title} 🎶 I'm vibing.",
    "{artist}? Excellent taste ✨",
    "Ooh, this one! {title} 🎵",
    "*bops to {title}* 🎶",
  ],
  songNoArtist: [
    "Ooh, {title} 🎶",
    "{title}! I'm vibing 🎧",
    "*bops to {title}* 🎶",
  ],
  wifiLost: [
    "Uh oh, Wi-Fi's gone 📡",
    "We lost the internet! I'm still here though.",
    "Offline 📴 Want me to look into it?",
    "No internet right now. Spooky 👻",
  ],
  wifiBack: [
    "Internet's back 🌐",
    "We're online again ✨",
    "Reconnected! Phew.",
  ],
  headphones: [
    "Headphones on 🎧 {device}",
    "Ooh, {device}. Private listening mode 🎧",
    "Switched to {device} 🎧",
  ],
  speakers: [
    "Back on the speakers 🔊",
    "Sound's coming out of the speakers again 🔊",
  ],
  hot: [
    "I'm toasty! {temp}°C 🥵 Want to see what's working so hard?",
    "Phew, {temp}°C in here 🔥 Something's busy.",
    "It's getting hot, {temp}°C. Want me to find out why?",
  ],
  disk: [
    "Your disk is {pct}% full 💾 Want help finding big stuff?",
    "Running low on space, {pct}% used. Cleanup time?",
  ],
}

var recent = {}

// Pick a line for `key`, avoiding the last few used, and fill in the {vars}.
function pick(key, vars) {
  var pool = lines[key] || []
  if (pool.length === 0) return ""
  var used = recent[key] || []
  var fresh = []
  for (var i = 0; i < pool.length; i++)
    if (used.indexOf(i) === -1) fresh.push(i)
  if (fresh.length === 0) { used = []; fresh = pool.map(function(_, j) { return j }) }
  var idx = fresh[Math.floor(Math.random() * fresh.length)]
  used.push(idx)
  while (used.length > Math.max(1, Math.floor(pool.length / 2))) used.shift()
  recent[key] = used
  return pool[idx].replace(/\{(\w+)\}/g, function(m, name) {
    return vars && vars[name] !== undefined ? String(vars[name]) : m
  })
}
