import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
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
  property double lastPointerMove: Date.now()
  property point lastPointer: Qt.point(-1, -1)

  function c(col, a) { return Qt.rgba(col.r, col.g, col.b, a) }

  function setMood(m, holdMs) {
    transientMood = (m === "thinking" || m === "idle") ? "" : m
    moodReset.interval = holdMs > 0 ? holdMs : 4000
    moodReset.restart()
  }

  function wake() {
    lastPointerMove = Date.now()
    if (!sleeping) return
    var sleptFor = Date.now() - sleptAt
    sleeping = false
    if (sleptFor > 600000) say({ text: "Oh! You're back 👋", mood: "happy", hop: true, cooldown: false })
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
    askProc.command = [askBin, text]
    askProc.running = true
  }

  function handleReply(raw) {
    busy = false
    var res
    try { res = JSON.parse(String(raw || "").trim().split("\n").pop()) }
    catch (e) { res = { ok: false, reply: "I couldn't understand my own brain just now 😵", mood: "worried" } }
    if (res.brain) brainName = res.brain
    messages.append({ who: "nyx", text: res.reply || "…", command: "", label: "", status: "" })
    if (res.action && res.action.command)
      messages.append({ who: "action", text: "", command: res.action.command, label: res.action.label || "Run this?", status: "pending" })
    setMood(res.mood && res.mood !== "neutral" ? res.mood : "happy", 4000)
  }

  function runAction(index) {
    if (runningIndex !== -1) return
    var item = messages.get(index)
    messages.setProperty(index, "status", "running")
    runningIndex = index
    runProc.command = ["bash", "-c", item.command + " 2>&1"]
    runProc.running = true
  }

  function finishAction(exitCode, output) {
    var index = runningIndex
    runningIndex = -1
    if (index < 0) return
    var ok = exitCode === 0
    messages.setProperty(index, "status", ok ? "done" : "failed")
    var tail = String(output || "").trim().split("\n").slice(-12).join("\n")
    messages.setProperty(index, "text", tail)
    // Let Nyx react to the result.
    ask("[ran] `" + messages.get(index).command + "` exited " + exitCode + (tail ? ". Output:\n" + tail.slice(0, 1500) : " with no output."))
  }

  function resetChat() {
    messages.clear()
    resetProc.running = true
    open()
  }

  ListModel { id: messages }

  Timer { id: moodReset; interval: 4000; onTriggered: root.transientMood = "" }
  Timer { id: focusTimer; interval: 60; onTriggered: input.forceActiveFocus() }

  Process {
    id: askProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleReply(text) }
  }

  Process {
    id: runProc
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: runProc.captured = text }
    onExited: (exitCode, exitStatus) => Qt.callLater(function() { root.finishAction(exitCode, runProc.captured) })
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
          var cx = scr.x + scr.width - root.edge - win.implicitWidth + orb.x + orb.width / 2
          var cy = scr.y + scr.height - root.edge - win.implicitHeight + orb.y + orb.height / 2
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
  // Settings: ~/.config/nyx/config.json  { "speakUp": false } silences tips.
  property var config: ({})
  readonly property bool speakUp: config.speakUp !== false
  FileView {
    path: Quickshell.env("HOME") + "/.config/nyx/config.json"
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
      root.say({ text: "Ooh, " + title + (artist ? " by " + artist : "") + " 🎶", mood: "vibing", hop: true })
    }
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
      say({ text: "Ahh, power ⚡ thank you!", mood: "happy", hop: true })
    } else {
      batteryCheck()
    }
  }
  function batteryCheck() {
    if (!discharging) return
    if (batteryPct <= 10 && batteryWarnedAt > 10) {
      batteryWarnedAt = batteryPct
      say({ text: "Battery's at " + batteryPct + "%! Plug me in pleeease 🔌", mood: "worried", hop: true, cooldown: false, hold: 20000 })
    } else if (batteryPct <= 20 && batteryWarnedAt > 20) {
      batteryWarnedAt = batteryPct
      say({ text: "Battery's at " + batteryPct + "%. Want me to switch to power saver?", mood: "worried",
            actionLabel: "Power saver", command: "powerprofilesctl set power-saver", hold: 20000 })
    }
  }

  // --- notifications (watched, never read)
  Process {
    id: notifyWatch
    command: ["setpriv", "--pdeathsig", "TERM", "dbus-monitor", "--session",
              "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("member=Notify") === -1 || root.chatOpen) return
        root.wake()
        orb.hop()
        root.setMood("curious", 1800)
      }
    }
    onExited: notifyRestart.restart()
  }
  Timer { id: notifyRestart; interval: 5000; onTriggered: notifyWatch.running = true }

  // --- time of day
  property int hour: new Date().getHours()
  readonly property bool isNight: hour >= 23 || hour < 5
  property string nightOfferedOn: ""
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.hour = new Date().getHours()
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
        if (!on) root.say({ text: "It's getting late 🌙 Want night light on?", mood: "sleepy",
                            actionLabel: "Night light", command: "omarchy toggle nightlight", hold: 20000 })
      }
    }
  }

  // ============================================================ speech tips
  // say({ text, mood, hop, actionLabel, command, hold, cooldown })
  property var tip: null
  property string tipResult: ""
  property double lastTipAt: 0

  function say(t) {
    if (!t || !t.text) return
    if (t.mood) setMood(t.mood, t.mood === "vibing" ? 3000 : 3500)
    if (t.hop) orb.hop()
    if (chatOpen || !speakUp) return
    var urgent = t.cooldown === false
    if (!urgent && Date.now() - lastTipAt < 90000) return
    lastTipAt = Date.now()
    tipResult = ""
    tip = t
    tipTimer.interval = t.hold || (t.command ? 15000 : 7000)
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
  function runTip() {
    if (!tip || !tip.command || tipProc.running) return
    tipResult = "…"
    tipProc.command = ["bash", "-c", tip.command + " 2>&1"]
    tipProc.running = true
  }
  Timer { id: tipTimer; onTriggered: if (!tipArea.containsMouse) root.hideTip(); else restart() }
  Process {
    id: tipProc
    onExited: (code, status) => {
      root.tipResult = code === 0 ? "Done ✓" : "Hmm, that failed ✗"
      root.setMood(code === 0 ? "proud" : "worried", 2500)
      tipTimer.interval = 2500
      tipTimer.restart()
    }
  }

  IpcHandler {
    target: "nyx"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function reset(): string { root.resetChat(); return "ok" }
    function ask(text: string): string { root.open(); root.send(text); return "ok" }
    function hush(): string { root.hideTip(); return "ok" }
    function say(text: string): string { root.say({ text: text, mood: "happy", hop: true, cooldown: false }); return "ok" }
    // Try reactions without waiting for them: music | battery | plug | night | notify | sleep | yawn
    function demo(kind: string): string {
      if (kind === "music") root.say({ text: "Ooh, Midnight City by M83 🎶", mood: "vibing", hop: true, cooldown: false })
      else if (kind === "battery") root.say({ text: "Battery's at 18%. Want me to switch to power saver?", mood: "worried", actionLabel: "Power saver", command: "powerprofilesctl set power-saver", cooldown: false, hold: 20000 })
      else if (kind === "plug") root.say({ text: "Ahh, power ⚡ thank you!", mood: "happy", hop: true, cooldown: false })
      else if (kind === "night") root.say({ text: "It's getting late 🌙 Want night light on?", mood: "sleepy", actionLabel: "Night light", command: "omarchy toggle nightlight", cooldown: false, hold: 20000 })
      else if (kind === "notify") { orb.hop(); root.setMood("curious", 1800) }
      else if (kind === "sleep") { root.sleeping = true; root.sleptAt = Date.now() - 700000 }
      else if (kind === "yawn") root.setMood("yawn", 1800)
      else return "unknown: music | battery | plug | night | notify | sleep | yawn"
      return "ok"
    }
  }

  PanelWindow {
    id: win
    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    anchors { bottom: true; right: true }
    margins { bottom: root.edge; right: root.edge }
    implicitWidth: root.cardWidth + 8
    implicitHeight: root.cardHeight + orb.height + 4
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

    mask: Region { item: root.chatOpen ? fullHit : (root.tip ? tipHit : orbHit) }

    Item { id: fullHit; anchors.fill: parent }
    Item { id: orbHit; x: orb.x + 10; y: orb.y + 10; width: orb.width - 20; height: orb.height - 20 }
    Item { id: tipHit; x: tipBubble.x; y: tipBubble.y; width: parent.width - tipBubble.x; height: parent.height - tipBubble.y }

    // ------------------------------------------------------- speech bubble
    Rectangle {
      id: tipBubble
      readonly property bool shown: root.tip !== null && !root.chatOpen
      width: Math.min(270, Math.max(tipText.implicitWidth, tipButtons.implicitWidth) + 28)
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
          id: tipText
          width: Math.min(implicitWidth, 242)
          text: root.tip ? root.tip.text : ""
          color: Commons.Color.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          wrapMode: Text.Wrap
        }

        Row {
          id: tipButtons
          visible: root.tip !== null && !!root.tip.command
          spacing: 6
          ActionButton {
            visible: root.tipResult === ""
            label: root.tip && root.tip.actionLabel ? root.tip.actionLabel : "Do it"
            primary: true
            onClicked: root.runTip()
          }
          ActionButton {
            visible: root.tipResult === ""
            label: "Nah"
            onClicked: root.hideTip()
          }
          Text {
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
      color: Commons.Color.accent
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
      }
    }

    // --------------------------------------------------------------- card
    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.right: parent.right
      anchors.rightMargin: 4
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
        onCountChanged: Qt.callLater(positionViewAtEnd)
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
          onHeightChanged: Qt.callLater(list.positionViewAtEnd)
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
          width: parent.width
          text: "⚡ " + (ac.entry ? ac.entry.label : "")
          color: Commons.Color.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
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
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: 12
            textFormat: TextEdit.PlainText
          }
        }

        Row {
          visible: ac.st === "pending"
          spacing: 8
          ActionButton { label: "Run"; primary: true; onClicked: root.runAction(ac.entry.index) }
          ActionButton { label: "Cancel"; onClicked: messages.setProperty(ac.entry.index, "status", "cancelled") }
        }

        Text {
          visible: ac.st !== "pending"
          text: ac.st === "running" ? "Running…" : ac.st === "done" ? "✓ Done" : ac.st === "failed" ? "✗ Failed" : "Cancelled"
          color: ac.st === "failed" ? Commons.Color.urgent : root.c(Commons.Color.foreground, 0.6)
          font.family: root.fontFamily
          font.pixelSize: 12
        }

        Text {
          visible: (ac.st === "done" || ac.st === "failed") && ac.entry && ac.entry.text !== ""
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
