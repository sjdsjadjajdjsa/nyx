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
  // One size system for every control, so rows always line up.
  readonly property int pillH: 28       // chips, buttons, header icon buttons
  readonly property int fieldH: 32      // text fields
  readonly property int pad: 14         // card padding

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
    if (messages.count === 0) {
      messages.append({ who: "nyx", text: "Hey, I'm Nyx ✨ Ask me anything about your machine, or tell me what to change.", command: "", label: "", status: "" })
      if (!setupChecked) { setupChecked = true; setupProc.running = true }
    }
    focusTimer.restart()
  }
  function close() { chatOpen = false; settingsOpen = false }
  function toggle() { chatOpen ? close() : open() }

  // Example questions shown in a fresh chat; tap one to ask it.
  readonly property var examplePool: [
    "What's using my memory?", "How's my battery?", "Change my theme", "Show my keyboard shortcuts",
    "Remind me in 20 minutes to take a break", "Make my window gaps smaller", "Is anything broken on my system?",
    "What's taking up disk space?", "Take a screenshot", "Turn on night light"
  ]
  property var examples: []
  property bool userSpoke: false
  function pickExamples() {
    var pool = examplePool.slice()
    for (var i = pool.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1)); var t = pool[i]; pool[i] = pool[j]; pool[j] = t
    }
    examples = pool.slice(0, 4)
  }
  Component.onCompleted: pickExamples()

  // Returns true when the text was taken (so the input can be cleared), false when it was kept back.
  function send(text) {
    text = String(text || "").trim()
    if (!text || busy) return false
    userSpoke = true
    messages.append({ who: "you", text: text, command: "", label: "", status: "" })
    ask(text)
    return true
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
    userSpoke = false
    pickExamples()
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
    // Keep only the last ~16 KB of output so a chatty command can't fill the shell's memory.
    property string output: ""
    property bool stopped: false
    // Keeps the END of the output (that is what goes back to the AI); one huge line is cut to its end too.
    function take(line) {
      var s = output + (line.length > 16000 ? line.slice(-16000) : line) + "\n"
      output = s.length > 16000 ? s.slice(-16000) : s
    }
    stdout: SplitParser { onRead: line => runProc.take(line) }
    stderr: SplitParser { onRead: line => runProc.take(line) }
    onExited: (exitCode, exitStatus) => Qt.callLater(function() { root.finishAction(exitCode, runProc.output) })
  }

  Process { id: resetProc; command: [root.askBin, "--reset"] }

  // ⚙ Settings page: reads and saves through nyx-ask (--settings / --save-settings),
  // so this file never writes anything itself and the API key goes on stdin.
  property bool settingsOpen: false
  property var st: ({})            // what nyx-ask --settings reported
  property var draft: ({})         // the choices on the page, saved with Save
  property bool removeKey: false
  property string settingsMsg: ""
  property bool settingsOk: true
  readonly property string effectiveBrain: draft.brain || st.auto || ""
  function openSettings() {
    settingsOpen = true
    settingsMsg = ""
    removeKey = false
    settingsProc.running = true
  }
  function closeSettings() { settingsOpen = false; pickerOpen = false; focusTimer.restart() }

  // Model picker: the chosen API's models, searchable, best ones first.
  property bool pickerOpen: false
  property var pickerModels: []
  property string pickerMsg: ""
  property string pickerQuery: ""
  readonly property var pickerShown: {
    var words = pickerQuery.toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
    return pickerModels.filter(function(m) {
      var hay = (m.id + " " + m.name + (m["in"] === 0 && m.out === 0 ? " free" : "")).toLowerCase()
      return words.every(function(w) { return hay.indexOf(w) !== -1 })
    })
  }
  function openPicker() {
    pickerOpen = true
    pickerModels = []
    pickerQuery = ""
    pickSearch.text = ""
    pickerMsg = "Loading models…"
    modelsProc.start([askBin, "--models"], JSON.stringify({ apiUrl: urlField.text.trim(), apiKey: keyField.text.trim() }))
  }
  function pickModel(m) {
    modelField.text = m.id
    pickerOpen = false
    settingsOk = true
    settingsMsg = "Picked " + m.name + ". Save to use it."
  }
  function price(m) {
    if (m["in"] === null || m["in"] === undefined) return ""
    if (m["in"] === 0 && m.out === 0) return "free"
    return "$" + m["in"].toFixed(2) + " in · $" + m.out.toFixed(2) + " out per M tokens"
  }
  StdinProcess {
    id: modelsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r
        try { r = JSON.parse(String(text || "").trim().split("\n").pop()) } catch (e) { r = { ok: false, error: "Couldn't read the model list." } }
        if (!r.ok) { root.pickerMsg = r.error || "Couldn't load models."; return }
        root.pickerModels = r.models || []
        root.pickerMsg = r.models.length === 0 ? "No models found."
          : r.toolsKnown ? r.models.length + " models that can drive Nyx (ones without tool support are hidden)"
          : r.models.length + " models. Pick one that supports tool calling."
      }
    }
  }
  function setDraft(k, v) { var d = Object.assign({}, draft); d[k] = v; draft = d }
  function loadSettings(raw) {
    try { st = JSON.parse(String(raw || "").trim().split("\n").pop()) } catch (e) { st = {}; return }
    var c = st.config || {}
    draft = { brain: c.brain || "", chattiness: c.chattiness || "normal",
              beatGlow: c.beatGlow !== false, timeOfDay: c.timeOfDay !== false,
              seasonal: c.seasonal !== false, hideInFullscreen: c.hideInFullscreen !== false }
    modelField.text = c.model || ""
    urlField.text = c.apiUrl || ""
    keyField.text = ""
    bdayField.text = c.birthday || ""
  }
  function saveSettings() {
    var d = Object.assign({}, draft)
    d.model = modelField.text.trim()
    d.apiUrl = urlField.text.trim()
    d.birthday = bdayField.text.trim()
    settingsMsg = "Saving…"
    settingsOk = true
    saveProc.start([askBin, "--save-settings"],
                   JSON.stringify({ config: d, apiKey: keyField.text.trim(), removeKey: removeKey }))
  }
  Process {
    id: settingsProc
    command: [root.askBin, "--settings"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadSettings(text) }
  }
  StdinProcess {
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r
        try { r = JSON.parse(String(text || "").trim().split("\n").pop()) } catch (e) { r = { ok: false, error: "Couldn't save." } }
        root.settingsOk = r.ok === true
        root.settingsMsg = r.ok ? "Saved ✓" : (r.error || "Couldn't save.")
        if (r.ok) {
          if (r.brain) root.brainName = r.brain
          settingsProc.running = true   // show what's stored now (e.g. "a key is saved")
        }
      }
    }
  }

  // First open: which brain is there, and (only once ever) an offer to add a
  // keyboard shortcut, as a normal Run card showing the exact command.
  property bool setupChecked: false
  Process {
    id: setupProc
    command: [root.askBin, "--setup"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleSetup(text) }
  }
  function handleSetup(raw) {
    var s
    try { s = JSON.parse(String(raw || "").trim().split("\n").pop()) } catch (e) { return }
    if (s.brain) brainName = s.brain
    if (!s.ready && s.message)
      messages.append({ who: "nyx", text: s.message, command: "", label: "", status: "" })
    if (s.shortcut && s.shortcut.command && plainCommand(s.shortcut.command)) {
      messages.append({ who: "nyx", text: "One more thing: want a keyboard shortcut to open me?", command: "", label: "", status: "" })
      messages.append({ who: "action", text: "", command: s.shortcut.command, label: s.shortcut.label || "Add a shortcut", status: "pending" })
    }
  }

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
      var spec = { key: "battery20", vars: { pct: batteryPct }, mood: "worried",
                  actionLabel: "Power saver", command: "powerprofilesctl set power-saver", hold: 20000 }
      // Only count it as warned once the bubble can actually show; the next change retries.
      if (!tipBlocked(spec)) { batteryWarnedAt = batteryPct; say(spec) }
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

  // --- rare easter eggs: ~1% chance every 20 minutes of active use
  Timer {
    interval: 20 * 60000
    running: root.speakUp
    repeat: true
    onTriggered: {
      if (root.tucked || root.sleeping || root.chatOpen || root.busy) return
      if (Date.now() - root.lastActive > 5 * 60000) return
      if (Math.random() < 0.01) root.say({ key: "rare", mood: "happy", hop: true })
    }
  }

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
        var spec = { key: "night", mood: "sleepy",
                    actionLabel: "Night light", command: "omarchy toggle nightlight", hold: 20000 }
        if (!on) {
          // Not shown (chat open, hidden, too soon after another bubble): offer again next minute.
          if (root.tipBlocked(spec)) root.nightOfferedOn = ""
          else root.say(spec)
        }
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
      var spec = { key: "morning", mood: "happy", hop: true }
      if (!tipBlocked(spec)) { greetedOn = today; say(spec) }
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
        var spec = { key: "lateCoding", vars: { time: Qt.formatTime(new Date(), "h:mm"), app: root.focusedApp.split(".").pop() },
                    mood: "sleepy", actionLabel: "Remind me", ask: "remind me to go to bed in 30 minutes" }
        if (!root.tipBlocked(spec)) { root.lateCodingOn = night; say(spec) }
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

  // True when say() would not show this bubble right now.
  function tipBlocked(t) {
    if (chatOpen || tucked) return true  // never pop up over fullscreen or a screen share
    if (t.urgent === true || t.cooldown === false) return false
    if (!speakUp) return true
    if (Date.now() - lastTipAt < (chatty ? 45000 : 120000)) return true
    return !!(t.key && t.every > 0 && Date.now() - (lastSaid[t.key] || 0) < t.every * 60000)
  }

  function say(t) {
    if (!t) return
    var text = t.text || (t.key ? Lines.pick(t.key, t.vars) : "")
    if (!text) return
    if (t.mood) setMood(t.mood, t.mood === "vibing" ? 3000 : 3500)
    if (t.hop) orb.hop()
    if (tipBlocked(t)) return
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
    function settings(): string { root.open(); root.openSettings(); return "ok" }
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
      else if (kind === "rare") root.say({ key: "rare", mood: "happy", hop: true, urgent: true })
      else if (kind === "notify") { root.wake(); orb.hop(); root.setMood("curious", 1800) }
      else if (kind === "sleep") { root.sleeping = true; root.sleptAt = Date.now() - 700000 }
      else if (kind === "yawn") root.setMood("yawn", 1800)
      else return "unknown: music | battery | plug | night | notify | sleep | yawn | morning | stretch | latecoding | wifi | headphones | hot | quip | theme | pet | rare"
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
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: root.pad; topMargin: 12 }
        height: root.pillH

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
          text: root.settingsOpen ? "Settings" : "Nyx"
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
          visible: !root.settingsOpen
          text: root.busy ? "thinking…" : (root.brainName ? "online · " + root.brainName : "online")
          color: root.c(Commons.Color.foreground, 0.45)
          font.family: root.fontFamily
          font.pixelSize: 11
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          HeaderButton { icon: "newchat"; visible: !root.settingsOpen; onClicked: root.resetChat() }
          HeaderButton { icon: "gear"; active: root.settingsOpen
                         onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings() }
          HeaderButton { icon: "close"; onClicked: root.close() }
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
        visible: !root.settingsOpen
        anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: exampleChips.visible ? exampleChips.top : inputBox.top; margins: 14; topMargin: 10 }
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

      // example questions (fresh chat only)
      Flow {
        id: exampleChips
        visible: !root.settingsOpen && !root.userSpoke && !root.busy && root.examples.length > 0
        anchors { left: parent.left; right: parent.right; bottom: inputBox.top; leftMargin: 14; rightMargin: 14; bottomMargin: 8 }
        spacing: 6
        Repeater {
          model: root.examples
          Chip {
            required property string modelData
            label: modelData
            onClicked: root.send(modelData)
          }
        }
      }

      // input
      Rectangle {
        id: inputBox
        visible: !root.settingsOpen
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
          Keys.onReturnPressed: { if (root.send(text)) text = "" }
          Keys.onEnterPressed: { if (root.send(text)) text = "" }
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
          readonly property bool ready: input.text !== "" && !root.busy
          width: 30; height: 30; radius: 15
          color: ready ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.08)
          Behavior on color { ColorAnimation { duration: 150 } }
          scale: sendMouse.pressed && ready ? 0.9 : 1
          Behavior on scale { NumberAnimation { duration: 90 } }
          Icon {
            anchors.centerIn: parent
            name: "up"
            size: 16
            stroke: 2.4
            color: sendBtn.ready ? Commons.Color.background : root.c(Commons.Color.foreground, 0.35)
          }
          MouseArea {
            id: sendMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (root.send(input.text)) input.text = "" }
          }
        }
      }

      // ⚙ settings page
      Flickable {
        id: settingsView
        visible: root.settingsOpen && !root.pickerOpen
        anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: settingsFooter.top; leftMargin: root.pad; rightMargin: root.pad; topMargin: 4 }
        clip: true
        contentHeight: settingsCol.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: settingsCol
          width: settingsView.width
          spacing: 8

          SettingLabel { text: "BRAIN" }
          Flow {
            width: parent.width
            spacing: 6
            Chip { label: "Auto"; on: root.draft.brain === ""; onClicked: root.setDraft("brain", "") }
            Chip { label: "Claude Code"; on: root.draft.brain === "claude"; dim: !(root.st.installed || {}).claude
                   onClicked: root.setDraft("brain", "claude") }
            Chip { label: "Codex"; on: root.draft.brain === "codex"; dim: !(root.st.installed || {}).codex
                   onClicked: root.setDraft("brain", "codex") }
            Chip { label: "API key"; on: root.draft.brain === "api"; onClicked: root.setDraft("brain", "api") }
          }
          SettingHint {
            text: {
              var inst = root.st.installed || {}
              var names = { claude: "Claude Code", codex: "Codex", api: "an API key" }
              if (root.draft.brain === "") return root.st.auto ? "Uses " + names[root.st.auto] + ", the first one I found." : "Nothing found yet: install Claude Code or Codex, or use an API key."
              if (root.draft.brain === "claude" && !inst.claude) return "Claude Code isn't installed yet."
              if (root.draft.brain === "codex" && !inst.codex) return "Codex isn't installed yet. Run `codex login` after installing."
              if (root.draft.brain === "api") return "Any OpenAI-compatible service. Pick it below."
              return ""
            }
            visible: text !== ""
          }

          SettingLabel { text: "MODEL" }
          Field {
            id: modelField
            placeholder: "default: " + (((root.st.defaults || {})[root.effectiveBrain]) || "pick one")
          }
          Flow {
            width: parent.width
            spacing: 6
            visible: modelPicks.count > 0
            Repeater {
              id: modelPicks
              model: root.effectiveBrain === "claude" ? ["sonnet", "haiku", "opus"]
                : root.effectiveBrain === "codex" ? ["gpt-6.1-terra", "gpt-6-luna"]
                : root.effectiveBrain === "api" && (urlField.text === "" || urlField.text.indexOf("openrouter.ai") !== -1)
                  ? ["anthropic/claude-haiku-5.5", "deepseek/deepseek-v4-flash", "z-ai/glm-5.3-flash"] : []
              Chip {
                required property string modelData
                label: modelData.split("/").pop()
                on: modelField.text === modelData || (modelField.text === "" && ((root.st.defaults || {})[root.effectiveBrain]) === modelData)
                onClicked: modelField.text = modelData
              }
            }
          }

          ActionButton {
            visible: root.effectiveBrain === "api"
            icon: "list"
            label: "Browse all models"
            onClicked: root.openPicker()
          }

          Column {
            width: parent.width
            spacing: 8
            visible: root.effectiveBrain === "api"
            SettingLabel { text: "PROVIDER" }
            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: root.st.providers || []
                Chip {
                  required property var modelData
                  label: modelData.name
                  on: urlField.text === modelData.url || (urlField.text === "" && modelData.name === "OpenRouter")
                  onClicked: urlField.text = modelData.name === "OpenRouter" ? "" : modelData.url
                }
              }
            }
            Field { id: urlField; placeholder: "https://openrouter.ai/api/v1" }
            SettingLabel { text: "API KEY" }
            SettingHint {
              text: root.removeKey ? "The saved key will be deleted when you save."
                : root.st.keyFromEnv ? "Using the key from $NYX_API_KEY."
                : root.st.hasKey ? "A key is saved ✓ (stored only for you, never shown again)"
                : urlField.text.indexOf("localhost") !== -1 ? "Local servers usually don't need a key."
                : "No key saved yet."
            }
            Field { id: keyField; secret: true; placeholder: root.st.hasKey ? "Paste a new key to replace it" : "Paste your key" }
            ActionButton {
              visible: root.st.hasKey === true && root.st.keyFromEnv !== true && !root.removeKey
              label: "Remove saved key"
              onClicked: root.removeKey = true
            }
          }

          SettingLabel { text: "CHATTINESS" }
          Flow {
            width: parent.width
            spacing: 6
            Chip { label: "Quiet"; on: root.draft.chattiness === "quiet"; onClicked: root.setDraft("chattiness", "quiet") }
            Chip { label: "Normal"; on: root.draft.chattiness === "normal"; onClicked: root.setDraft("chattiness", "normal") }
            Chip { label: "Chatty"; on: root.draft.chattiness === "chatty"; onClicked: root.setDraft("chattiness", "chatty") }
          }

          SettingLabel { text: "EXTRAS" }
          Toggle { label: "Glow to the beat"; on: root.draft.beatGlow === true; onToggled: v => root.setDraft("beatGlow", v) }
          Toggle { label: "Colors follow the time of day"; on: root.draft.timeOfDay === true; onToggled: v => root.setDraft("timeOfDay", v) }
          Toggle { label: "Hats & special days"; on: root.draft.seasonal === true; onToggled: v => root.setDraft("seasonal", v) }
          Toggle { label: "Hide in fullscreen & screen sharing"; on: root.draft.hideInFullscreen === true; onToggled: v => root.setDraft("hideInFullscreen", v) }

          SettingLabel { text: "BIRTHDAY" }
          Field { id: bdayField; placeholder: "month-day, like 07-24 (optional)" }
        }
      }

      // soft fade where the settings list scrolls under the footer
      Rectangle {
        visible: settingsView.visible && !settingsView.atYEnd
        anchors { left: parent.left; right: parent.right; bottom: settingsFooter.top; leftMargin: 1; rightMargin: 1 }
        height: 22
        gradient: Gradient {
          GradientStop { position: 0; color: root.c(Commons.Color.background, 0) }
          GradientStop { position: 1; color: root.c(Commons.Color.background, 0.86) }
        }
      }

      // Save / Back stay put at the bottom of settings and the model picker.
      Item {
        id: settingsFooter
        visible: root.settingsOpen
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: root.pad; rightMargin: root.pad; bottomMargin: 12 }
        height: root.pillH + 13

        Rectangle {
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: 1
          color: root.c(Commons.Color.foreground, 0.08)
        }
        Row {
          id: footerButtons
          anchors { left: parent.left; bottom: parent.bottom }
          spacing: 8
          ActionButton { visible: !root.pickerOpen; label: "Save"; primary: true; onClicked: root.saveSettings() }
          ActionButton { icon: "back"; label: "Back"; onClicked: root.pickerOpen ? root.pickerOpen = false : root.closeSettings() }
        }
        Text {
          textFormat: Text.PlainText
          anchors { left: footerButtons.right; right: parent.right; leftMargin: 12; verticalCenter: footerButtons.verticalCenter }
          visible: root.settingsMsg !== "" && !root.pickerOpen
          text: root.settingsMsg
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
          color: root.settingsOk ? root.c(Commons.Color.foreground, 0.6) : Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }

      // model picker (from ⚙ → Browse all models…)
      Item {
        id: pickerView
        visible: root.settingsOpen && root.pickerOpen
        anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: settingsFooter.top; leftMargin: root.pad; rightMargin: root.pad; topMargin: 12; bottomMargin: 10 }
        Field {
          id: pickSearch
          anchors { top: parent.top; left: parent.left; right: parent.right }
          width: parent.width
          icon: "search"
          placeholder: "Search: haiku, deepseek, free…"
          onTextChanged: root.pickerQuery = text
        }
        Text {
          id: pickInfo
          textFormat: Text.PlainText
          anchors { top: pickSearch.bottom; left: parent.left; right: parent.right; topMargin: 6 }
          wrapMode: Text.Wrap
          text: root.pickerQuery !== "" && root.pickerModels.length > 0 ? root.pickerShown.length + " matching" : root.pickerMsg
          color: root.c(Commons.Color.foreground, 0.45)
          font.family: root.fontFamily
          font.pixelSize: 11
        }
        ListView {
          id: pickList
          anchors { top: pickInfo.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 8 }
          clip: true
          spacing: 4
          boundsBehavior: Flickable.StopAtBounds
          model: root.pickerShown
          delegate: Rectangle {
            id: pm
            required property var modelData
            width: ListView.view.width
            height: pmCol.implicitHeight + 12
            radius: 9
            readonly property bool chosen: modelField.text === modelData.id
            color: chosen ? root.c(Commons.Color.accent, 0.22) : pmMouse.containsMouse ? root.c(Commons.Color.foreground, 0.08) : root.c(Commons.Color.foreground, 0.03)
            Column {
              id: pmCol
              x: 10; y: 6
              width: parent.width - 20
              spacing: 1
              Row {
                width: parent.width
                spacing: 6
                Icon {
                  visible: !!pm.modelData.star
                  anchors.verticalCenter: parent.verticalCenter
                  name: "star"
                  filled: true
                  size: 12
                  color: Commons.Color.accent
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width - (pm.modelData.star ? 18 : 0)
                  elide: Text.ElideRight
                  text: pm.modelData.name
                  color: Commons.Color.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.bold: true
                }
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: [pm.modelData.star, root.price(pm.modelData)].filter(function(x) { return x }).join(" · ")
                color: pm.modelData.star ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.5)
                font.family: root.fontFamily
                font.pixelSize: 10
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideMiddle
                text: pm.modelData.id
                color: root.c(Commons.Color.foreground, 0.35)
                font.family: root.fontFamily
                font.pixelSize: 10
              }
            }
            MouseArea { id: pmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickModel(pm.modelData) }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  component SettingLabel: Text {
    textFormat: Text.PlainText
    color: root.c(Commons.Color.foreground, 0.5)
    font.family: root.fontFamily
    font.pixelSize: 11
    font.bold: true
    topPadding: 6
  }
  component SettingHint: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 300
    wrapMode: Text.Wrap
    color: root.c(Commons.Color.foreground, 0.45)
    font.family: root.fontFamily
    font.pixelSize: 11
  }
  // A pill button; `on` shows it as chosen. Sized for its bold label so
  // choosing it never shifts the row.
  component Chip: Rectangle {
    id: chip
    property string label
    property bool on: false
    property bool dim: false
    signal clicked()
    width: Math.ceil(chipBold.advanceWidth) + 24
    height: root.pillH
    radius: height / 2
    color: on ? Commons.Color.accent : (chipMouse.containsMouse ? root.c(Commons.Color.foreground, 0.12) : root.c(Commons.Color.foreground, 0.06))
    Behavior on color { ColorAnimation { duration: 120 } }
    border.width: 1
    border.color: on ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.1)
    scale: chipMouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    TextMetrics { id: chipBold; text: chip.label; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
    Text {
      id: chipText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: chip.label
      color: chip.on ? Commons.Color.background : Commons.Color.foreground
      opacity: chip.dim && !chip.on ? 0.45 : 1
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: chip.on
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }
  // A labelled on/off switch.
  component Toggle: Item {
    id: tg
    property string label
    property bool on: true
    signal toggled(bool value)
    width: parent ? parent.width : 300
    height: root.pillH
    Text {
      textFormat: Text.PlainText
      anchors { left: parent.left; right: sw.left; verticalCenter: parent.verticalCenter; rightMargin: 8 }
      text: tg.label
      elide: Text.ElideRight
      color: Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: 12
    }
    Rectangle {
      id: sw
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      width: 36; height: 20; radius: 10
      color: tg.on ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.15)
      Behavior on color { ColorAnimation { duration: 150 } }
      Rectangle {
        width: 16; height: 16; radius: 8
        y: 2
        x: tg.on ? parent.width - width - 2 : 2
        color: tg.on ? Commons.Color.background : Commons.Color.foreground
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.on) }
  }
  // A one-line text box.
  component Field: Rectangle {
    id: fld
    property alias text: fldInput.text
    property string placeholder
    property string icon
    property bool secret: false
    width: parent ? parent.width : 300
    height: root.fieldH
    radius: 10
    color: root.c(Commons.Color.foreground, 0.05)
    border.width: 1
    border.color: fldInput.activeFocus ? root.c(Commons.Color.accent, 0.6) : root.c(Commons.Color.foreground, 0.12)
    Behavior on border.color { ColorAnimation { duration: 150 } }
    Icon {
      id: fldIcon
      visible: fld.icon !== ""
      anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
      name: fld.icon
      size: 14
      color: root.c(Commons.Color.foreground, 0.4)
    }
    TextInput {
      id: fldInput
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: fld.icon !== "" ? 33 : 12; rightMargin: 12 }
      color: Commons.Color.foreground
      selectionColor: root.c(Commons.Color.accent, 0.4)
      font.family: root.fontFamily
      font.pixelSize: 12
      clip: true
      echoMode: fld.secret ? TextInput.Password : TextInput.Normal
      Keys.onReturnPressed: root.saveSettings()
      Keys.onEscapePressed: root.closeSettings()
      Text {
        textFormat: Text.PlainText
        visible: !fldInput.text
        anchors.verticalCenter: parent.verticalCenter
        text: fld.placeholder
        color: root.c(Commons.Color.foreground, 0.32)
        font: fldInput.font
      }
    }
  }

  // A round icon button for the card header; all share one size and icon box.
  component HeaderButton: Rectangle {
    id: hb
    property string icon
    property bool active: false
    signal clicked()
    width: root.pillH; height: root.pillH; radius: height / 2
    color: active ? root.c(Commons.Color.accent, 0.22)
         : hbMouse.containsMouse ? root.c(Commons.Color.foreground, 0.1) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: hbMouse.pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    Icon {
      anchors.centerIn: parent
      name: hb.icon
      size: 16
      color: hb.active ? Commons.Color.accent : root.c(Commons.Color.foreground, hbMouse.containsMouse ? 0.95 : 0.65)
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

        Row {
          width: parent.width
          spacing: 6
          Icon {
            name: "bolt"
            size: 13
            y: 1
            color: Commons.Color.accent
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - 19
            // The AI's own description: small, because the command below is what runs.
            text: ac.entry ? ac.entry.label : ""
            color: root.c(Commons.Color.foreground, 0.6)
            font.family: root.fontFamily
            font.pixelSize: 11
            wrapMode: Text.Wrap
          }
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

  // A pill action button, same height as Chip; optional leading icon.
  component ActionButton: Rectangle {
    id: ab
    property string label
    property string icon
    property bool primary: false
    signal clicked()
    width: abRow.implicitWidth + 28
    height: root.pillH
    radius: height / 2
    color: primary ? (abMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent)
                   : (abMouse.containsMouse ? root.c(Commons.Color.foreground, 0.12) : root.c(Commons.Color.foreground, 0.06))
    Behavior on color { ColorAnimation { duration: 120 } }
    border.width: 1
    border.color: primary ? Commons.Color.accent : root.c(Commons.Color.foreground, 0.1)
    scale: abMouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    Row {
      id: abRow
      anchors.centerIn: parent
      spacing: 6
      Icon {
        visible: ab.icon !== ""
        anchors.verticalCenter: parent.verticalCenter
        name: ab.icon
        size: 14
        color: abText.color
      }
      Text {
        textFormat: Text.PlainText
        id: abText
        anchors.verticalCenter: parent.verticalCenter
        text: ab.label
        color: ab.primary ? Commons.Color.background : Commons.Color.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: ab.primary
      }
    }
    MouseArea { id: abMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
  }
}
