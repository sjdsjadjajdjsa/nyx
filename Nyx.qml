import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "Lines.js" as Lines
import qs.Commons
import qs.Commons as Commons

// Nyx — a little AI buddy for Omarchy.
//
// Click the orb (or Super+N → `omarchy-shell nyx toggle`) to chat.
// Nyx can look around your system on its own; anything that changes
// something comes back as a Run / Cancel card.
Item {
  id: root

  property var shell
  property string omarchyPath
  property var manifest

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property string askBin: pluginDir + "bin/nyx-ask"

  // look & layout (logical px)
  readonly property int edge: 14
  readonly property int orbSize: 54
  readonly property int cardWidth: 380
  readonly property int cardHeight: 470
  readonly property string fontFamily: Style.font.family

  property bool chatOpen: false
  property bool busy: false
  property string brainName: ""
  property string transientMood: ""
  property bool sleeping: false
  property double sleptAt: 0
  // What Nyx looks like right now: thinking > a short reaction > asleep > background mood.
  readonly property string baseMood: musicPlaying ? "vibing" : batteryLow ? "worried" : "idle"
  readonly property string mood: busy || runningIndex !== -1 ? "thinking"
    : transientMood !== "" ? transientMood
    : sleeping ? "sleepy" : baseMood
  property real lookX: 0
  property real lookY: 0
  property int runningIndex: -1
  // Each new chat bumps chatGen; replies and Run results from an older chat are dropped.
  property int chatGen: 0
  property int askGen: 0
  property int runGen: 0
  // Run is ignored briefly after the list moves, so a click can't land on a card that just scrolled in.
  property real runGuardUntil: 0
  property double lastPointerMove: Date.now()
  property point lastPointer: Qt.point(-1, -1)

  function c(col, a) { return Qt.rgba(col.r, col.g, col.b, a) }

  function setMood(m, holdMs) {
    transientMood = (m === "thinking" || m === "idle") ? "" : m
    moodReset.interval = holdMs > 0 ? holdMs : 4000
    moodReset.restart()
  }

  function wake(quiet) {
    onActivity()
    lastPointerMove = Date.now()
    if (!sleeping) return
    var sleptFor = Date.now() - sleptAt
    sleeping = false
    if (!quiet && sleptFor > 600000) say({ key: "back", mood: "happy", hop: true, every: 30 })
    else setMood("curious", 2000)
  }

  function open() {
    chatOpen = true
    hideTip()
    if (sleeping) { sleeping = false; setMood("happy", 1500) }
    lastPointerMove = Date.now()
    if (messages.count === 0)
      messages.append({ who: "nyx", text: "Hey, I'm Nyx ✨ Ask me anything about your machine, or tell me what to change.", command: "", label: "", status: "" })
    focusTimer.restart()
  }
  function close() { chatOpen = false }
  function toggle() { chatOpen ? close() : open() }

  function send(text) {
    text = String(text || "").trim()
    if (!text || busy) return
    messages.append({ who: "you", text: text, command: "", label: "", status: "" })
    ask(text)
  }

  function ask(text) {
    busy = true
    askGen = chatGen
    askProc.start(["setpriv", "--pdeathsig", "TERM", askBin], text)
  }

  function handleReply(raw) {
    busy = false
    if (askGen !== chatGen) return  // answer to a chat that was reset meanwhile
    var res
    try { res = JSON.parse(String(raw || "").trim().split("\n").pop()) }
    catch (e) { res = { ok: false, reply: "I couldn't understand my own brain just now 😵", mood: "worried" } }
    if (res.brain) brainName = res.brain
    messages.append({ who: "nyx", text: res.reply || "…", command: "", label: "", status: "" })
    if (res.action && res.action.command)
      messages.append({ who: "action", text: "", command: res.action.command, label: res.action.label || "Run this?", status: "pending" })
    setMood(res.mood && res.mood !== "neutral" ? res.mood : "happy", 4000)
  }

  // A command must be one plain line: nothing that could make the card show
  // something other than what runs (controls, bidi or zero-width marks, odd
  // whitespace). nyx-ask already refuses these; this is a second check.
  function plainCommand(cmd) {
    return cmd.length > 0 && cmd.length <= 400
      && !/[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb\ud800-\udfff]|[^\S ]/.test(cmd)
  }

  function runAction(index) {
    if (runningIndex !== -1 || Date.now() < runGuardUntil) return
    var item = messages.get(index)
    if (!plainCommand(item.command)) {
      messages.setProperty(index, "status", "failed")
      messages.setProperty(index, "text", "Not run: the command has hidden characters.")
      return
    }
    messages.setProperty(index, "status", "running")
    runningIndex = index
    runGen = chatGen
    runProc.output = ""
    runProc.stopped = false
    // Killed with the shell, stopped after 5 minutes, output capped (see runProc).
    runProc.command = ["setpriv", "--pdeathsig", "TERM", "timeout", "-k", "5", "300", "bash", "-c", item.command]
    runProc.running = true
  }
  function stopAction() { if (runProc.running) { runProc.stopped = true; runProc.signal(15) } }

  function finishAction(exitCode, output) {
    var index = runningIndex
    runningIndex = -1
    if (index < 0 || runGen !== chatGen) return  // chat was reset while it ran
    var ok = exitCode === 0
    var stopped = runProc.stopped || exitCode === 124  // Stop button, or the 5-minute limit
    messages.setProperty(index, "status", ok ? "done" : stopped ? "stopped" : "failed")
    var tail = String(output || "").trim().split("\n").slice(-12).join("\n")
    messages.setProperty(index, "text", tail)
    // Let Nyx react to the result.
    var how = runProc.stopped ? "was stopped by the user" : exitCode === 124 ? "was stopped after 5 minutes"
            : "exited " + exitCode
    ask("[ran] `" + messages.get(index).command + "` " + how + (tail ? ". Output:\n" + tail.slice(-1500) : " with no output."))
  }

  function resetChat() {
    chatGen++
    if (askProc.running) askProc.running = false
    if (runProc.running) runProc.signal(15)
    busy = false
    runningIndex = -1
    messages.clear()
    resetProc.running = true
    open()
  }

  ListModel { id: messages }

  Timer { id: moodReset; interval: 4000; onTriggered: root.transientMood = "" }
  Timer { id: focusTimer; interval: 60; onTriggered: input.forceActiveFocus() }

  // Private text (chat messages, quip context) goes to nyx-ask on stdin, never
  // in argv, so other users can't read it from `ps` or /proc/<pid>/cmdline.
  component StdinProcess: Process {
    property string input: ""
    function start(cmd, text) { input = text; stdinEnabled = true; command = cmd; running = true }
    onStarted: { write(input); input = ""; stdinEnabled = false }  // false closes stdin (EOF)
  }

  StdinProcess {
    id: askProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleReply(text) }
  }

  Process {
    id: runProc
    // Keep at most ~16 KB of output so a chatty command can't fill the shell's memory.
    property string output: ""
    property bool stopped: false
    function take(line) { if (output.length < 16000) output += line + "\n" }
    stdout: SplitParser { onRead: line => runProc.take(line) }
    stderr: SplitParser { onRead: line => runProc.take(line) }
    onExited: (exitCode, exitStatus) => Qt.callLater(function() { root.finishAction(exitCode, runProc.output) })
  }

  Process { id: resetProc; command: [root.askBin, "--reset"] }

  // Eyes follow the pointer; Nyx dozes off after a few idle minutes.
  Process {
    id: cursorProc
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var p = JSON.parse(text)
          var scr = win.screen
          var cx = scr.x + scr.width - win.implicitWidth + orb.x + orb.width / 2
          var cy = scr.y + scr.height - win.implicitHeight + orb.y + orb.height / 2
          var dx = p.x - cx, dy = p.y - cy
          if (p.x !== root.lastPointer.x || p.y !== root.lastPointer.y) {
            root.lastPointer = Qt.point(p.x, p.y)
            root.wake()
          } else if (!root.sleeping && !root.chatOpen && !root.busy && root.transientMood === "" && !root.musicPlaying
                     && Date.now() - root.lastPointerMove > (root.isNight ? 60000 : 180000)) {
            root.sleeping = true
            root.sleptAt = Date.now()
          }
          var d = Math.max(1, Math.sqrt(dx * dx + dy * dy))
          var reach = Math.min(1, d / 260)
          root.lookX = dx / d * reach
          root.lookY = dy / d * reach
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: 180
    running: true
    repeat: true
    onTriggered: if (!cursorProc.running && root.mood !== "thinking") cursorProc.running = true
  }

  // ================================================================ senses
  // Settings: ~/.config/nyx/config.json
  //   "chattiness": "quiet" | "normal" | "chatty"   ("speakUp": false = quiet)
  property var config: ({})
  readonly property string chattiness: config.speakUp === false ? "quiet"
    : (["quiet", "normal", "chatty"].indexOf(config.chattiness) !== -1 ? config.chattiness : "normal")
  readonly property bool speakUp: chattiness !== "quiet"
  readonly property bool chatty: chattiness === "chatty"
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/nyx/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.config = JSON.parse(text()) || {} } catch (e) { root.config = {} } }
    onLoadFailed: root.config = {}
  }

  // --- music
  readonly property var activePlayer: {
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
    return null
  }
  readonly property bool musicPlaying: activePlayer !== null
  property string lastTrack: ""
  onActivePlayerChanged: musicCheck.restart()
  onMusicPlayingChanged: if (musicPlaying) wake(true)   // nobody sleeps through a song
  Connections {
    target: root.activePlayer
    ignoreUnknownSignals: true
    function onTrackTitleChanged() { musicCheck.restart() }
  }
  Timer {
    id: musicCheck
    interval: 1200 // let title/artist settle
    onTriggered: {
      var p = root.activePlayer
      if (!p) return
      var title = String(p.trackTitle || "").trim()
      var artist = String(p.trackArtist || "").trim()
      var key = title + "|" + artist
      if (!title || key === root.lastTrack) return
      root.lastTrack = key
      root.say({ key: artist ? "song" : "songNoArtist", vars: { title: title, artist: artist },
                 mood: "vibing", hop: true, every: root.chatty ? 0 : 15 })
    }
  }

  // --- beat: glow and wobble to what's actually playing (bin/nyx-beat).
  // Runs only while music plays; "beatGlow": false in config turns it off.
  readonly property bool beatGlow: config.beatGlow !== false
  Process {
    id: beatProc
    command: ["setpriv", "--pdeathsig", "TERM", root.pluginDir + "bin/nyx-beat"]
    running: root.beatGlow && root.musicPlaying
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var m = JSON.parse(line)
          orb.audioLevel = m.l
          if (m.b) orb.beat()
        } catch (e) {}
      }
    }
    onRunningChanged: if (!running) orb.audioLevel = 0
  }

  // --- battery
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: battery && battery.isLaptopBattery
  readonly property int batteryPct: {
    if (!hasBattery) return 100
    var p = battery.percentage
    return Math.round(p <= 1 ? p * 100 : p)
  }
  readonly property bool discharging: hasBattery && UPower.onBattery
  readonly property bool batteryLow: discharging && batteryPct <= 20
  property int batteryWarnedAt: 101
  onBatteryPctChanged: batteryCheck()
  onDischargingChanged: {
    if (!discharging && hasBattery) {
      batteryWarnedAt = 101
      say({ key: "plugged", mood: "happy", hop: true, every: 10 })
    } else {
      batteryCheck()
    }
  }
  function batteryCheck() {
    if (!discharging) return
    if (batteryPct <= 10 && batteryWarnedAt > 10) {
      batteryWarnedAt = batteryPct
      say({ key: "battery10", vars: { pct: batteryPct }, mood: "worried", hop: true, urgent: true, hold: 20000 })
    } else if (batteryPct <= 20 && batteryWarnedAt > 20) {
      batteryWarnedAt = batteryPct
      say({ key: "battery20", vars: { pct: batteryPct }, mood: "worried",
            actionLabel: "Power saver", command: "powerprofilesctl set power-saver", hold: 20000 })
    }
  }

  // --- notifications (watched, never read)
  Process {
    id: notifyWatch
    // --profile prints one header line per call (no title or body), so the
    // contents of notifications never reach Nyx at all.
    command: ["setpriv", "--pdeathsig", "TERM", "dbus-monitor", "--session", "--profile",
              "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (!/^mc\t.*\tNotify$/.test(line) || root.chatOpen) return
        root.wake()
        orb.hop()
        root.setMood("curious", 1800)
      }
    }
    onExited: notifyRestart.restart()
  }
  Timer { id: notifyRestart; interval: 5000; onTriggered: notifyWatch.running = true }

  // --- stay out of the way: fullscreen apps and screen sharing ------------
  // Nyx fades out (and lets clicks through) while the monitor it's on shows
  // something fullscreen, or while the screen is being shared or recorded
  // through the portal. Opening the chat (Super+N) still works.
  // "hideInFullscreen": false in config turns it off.
  readonly property bool hideWhenBusy: config.hideInFullscreen !== false
  property bool screencasting: false
  property bool previewTucked: false
  readonly property var nyxMonitor: Hyprland.monitorFor(win.screen)
  readonly property bool fullscreenHere: !!(nyxMonitor && nyxMonitor.activeWorkspace && nyxMonitor.activeWorkspace.hasFullscreen)
  readonly property bool tucked: !chatOpen && (previewTucked || (hideWhenBusy && (fullscreenHere || screencasting)))
  onTuckedChanged: if (tucked) hideTip()
  Connections {
    target: Hyprland
    // screencast>>STATE,OWNER: STATE is 1 while sharing or recording
    function onRawEvent(event) {
      if (event.name === "screencast") root.screencasting = String(event.data).split(",")[0] === "1"
    }
  }

  // --- theme changes: gasp, sparkle, fade into the new colors -------------
  readonly property color themeAccent: Commons.Color.accent
  readonly property double startedAt: Date.now()
  onThemeAccentChanged: if (Date.now() - startedAt > 10000) themeDebounce.restart()
  Timer { id: themeDebounce; interval: 1200; onTriggered: root.themeChanged() }
  function themeChanged() {
    if (tucked) return
    wake(true)
    orb.hop()
    orb.sparkle(24)
    setMood("happy", 3000)
    themeNameProc.running = true
  }
  Process {
    id: themeNameProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim() || "This"
        // A theme change is something you just did, so skip the usual spacing between bubbles.
        if (name !== "Unknown" && root.speakUp) root.say({ key: "theme", vars: { theme: name }, cooldown: false })
      }
    }
  }

  // --- petting: stroke the mouse back and forth over Nyx -----------------
  property real petLastX: -1
  property int petDir: 0
  property int petStrokes: 0
  property double petLastStroke: 0
  property double lastPetAt: 0
  property double lastPetLineAt: 0
  function petMove(x) {
    var now = Date.now()
    if (petLastX < 0 || now - petLastStroke > 700) { petStrokes = 0; petDir = 0; petLastX = x; petLastStroke = now; return }
    var dx = x - petLastX
    if (Math.abs(dx) < 3) return
    var dir = dx > 0 ? 1 : -1
    if (petDir !== 0 && dir !== petDir) { petStrokes++; petLastStroke = now }
    petDir = dir
    petLastX = x
    if (petStrokes >= 4 && now - lastPetAt > 2500) {
      petStrokes = 0
      lastPetAt = now
      pet()
    }
  }
  function pet() {
    wake(true)
    orb.petted = true
    petTimer.restart()
    orb.sparkle(6)
    setMood("happy", 2600)
    // say something now and then, never more than once every 2 minutes
    if (speakUp && Date.now() - lastPetLineAt > 120000 && Math.random() < 0.35) {
      lastPetLineAt = Date.now()
      say({ key: "pet", cooldown: false })
    }
  }
  Timer { id: petTimer; interval: 2600; onTriggered: orb.petted = false }

  // --- special days: birthday, New Year, Christmas, Halloween, Valentine's
  // A hat (or snow in December) and one greeting per day. "seasonal": false
  // turns it off; "birthday": "MM-DD" adds yours.
  readonly property bool seasonal: config.seasonal !== false
  property string todayMD: Qt.formatDate(new Date(), "MM-dd")
  property string previewMD: ""    // set through IPC `date` to preview a day
  readonly property string dayMD: previewMD !== "" ? previewMD : todayMD
  readonly property string birthday: /^\d\d-\d\d$/.test(String(config.birthday || "")) ? config.birthday : ""
  readonly property string occasion: !seasonal ? ""
    : dayMD === birthday ? "birthday"
    : dayMD === "01-01" ? "newYear"
    : dayMD >= "12-24" && dayMD <= "12-26" ? "christmas"
    : dayMD === "10-31" ? "halloween"
    : dayMD === "02-14" ? "valentine"
    : dayMD.slice(0, 2) === "12" ? "december" : ""
  readonly property string occasionHat: occasion === "birthday" || occasion === "newYear" ? "party"
    : occasion === "christmas" ? "santa" : occasion === "halloween" ? "witch" : ""
  property string occasionGreetedOn: ""
  onOccasionChanged: Qt.callLater(greetOccasion)
  function greetOccasion() {
    if (occasion === "" || occasion === "december" || occasionGreetedOn === dayMD + occasion || tucked) return
    occasionGreetedOn = dayMD + occasion
    orb.hop()
    var n = occasion === "birthday" || occasion === "newYear" ? 3 : 1
    for (var i = 0; i < n; i++) confetti.start()
    say({ key: occasion, mood: "happy", hop: true, urgent: occasion === "birthday" || occasion === "newYear", hold: 12000 })
  }
  // A few bursts of sparkles a moment apart.
  Timer {
    id: confetti
    property int left: 0
    interval: 350
    repeat: true
    function start() { left = 4; restart() }
    onTriggered: { orb.sparkle(28); if (--left <= 0) stop() }
  }
  // Snow in December: a minute of gentle flurries every quarter hour.
  Timer {
    interval: 15 * 60000
    running: root.occasion !== "" && (root.occasion === "december" || root.occasion === "christmas")
    repeat: true
    triggeredOnStart: true
    onTriggered: { if (!root.tucked) { orb.snowing = true; snowStop.restart() } }
  }
  Timer { id: snowStop; interval: 60000; onTriggered: orb.snowing = false }

  // --- time of day
  property int hour: new Date().getHours()

  // Nyx's look follows the clock on top of the theme's accent color: a warm
  // peach at sunrise, the plain theme color by day, golden hour in the
  // evening, cooler and dimmer at night. Blended minute by minute.
  // "timeOfDay": false in config turns it off.
  readonly property bool timeOfDay: config.timeOfDay !== false
  property int clockMinutes: new Date().getHours() * 60 + new Date().getMinutes()
  property real previewHour: -1    // set through IPC `clock` to preview a time
  readonly property real dayMinute: previewHour >= 0 ? previewHour * 60 : clockMinutes
  // [minute of day, tint, how much tint, lightness, glow]
  readonly property var dayKeys: [
    [0,    "#7d8cff", 0.22, 0.82, 0.65],   // night: cool, dim
    [330,  "#7d8cff", 0.22, 0.82, 0.65],   // 5:30
    [420,  "#ffb38a", 0.18, 1.04, 1.0],    // 7:00 sunrise peach
    [600,  "#ffffff", 0.0,  1.0,  1.0],    // 10:00 plain theme color
    [990,  "#ffffff", 0.0,  1.0,  1.0],    // 16:30
    [1140, "#ffc35c", 0.22, 1.0,  1.1],    // 19:00 golden hour
    [1290, "#7d8cff", 0.22, 0.82, 0.65],   // 21:30 night again
    [1440, "#7d8cff", 0.22, 0.82, 0.65]
  ]
  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  function keyColor(base, key) {
    var c = mixColor(base, Qt.color(key[1]), key[2])
    return Qt.hsla(c.hslHue, c.hslSaturation * (key[3] < 1 ? 0.9 : 1), Math.min(1, c.hslLightness * key[3]), 1)
  }
  function dayLook(base, minute) {
    var k = dayKeys
    for (var i = 0; i < k.length - 1; i++) {
      if (minute >= k[i][0] && minute <= k[i + 1][0]) {
        var t = (minute - k[i][0]) / Math.max(1, k[i + 1][0] - k[i][0])
        t = t * t * (3 - 2 * t)  // ease in and out
        return { color: mixColor(keyColor(base, k[i]), keyColor(base, k[i + 1]), t),
                 glow: k[i][4] + (k[i + 1][4] - k[i][4]) * t }
      }
    }
    return { color: base, glow: 1 }
  }
  readonly property var look: timeOfDay ? dayLook(Commons.Color.accent, dayMinute) : { color: Commons.Color.accent, glow: 1 }
  readonly property bool isNight: hour >= 23 || hour < 5
  property string nightOfferedOn: ""
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var now = new Date()
      root.hour = now.getHours()
      root.clockMinutes = now.getHours() * 60 + now.getMinutes()
      root.todayMD = Qt.formatDate(now, "MM-dd")
      if (root.occasionGreetedOn === "") Qt.callLater(root.greetOccasion)
      if (!root.isNight) return
      // occasional yawn
      if (!root.sleeping && !root.busy && !root.chatOpen && root.transientMood === "" && Math.random() < 0.15)
        root.setMood("yawn", 1800)
      // once per night: offer night light if it's off
      var night = Qt.formatDate(new Date(new Date().getTime() - 5 * 3600000), "yyyy-MM-dd")
      if (root.nightOfferedOn !== night && !nightProbe.running) {
        root.nightOfferedOn = night
        nightProbe.running = true
      }
    }
  }
  Process {
    id: nightProbe
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text || "").match(/[0-9]+/)
        var on = m && Number(m[0]) < 6000
        if (!on) root.say({ key: "night", mood: "sleepy",
                            actionLabel: "Night light", command: "omarchy toggle nightlight", hold: 20000 })
      }
    }
  }

  // --- your day: good morning, long sessions, late-night coding
  property double activeSince: Date.now()
  property double lastActive: Date.now()
  property string greetedOn: ""
  property string lateCodingOn: ""
  readonly property string focusedApp: ToplevelManager.activeToplevel ? String(ToplevelManager.activeToplevel.appId || "") : ""
  readonly property bool codingApp: /terminal|foot|kitty|alacritty|ghostty|wezterm|code|codium|cursor|zed|nvim|neovim|jetbrains|idea|pycharm|webstorm|clion|goland|rustrover/i.test(focusedApp)

  function onActivity() {
    var now = Date.now()
    if (now - lastActive > 5 * 60000) activeSince = now   // a 5+ min break resets the session
    lastActive = now
    var d = new Date()
    var today = Qt.formatDate(d, "yyyy-MM-dd")
    if (d.getHours() >= 5 && d.getHours() < 11 && greetedOn !== today) {
      greetedOn = today
      say({ key: "morning", mood: "happy", hop: true })
    }
  }
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      if (now - root.lastActive > 2 * 60000 || root.busy) return
      var mins = Math.round((now - root.activeSince) / 60000)
      if (mins >= 90) say({ key: "stretch", vars: { mins: mins }, mood: "curious", hop: true, every: 75 })
      var h = new Date().getHours()
      var night = Qt.formatDate(new Date(now - 5 * 3600000), "yyyy-MM-dd")
      if (h < 4 && root.codingApp && root.lateCodingOn !== night) {
        root.lateCodingOn = night
        say({ key: "lateCoding", vars: { time: Qt.formatTime(new Date(), "h:mm"), app: root.focusedApp.split(".").pop() },
              mood: "sleepy", actionLabel: "Remind me", ask: "remind me to go to bed in 30 minutes" })
      }
    }
  }

  // --- Wi-Fi drops and comes back
  property string netState: ""
  property double netLostAt: 0
  Process {
    id: netProbe
    command: ["nmcli", "-t", "-f", "STATE", "general"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = String(text || "").trim()
        var up = st.indexOf("connected") === 0, down = st === "disconnected" || st === "asleep"
        if (!up && !down) return            // connecting, unknown: wait
        var next = up ? "up" : "down"
        if (root.netState === "up" && next === "down") {
          root.netLostAt = Date.now()
          root.say({ key: "wifiLost", mood: "worried", ask: "my internet just dropped, can you check what's going on?", every: 10 })
        } else if (root.netState === "down" && next === "up" && Date.now() - root.netLostAt > 20000) {
          root.say({ key: "wifiBack", mood: "happy", hop: true, every: 10 })
        }
        root.netState = next
      }
    }
  }
  Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!netProbe.running) netProbe.running = true }

  // --- headphones / speakers
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property string sinkName: sink ? String(sink.description || sink.nickname || sink.name || "") : ""
  property string lastSinkName: ""
  onSinkNameChanged: sinkSettle.restart()
  Timer {
    id: sinkSettle
    interval: 1500
    onTriggered: {
      var name = root.sinkName
      if (!name || name === root.lastSinkName) return
      var first = root.lastSinkName === ""
      root.lastSinkName = name
      if (first) return
      if (/head|bluetooth|bt|airpods|buds|earbud|wh-|wf-/i.test(name))
        root.say({ key: "headphones", vars: { device: name }, mood: "happy", hop: true, every: 5 })
      else
        root.say({ key: "speakers", mood: "neutral", every: 5 })
    }
  }

  // --- running hot, disk filling up
  property int hotStreak: 0
  Process {
    id: heatProbe
    command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null; df --output=pcent / | tail -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = String(text || "").trim().split("\n")
        var disk = parseInt(rows.pop())
        var temp = 0
        for (var i = 0; i < rows.length; i++) temp = Math.max(temp, parseInt(rows[i]) / 1000 || 0)
        root.hotStreak = temp >= 88 ? root.hotStreak + 1 : 0
        if (root.hotStreak >= 2)
          root.say({ key: "hot", vars: { temp: Math.round(temp) }, mood: "worried",
                     ask: "my laptop is running hot, what's using the most CPU right now?", every: 30 })
        if (disk >= 90)
          root.say({ key: "disk", vars: { pct: disk }, mood: "worried",
                     ask: "my disk is almost full, what's taking up the most space in my home folder?", every: 24 * 60 })
      }
    }
  }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: if (!heatProbe.running) heatProbe.running = true }

  // --- AI small talk (chatty only): now and then, a fresh one-liner about
  // the moment from the brain. Only the hour, the focused app's name, the
  // song and the battery level are sent along.
  property double lastQuipAt: Date.now()
  Timer {
    interval: 5 * 60000
    running: root.chatty
    repeat: true
    onTriggered: {
      var now = Date.now()
      if (root.busy || root.chatOpen || root.sleeping || quipProc.running) return
      if (now - root.lastActive > 3 * 60000) return
      if (now - root.lastQuipAt < 40 * 60000 || Math.random() < 0.5) return
      root.lastQuipAt = now
      var p = root.activePlayer
      var ctx = "time " + Qt.formatTime(new Date(), "h:mm AP") + ", " + Qt.formatDate(new Date(), "dddd")
        + (root.focusedApp ? "; using " + root.focusedApp : "")
        + (p && p.trackTitle ? "; listening to " + p.trackTitle + (p.trackArtist ? " by " + p.trackArtist : "") : "")
        + (root.hasBattery ? "; battery " + root.batteryPct + "%" + (root.discharging ? "" : " charging") : "")
        + "; active for " + Math.round((now - root.activeSince) / 60000) + " min"
      quipProc.start([root.askBin, "--quip"], ctx)
    }
  }
  StdinProcess {
    id: quipProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var r = JSON.parse(String(text || "").trim().split("\n").pop())
          if (r.ok && r.reply) root.say({ text: r.reply, mood: r.mood && r.mood !== "neutral" ? r.mood : "happy", hop: true })
        } catch (e) {}
      }
    }
  }

  // ============================================================ speech tips
  // say({ key | text, vars, mood, hop, actionLabel, command, ask, hold, urgent, every })
  //   key     a moment from Lines.js (a fresh line is picked each time)
  //   urgent  skips chattiness limits (low battery); "quiet" still shows these
  //   every   minimum minutes between bubbles for this same key
  //   ask     a question; the bubble gets a button that asks Nyx it in chat
  property var tip: null
  property string tipResult: ""
  property double lastTipAt: 0
  property var lastSaid: ({})

  function say(t) {
    if (!t) return
    var text = t.text || (t.key ? Lines.pick(t.key, t.vars) : "")
    if (!text) return
    if (t.mood) setMood(t.mood, t.mood === "vibing" ? 3000 : 3500)
    if (t.hop) orb.hop()
    if (chatOpen || tucked) return  // never pop up over fullscreen or a screen share
    var urgent = t.urgent === true || t.cooldown === false
    if (!urgent) {
      if (!speakUp) return
      if (Date.now() - lastTipAt < (chatty ? 45000 : 120000)) return
      if (t.key && t.every > 0 && Date.now() - (lastSaid[t.key] || 0) < t.every * 60000) return
    }
    lastTipAt = Date.now()
    if (t.key) { var ls = lastSaid; ls[t.key] = Date.now(); lastSaid = ls }
    tipResult = ""
    t.text = text
    tip = t
    tipTimer.interval = t.hold || (t.command || t.ask ? 15000 : 7000)
    tipTimer.restart()
  }
  function hideTip() { tip = null; tipResult = "" }
  function tipToChat() {
    var t = tip
    hideTip()
    open()
    if (t) messages.append({ who: "nyx", text: t.text, command: "", label: "", status: "" })
    if (t && t.command)
      messages.append({ who: "action", text: "", command: t.command, label: t.actionLabel || "Run this?", status: "pending" })
  }
  // Bubble buttons never run anything themselves: a command goes to a Run card
  // in the chat, where the exact command is shown first.
  function runTip() {
    if (tip && tip.ask) { var q = tip.ask; hideTip(); open(); send(q); return }
    if (tip && tip.command) tipToChat()
  }
  Timer { id: tipTimer; onTriggered: if (!tipArea.containsMouse) root.hideTip(); else restart() }

  IpcHandler {
    target: "nyx"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function reset(): string { root.resetChat(); return "ok" }
    // Preview a special day: `date 12-25`, `date 10-31`; `date now` goes back to today.
    function date(md: string): string {
      root.previewMD = /^\d\d-\d\d$/.test(md) ? md : ""
      return root.previewMD === "" ? "now" : "previewing " + root.previewMD + " (" + (root.occasion || "nothing special") + ")"
    }
    // Preview hiding: `tuck on` / `tuck off`.
    function tuck(state: string): string { root.previewTucked = state === "on"; return root.tucked ? "hidden" : "shown" }
    // Preview Nyx's time-of-day look: `clock 19.5` is 19:30; `clock now` goes back to the real time.
    function clock(hour: string): string {
      var h = Number(hour)
      root.previewHour = hour === "now" || isNaN(h) ? -1 : Math.max(0, Math.min(24, h))
      return root.previewHour < 0 ? "now" : "previewing " + root.previewHour
    }
    function ask(text: string): string { root.open(); root.send(text); return "ok" }
    function hush(): string { root.hideTip(); return "ok" }
    function say(text: string): string { root.say({ text: text, mood: "happy", hop: true, cooldown: false }); return "ok" }
    // Try reactions without waiting for them (see the list in the error below)
    function demo(kind: string): string {
      if (kind === "music") root.say({ key: "song", vars: { title: "Starlight", artist: "Nocturne" }, mood: "vibing", hop: true, urgent: true })
      else if (kind === "battery") root.say({ key: "battery20", vars: { pct: 18 }, mood: "worried", actionLabel: "Power saver", command: "powerprofilesctl set power-saver", urgent: true, hold: 20000 })
      else if (kind === "plug") root.say({ key: "plugged", mood: "happy", hop: true, urgent: true })
      else if (kind === "night") root.say({ key: "night", mood: "sleepy", actionLabel: "Night light", command: "omarchy toggle nightlight", urgent: true, hold: 20000 })
      else if (kind === "morning") root.say({ key: "morning", mood: "happy", hop: true, urgent: true })
      else if (kind === "stretch") root.say({ key: "stretch", vars: { mins: 95 }, mood: "curious", hop: true, urgent: true })
      else if (kind === "latecoding") root.say({ key: "lateCoding", vars: { time: "1:12", app: "foot" }, mood: "sleepy", actionLabel: "Remind me", ask: "remind me to go to bed in 30 minutes", urgent: true })
      else if (kind === "wifi") root.say({ key: "wifiLost", mood: "worried", ask: "my internet just dropped, can you check what's going on?", urgent: true })
      else if (kind === "headphones") root.say({ key: "headphones", vars: { device: "WH-1000XM6" }, mood: "happy", hop: true, urgent: true })
      else if (kind === "hot") root.say({ key: "hot", vars: { temp: 91 }, mood: "worried", ask: "my laptop is running hot, what's using the most CPU right now?", urgent: true })
      else if (kind === "quip") { root.lastQuipAt = 0; quipProc.start([root.askBin, "--quip"], "time " + Qt.formatTime(new Date(), "h:mm AP") + "; using " + (root.focusedApp || "the desktop")) }
      else if (kind === "theme") root.themeChanged()
      else if (kind === "pet") root.pet()
      else if (kind === "notify") { root.wake(); orb.hop(); root.setMood("curious", 1800) }
      else if (kind === "sleep") { root.sleeping = true; root.sleptAt = Date.now() - 700000 }
      else if (kind === "yawn") root.setMood("yawn", 1800)
      else return "unknown: music | battery | plug | night | notify | sleep | yawn | morning | stretch | latecoding | wifi | headphones | hot | quip | theme | pet"
      return "ok"
    }
  }

  PanelWindow {
    id: win
    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    anchors { bottom: true; right: true }
    // The window reaches the screen corner so Nyx's glow is only ever cut by
    // the screen edge; Nyx keeps its spot through the inner margins below.
    margins { bottom: 0; right: 0 }
    implicitWidth: root.cardWidth + 8 + root.edge
    implicitHeight: root.cardHeight + orb.height + 4 + root.edge
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nyx"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.chatOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Click anywhere outside Nyx and the chat closes, like Omarchy's own popups.
    HyprlandFocusGrab {
      active: root.chatOpen
      windows: [win]
      onCleared: root.close()
    }

    mask: Region { item: root.chatOpen ? fullHit : root.tucked ? noHit : (root.tip ? tipHit : orbHit) }

    Item { id: fullHit; anchors.fill: parent }
    Item { id: noHit; width: 0; height: 0 }
    Item { id: orbHit; x: orb.x + 10; y: orb.y + 10; width: orb.width - 20; height: orb.height - 20 }
    Item { id: tipHit; x: tipBubble.x; y: tipBubble.y; width: parent.width - tipBubble.x; height: parent.height - tipBubble.y }

    // ------------------------------------------------------- speech bubble
    Rectangle {
      id: tipBubble
      readonly property bool shown: root.tip !== null && !root.chatOpen
      width: Math.min(320, Math.max(tipText.implicitWidth, tipButtons.implicitWidth) + 28)
      height: tipCol.implicitHeight + 22
      anchors.right: orb.right
      anchors.rightMargin: orb.width * 0.35
      anchors.bottom: orb.top
      anchors.bottomMargin: shown ? -2 : -14
      radius: 16
      color: root.c(Commons.Color.background, 0.9)
      border.width: 1
      border.color: root.c(Commons.Color.accent, 0.45)
      opacity: shown ? 1 : 0
      visible: opacity > 0
      scale: shown ? 1 : 0.85
      transformOrigin: Item.BottomRight
      Behavior on opacity { NumberAnimation { duration: 200 } }
      Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
      Behavior on anchors.bottomMargin { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }

      // little tail pointing at Nyx
      Rectangle {
        width: 12; height: 12
        rotation: 45
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.bottom
        color: parent.color
        border.width: 1
        border.color: parent.border.color
        z: -1
      }
      Rectangle { // hides the tail's top border inside the bubble
        width: 16; height: 8
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        color: parent.color
      }

      MouseArea {
        id: tipArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tipToChat()
      }

      Column {
        id: tipCol
        x: 14; y: 11
        width: parent.width - 28
        spacing: 9

        Text {
          textFormat: Text.PlainText
          id: tipText
          width: Math.min(implicitWidth, 292)
          text: root.tip ? root.tip.text : ""
          color: Commons.Color.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          wrapMode: Text.Wrap
        }

        Row {
          id: tipButtons
          visible: root.tip !== null && (!!root.tip.command || !!root.tip.ask)
          spacing: 6
          ActionButton {
            visible: root.tipResult === ""
            label: root.tip && root.tip.actionLabel ? root.tip.actionLabel : (root.tip && root.tip.ask ? "Find out" : "Do it")
            primary: true
            onClicked: root.runTip()
          }
          ActionButton {
            visible: root.tipResult === ""
            label: "Nah"
            onClicked: root.hideTip()
          }
          Text {
            textFormat: Text.PlainText
            visible: root.tipResult !== ""
            text: root.tipResult
            color: root.c(Commons.Color.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: 12
          }
        }
      }
    }

    // ---------------------------------------------------------------- orb
    Orb {
      id: orb
      size: root.orbSize
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.edge
      anchors.bottomMargin: root.edge
      color: root.look.color
      glowScale: root.look.glow
      hat: root.occasionHat
      opacity: root.tucked ? 0 : 1
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: 400 } }
      eyeColor: Commons.Color.background
      mood: root.mood
      lookX: root.chatOpen ? -0.55 : root.lookX
      lookY: root.chatOpen ? -0.6 : root.lookY
      hovered: orbMouse.containsMouse

      MouseArea {
        id: orbMouse
        anchors.fill: parent
        anchors.margins: 10
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { orb.squish(); root.toggle() }
        onPositionChanged: mouse => root.petMove(mouse.x)
      }
    }

    // --------------------------------------------------------------- card
    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.right: parent.right
      anchors.rightMargin: 4 + root.edge
      anchors.bottom: orb.top
      anchors.bottomMargin: -6
      radius: Math.max(14, Style.cornerRadius + 4)
      color: root.c(Commons.Color.background, 0.86)
      border.width: 1
      border.color: root.c(Commons.Color.accent, 0.35)
      visible: opacity > 0
      opacity: root.chatOpen ? 1 : 0
      scale: root.chatOpen ? 1 : 0.92
      transformOrigin: Item.BottomRight
      Behavior on opacity { NumberAnimation { duration: 180 } }
      Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

      Keys.onEscapePressed: root.close()

      // header
      Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
        height: 26

        Rectangle {
          id: dot
          width: 8; height: 8; radius: 4
          anchors.verticalCenter: parent.verticalCenter
          color: root.busy ? Commons.Color.accent : "#9fd8b0"
          SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 400 }
            NumberAnimation { to: 1; duration: 400 }
          }
        }
        Text {
          textFormat: Text.PlainText
          id: title
          anchors.left: dot.right
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: "Nyx"
          color: Commons.Color.foreground
          font.family: root.fontFamily
          font.pixelSize: 14
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          anchors.left: title.right
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: root.busy ? "thinking…" : (root.brainName ? "online · " + root.brainName : "online")
          color: root.c(Commons.Color.foreground, 0.45)
          font.family: root.fontFamily
          font.pixelSize: 11
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          HeaderButton { glyph: "↺"; tip: "New chat"; onClicked: root.resetChat() }
          HeaderButton { glyph: "✕"; tip: "Close"; onClicked: root.close() }
        }
      }

      Rectangle {
        id: rule
        anchors { top: header.bottom; left: parent.left; right: parent.right; topMargin: 10; leftMargin: 14; rightMargin: 14 }
        height: 1
        color: root.c(Commons.Color.foreground, 0.08)
      }

      // messages
      ListView {
        id: list
        anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: inputBox.top; margins: 14; topMargin: 10 }
        clip: true
        spacing: 10
        model: messages
        boundsBehavior: Flickable.StopAtBounds
        onCountChanged: { root.runGuardUntil = Date.now() + 700; Qt.callLater(positionViewAtEnd) }
        delegate: Loader {
          id: row
          required property int index
          required property string who
          required property string text
          required property string command
          required property string label
          required property string status
          width: ListView.view.width
          sourceComponent: who === "action" ? actionCard : bubble
          onLoaded: item.entry = row
          onHeightChanged: { root.runGuardUntil = Date.now() + 700; Qt.callLater(list.positionViewAtEnd) }
        }
      }

      // input
      Rectangle {
        id: inputBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        height: 40
        radius: height / 2
        color: root.c(Commons.Color.foreground, 0.05)
        border.width: 1
        border.color: input.activeFocus ? root.c(Commons.Color.accent, 0.6) : root.c(Commons.Color.foreground, 0.12)
        Behavior on border.color { ColorAnimation { duration: 150 } }

        TextInput {
          id: input
          anchors { left: parent.left; right: sendBtn.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 8 }
          color: Commons.Color.foreground
          selectionColor: root.c(Commons.Color.accent, 0.4)
          font.family: root.fontFamily
          font.pixelSize: 13
          clip: true
          Keys.onReturnPressed: { root.send(text); text = "" }
          Keys.onEnterPressed: { root.send(text); text = "" }
          Keys.onEscapePressed: root.close()

          Text {
            textFormat: Text.PlainText
            visible: !input.text
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? "Nyx is thinking…" : "Ask Nyx anything…"
            color: root.c(Commons.Color.foreground, 0.35)
            font: input.font
          }
        }

        Rectangle {
          id: sendBtn
          anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 5 }
          width: 30; height: 30; radius: 15
          color: input.text && !root.busy ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.1)
          Behavior on color { ColorAnimation { duration: 150 } }
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "↑"
            font.pixelSize: 15
            font.bold: true
            color: input.text && !root.busy ? Commons.Color.background : root.c(Commons.Color.foreground, 0.4)
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.send(input.text); input.text = "" }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  component HeaderButton: Rectangle {
    id: hb
    property string glyph
    property string tip
    signal clicked()
    width: 24; height: 24; radius: 12
    color: hbMouse.containsMouse ? root.c(Commons.Color.accent, 0.18) : "transparent"
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: hb.glyph
      color: Commons.Color.foreground
      opacity: 0.75
      font.pixelSize: 12
    }
    MouseArea { id: hbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hb.clicked() }
  }

  Component {
    id: bubble
    Item {
      id: b
      property var entry
      readonly property bool mine: entry && entry.who === "you"
      implicitHeight: bubbleBg.height
      height: implicitHeight

      Rectangle {
        id: bubbleBg
        anchors.right: b.mine ? parent.right : undefined
        anchors.left: b.mine ? undefined : parent.left
        width: Math.min(b.width * 0.84, msg.implicitWidth + 24)
        height: msg.implicitHeight + 16
        radius: 14
        color: b.mine ? root.c(Commons.Color.accent, 0.22) : root.c(Commons.Color.foreground, 0.06)
        border.width: 1
        border.color: b.mine ? root.c(Commons.Color.accent, 0.3) : root.c(Commons.Color.foreground, 0.06)

        TextEdit {
          id: msg
          x: 12; y: 8
          width: Math.min(implicitWidth, b.width * 0.84 - 24)
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          text: b.entry ? b.entry.text : ""
          color: Commons.Color.foreground
          selectionColor: root.c(Commons.Color.accent, 0.4)
          font.family: root.fontFamily
          font.pixelSize: 13
          textFormat: TextEdit.PlainText
        }
      }
    }
  }

  Component {
    id: actionCard
    Rectangle {
      id: ac
      property var entry
      readonly property string st: entry ? entry.status : ""
      implicitHeight: col.implicitHeight + 24
      height: implicitHeight
      radius: 14
      color: root.c(Commons.Color.accent, 0.08)
      border.width: 1
      border.color: st === "failed" ? root.c(Commons.Color.urgent, 0.6) : root.c(Commons.Color.accent, 0.4)

      Column {
        id: col
        x: 12; y: 12
        width: parent.width - 24
        spacing: 8

        Text {
          textFormat: Text.PlainText
          width: parent.width
          // The AI's own description: small, because the command below is what runs.
          text: "⚡ " + (ac.entry ? ac.entry.label : "")
          color: root.c(Commons.Color.foreground, 0.6)
          font.family: root.fontFamily
          font.pixelSize: 11
          wrapMode: Text.Wrap
        }

        Rectangle {
          width: parent.width
          height: cmd.implicitHeight + 12
          radius: 8
          color: root.c(Commons.Color.background, 0.7)
          TextEdit {
            id: cmd
            x: 8; y: 6
            width: parent.width - 16
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            text: ac.entry ? ac.entry.command : ""
            color: Commons.Color.foreground
            font.family: root.fontFamily
            font.pixelSize: 13
            font.bold: true
            textFormat: TextEdit.PlainText
          }
        }

        Row {
          visible: ac.st === "pending"
          spacing: 8
          ActionButton { label: "Run"; primary: true; onClicked: root.runAction(ac.entry.index) }
          ActionButton { label: "Cancel"; onClicked: messages.setProperty(ac.entry.index, "status", "cancelled") }
        }

        ActionButton { visible: ac.st === "running"; label: "Stop"; onClicked: root.stopAction() }

        Text {
          textFormat: Text.PlainText
          visible: ac.st !== "pending"
          text: ac.st === "running" ? "Running…" : ac.st === "done" ? "✓ Done" : ac.st === "failed" ? "✗ Failed"
              : ac.st === "stopped" ? "■ Stopped" : "Cancelled"
          color: ac.st === "failed" ? Commons.Color.urgent : root.c(Commons.Color.foreground, 0.6)
          font.family: root.fontFamily
          font.pixelSize: 12
        }

        Text {
          textFormat: Text.PlainText
          visible: (ac.st === "done" || ac.st === "failed" || ac.st === "stopped") && ac.entry && ac.entry.text !== ""
          width: parent.width
          text: ac.entry ? ac.entry.text : ""
          color: root.c(Commons.Color.foreground, 0.55)
          font.family: root.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 6
          elide: Text.ElideRight
        }
      }
    }
  }

  component ActionButton: Rectangle {
    id: ab
    property string label
    property bool primary: false
    signal clicked()
    width: abText.implicitWidth + 28
    height: 28
    radius: 14
    color: primary ? (abMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent)
                   : (abMouse.containsMouse ? root.c(Commons.Color.foreground, 0.12) : root.c(Commons.Color.foreground, 0.06))
    Text {
      textFormat: Text.PlainText
      id: abText
      anchors.centerIn: parent
      text: ab.label
      color: ab.primary ? Commons.Color.background : Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: ab.primary
    }
    MouseArea { id: abMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
  }
}
