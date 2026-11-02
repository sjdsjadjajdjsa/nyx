import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Particles

// Nyx's body: a glowing orb with expressive eyes.
// mood: idle | thinking | happy | proud | curious | worried | sleepy | yawn | vibing | neutral
Item {
  id: orb

  property color color: "#e8a2c8"
  property color eyeColor: "#13111c"
  property real glowScale: 1.0      // time of day: dimmer glow at night (set by Nyx.qml)
  Behavior on color { ColorAnimation { duration: 1500 } }
  Behavior on glowScale { NumberAnimation { duration: 1500 } }
  property string mood: "idle"
  property real lookX: 0   // -1 .. 1
  property real lookY: 0   // -1 .. 1
  property bool hovered: false
  property real size: 58

  readonly property bool joyful: mood === "happy" || mood === "proud" || mood === "vibing"
  readonly property bool asleep: mood === "sleepy" || mood === "yawn"
  readonly property bool vibing: mood === "vibing"
  readonly property bool thinking: mood === "thinking"

  implicitWidth: size * 1.6
  implicitHeight: size * 1.6

  // Audio loudness 0..1 while music plays (fed by Nyx.qml from bin/nyx-beat).
  property real audioLevel: 0
  property real level: 0          // smoothed audioLevel
  property real kick: 0           // short punch on each beat, decays
  property real wobble: 0         // jelly energy, decays
  property real t: 0              // animation clock (seconds)

  function squish() { squishAnim.restart(); splash(0.9) }
  function hop() { hopAnim.restart(); splash(0.6); sparkle(10) }
  function splash(strength) { wobble = Math.min(1.4, wobble + strength) }
  function sparkle(n) {
    sparkleHold.restart()                       // wake the particle system
    Qt.callLater(function() { sparkles.burst(n) })
  }
  function beat() {
    kick = 1
    splash(0.35)
    sparkle(4)
  }

  // ---- the clock -----------------------------------------------------------
  // All of Nyx's continuous motion (bob, breath, glow pulse, sway, liquid
  // edge) is computed here from one clock instead of free-running animations.
  // Free-running animations redraw at the screen's refresh rate (144 Hz on
  // some laptops) forever; this clock ticks 25 times a second while Nyx idles
  // and 60 while it's actually moving, which keeps it light on the battery.
  readonly property bool lively: wobble > 0.01 || kick > 0.01 || level > 0.01 || audioLevel > 0.01
    || hovered || vibing || thinking || hopAnim.running || squishAnim.running
  property double lastTick: Date.now()
  Timer {
    id: clock
    interval: orb.lively ? 16 : 40
    running: orb.visible
    repeat: true
    onTriggered: {
      var now = Date.now()
      var dt = Math.min((now - orb.lastTick) / 1000, 0.1)
      orb.lastTick = now
      var t = (orb.t += dt)
      orb.level += (orb.audioLevel - orb.level) * Math.min(1, dt * 14)
      orb.kick *= Math.pow(0.02, dt)      // ~gone in 0.6 s
      orb.wobble *= Math.pow(0.08, dt)    // ~gone in 1 s
      if (orb.level < 0.002) orb.level = 0
      if (orb.kick < 0.002) orb.kick = 0
      if (orb.wobble < 0.002) orb.wobble = 0

      var TAU = Math.PI * 2
      body.bob = orb.asleep ? 0
        : orb.vibing ? -2.5 + 3.5 * Math.sin(TAU * t / 0.6)
        : -1 + 3 * Math.sin(TAU * t / 2.8)
      body.sway = orb.vibing ? 9 * Math.sin(TAU * t / 1.2) : 0
      body.breath = orb.asleep ? 0.97 + 0.03 * Math.sin(TAU * t / 4.4)
        : 1.0125 + 0.0125 * Math.sin(TAU * t / 3.2)
      glow.scale = orb.thinking ? 1.07 + 0.11 * Math.sin(TAU * t / 1.0)
        : 1.01 + 0.05 * Math.sin(TAU * t / 3.6)
      blob.update()
    }
  }

  // ---- ambient light: a wide, faint, slightly violet halo -----------------
  // Makes Nyx look like it lights up the desktop rather than sits on it.
  Rectangle {
    id: halo
    anchors.centerIn: body
    width: orb.size * 2.5
    height: width
    radius: width / 2
    color: Qt.hsla((orb.color.hslHue + 0.94) % 1, Math.min(1, orb.color.hslSaturation * 1.1), orb.color.hslLightness, 1)
    opacity: orb.asleep ? 0.10 : Math.min(0.42, 0.18 + orb.level * 0.14 + orb.kick * 0.1)
    scale: 1 + orb.level * 0.12
    Behavior on opacity { NumberAnimation { duration: 500 } }
    layer.enabled: true
    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; autoPaddingEnabled: true }
  }

  // ---- glow (breathes, and pumps with the music) ------------------------
  Item {
    id: glowPump
    anchors.centerIn: body
    width: glow.width
    height: glow.height
    scale: 1 + orb.level * 0.28 + orb.kick * 0.22
    opacity: Math.min(1, 1 + orb.kick * 0.6)
  Rectangle {
    id: glow
    anchors.centerIn: parent
    width: orb.size * 1.35
    height: width
    radius: width / 2
    color: orb.color
    opacity: Math.min(0.95, ((orb.thinking ? 0.75 : (orb.hovered ? 0.6 : 0.42)) + orb.level * 0.25 + orb.kick * 0.25) * orb.glowScale)
    Behavior on opacity { NumberAnimation { duration: 300 } }
    layer.enabled: true
    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; autoPaddingEnabled: true }
  }
  }

  // ---- sparkles ---------------------------------------------------------
  // Soft motes drifting off Nyx. How many depends on the mood; the particle
  // system only runs while there's something to show.
  Timer { id: sparkleHold; interval: 3500 }
  ParticleSystem {
    id: motes
    anchors.fill: parent
    running: sparkles.emitRate > 0 || sparkleHold.running
  }
  ImageParticle {
    system: motes
    source: "qrc:///particleresources/glowdot.png"
    color: Qt.lighter(orb.color, 1.15)
    colorVariation: 0.12
    alpha: orb.asleep ? 0.35 : 0.85
    alphaVariation: 0.3
    entryEffect: ImageParticle.Scale
  }
  Emitter {
    id: sparkles
    system: motes
    x: body.x + body.width * 0.1
    y: body.y + body.height * 0.1
    width: body.width * 0.8
    height: body.height * 0.8
    shape: EllipseShape { fill: false }
    emitRate: orb.joyful ? 7
      : orb.thinking ? 9
      : orb.mood === "curious" ? 4 : 0
    lifeSpan: orb.thinking ? 1200 : 2400
    lifeSpanVariation: 700
    size: 7
    sizeVariation: 4
    endSize: 1
    velocity: AngleDirection {
      angle: 270
      angleVariation: orb.thinking ? 180 : 55
      magnitude: orb.thinking ? 26 : 16
      magnitudeVariation: 10
    }
    acceleration: PointDirection { y: -6; xVariation: 6 }
  }

  // ---- body -------------------------------------------------------------
  Item {
    id: body
    width: orb.size
    height: orb.size
    anchors.horizontalCenter: parent.horizontalCenter
    y: (parent.height - height) / 2 + bob + jump
    property real bob: 0
    property real jump: 0
    property real sway: 0
    rotation: (orb.mood === "curious" ? -9 : 0) + sway
    Behavior on rotation { enabled: !orb.vibing; NumberAnimation { duration: 400; easing.type: Easing.OutBack } }

    SequentialAnimation {
      id: hopAnim
      NumberAnimation { target: body; property: "jump"; to: -16; duration: 160; easing.type: Easing.OutQuad }
      NumberAnimation { target: body; property: "jump"; to: 0; duration: 420; easing.type: Easing.OutBounce }
    }


    property real breath: 1
    transform: [
      Scale { id: squashScale; origin.x: body.width / 2; origin.y: body.height; xScale: 1; yScale: 1 },
      Scale { origin.x: body.width / 2; origin.y: body.height; xScale: 1; yScale: body.breath }
    ]
    scale: orb.hovered ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

    SequentialAnimation {
      id: squishAnim
      ParallelAnimation {
        NumberAnimation { target: squashScale; property: "yScale"; to: 0.78; duration: 90 }
        NumberAnimation { target: squashScale; property: "xScale"; to: 1.18; duration: 90 }
      }
      ParallelAnimation {
        NumberAnimation { target: squashScale; property: "yScale"; to: 1; duration: 420; easing.type: Easing.OutElastic }
        NumberAnimation { target: squashScale; property: "xScale"; to: 1; duration: 420; easing.type: Easing.OutElastic }
      }
    }


    // Liquid body: a circle whose edge ripples. A gentle idle wobble, a big
    // jelly splash on clicks/hops, and a pulse with every beat.
    Shape {
      id: blob
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      readonly property int points: 48

      function update() {
        var cx = width / 2, cy = height / 2
        var R = width / 2 * (1 + orb.kick * 0.05 + orb.level * 0.03)
        var t = orb.t, w = orb.wobble
        var idle = orb.asleep ? 0.008 : 0.016
        var pts = []
        for (var i = 0; i <= points; i++) {
          var a = i / points * Math.PI * 2
          var r = R * (1
            + idle * Math.sin(3 * a + t * 1.3)
            + idle * 0.7 * Math.sin(2 * a - t * 0.9)
            + w * 0.075 * Math.sin(4 * a + t * 11)
            + w * 0.045 * Math.sin(3 * a - t * 8)
            + orb.kick * 0.03 * Math.sin(5 * a + t * 6))
          pts.push(Qt.point(cx + r * Math.cos(a), cy + r * Math.sin(a)))
        }
        line.path = pts
      }

      ShapePath {
        strokeWidth: 1
        strokeColor: Qt.rgba(1, 1, 1, 0.18)
        fillGradient: LinearGradient {
          x1: 0; y1: 0; x2: 0; y2: blob.height
          GradientStop { position: 0.0; color: Qt.lighter(orb.color, 1.22) }
          GradientStop { position: 0.55; color: orb.color }
          GradientStop { position: 1.0; color: Qt.darker(orb.color, 1.35) }
        }
        PathPolyline { id: line }
      }
    }

    // glossy highlight
    Rectangle {
      x: parent.width * 0.2
      y: parent.height * 0.12
      width: parent.width * 0.3
      height: parent.height * 0.17
      radius: height / 2
      rotation: -28
      color: Qt.rgba(1, 1, 1, 0.42)
    }

    // ---- face -----------------------------------------------------------
    Item {
      id: face
      width: parent.width * 0.56
      height: parent.height * 0.4
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: orb.lookX * parent.width * 0.09
      anchors.verticalCenterOffset: orb.lookY * parent.height * 0.08 + 1
      Behavior on anchors.horizontalCenterOffset { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
      Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

      property real open: 1
      SequentialAnimation {
        id: blink
        NumberAnimation { target: face; property: "open"; to: 0.08; duration: 70 }
        NumberAnimation { target: face; property: "open"; to: 1; duration: 110 }
      }
      Timer {
        interval: 2400 + Math.random() * 3500
        running: !orb.asleep && !orb.joyful
        repeat: true
        onTriggered: { interval = 2400 + Math.random() * 3500; blink.restart() }
      }

      Repeater {
        model: 2
        Item {
          id: eye
          required property int index
          readonly property real w: face.width * 0.2
          x: index === 0 ? face.width * 0.16 : face.width * 0.64
          y: 0
          width: w
          height: face.height * 0.7

          // normal eye (pill)
          Rectangle {
            visible: !orb.joyful && !orb.asleep
            anchors.centerIn: parent
            width: eye.w * (orb.hovered ? 1.1 : 1)
            height: Math.max(2, eye.height * face.open * (orb.mood === "curious" && eye.index === 1 ? 1.2 : 1) * (orb.hovered ? 1.08 : 1))
            radius: width / 2
            color: orb.eyeColor
            Behavior on width { NumberAnimation { duration: 150 } }

            // sparkle
            Rectangle {
              visible: face.open > 0.6
              x: parent.width * 0.52
              y: parent.height * 0.14
              width: parent.width * 0.38
              height: width
              radius: width / 2
              color: Qt.rgba(1, 1, 1, 0.85)
            }
          }

          // happy eye ^
          Canvas {
            id: happyEye
            visible: orb.joyful
            anchors.centerIn: parent
            width: eye.w * 1.5
            height: eye.w * 1.1
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = orb.eyeColor
              ctx.lineWidth = Math.max(2, width * 0.22)
              ctx.lineCap = "round"
              ctx.beginPath()
              ctx.arc(width / 2, height * 0.95, width * 0.36, Math.PI * 1.15, Math.PI * 1.85)
              ctx.stroke()
            }
            Connections { target: orb; function onEyeColorChanged() { happyEye.requestPaint() } }
          }

          // sleepy eye —
          Rectangle {
            visible: orb.asleep
            anchors.centerIn: parent
            anchors.verticalCenterOffset: eye.height * 0.15
            width: eye.w * 1.3
            height: Math.max(2, eye.w * 0.3)
            radius: height / 2
            color: orb.eyeColor
          }

          // worried brow
          Rectangle {
            visible: orb.mood === "worried"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 1
            width: eye.w * 1.4
            height: Math.max(2, eye.w * 0.28)
            radius: height / 2
            rotation: eye.index === 0 ? -18 : 18
            color: orb.eyeColor
          }
        }
      }

      // blush
      Repeater {
        model: 2
        Rectangle {
          required property int index
          visible: orb.joyful || orb.hovered
          opacity: orb.joyful ? 0.55 : 0.3
          width: face.width * 0.22
          height: width * 0.5
          radius: height / 2
          x: index === 0 ? face.width * 0.0 : face.width * 0.78
          y: face.height * 0.72
          color: "#ff6f9f"
        }
      }

      // tiny mouth when happy
      Canvas {
        id: mouth
        visible: orb.joyful || orb.hovered
        width: face.width * 0.22
        height: width * 0.6
        anchors.horizontalCenter: parent.horizontalCenter
        y: face.height * 0.74
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = orb.eyeColor
          ctx.lineWidth = Math.max(1.5, width * 0.16)
          ctx.lineCap = "round"
          ctx.beginPath()
          ctx.arc(width / 2, 0, width * 0.38, Math.PI * 0.15, Math.PI * 0.85)
          ctx.stroke()
        }
        Connections { target: orb; function onEyeColorChanged() { mouth.requestPaint() } }
      }

      // yawn
      Rectangle {
        visible: orb.mood === "yawn"
        anchors.horizontalCenter: parent.horizontalCenter
        y: face.height * 0.7
        width: face.width * 0.2
        height: width * 1.25
        radius: width / 2
        color: orb.eyeColor
      }
    }
  }

  // ---- music notes --------------------------------------------------------
  Repeater {
    model: orb.vibing ? 3 : 0
    Text {
      textFormat: Text.PlainText
      required property int index
      text: index === 1 ? "♫" : "♪"
      color: orb.color
      font.pixelSize: 13 + (index % 2) * 3
      font.bold: true
      x: body.x + (index === 0 ? -6 : index === 1 ? body.width * 0.85 : body.width * 0.3)
      opacity: 0
      SequentialAnimation on y {
        loops: Animation.Infinite
        PauseAnimation { duration: index * 550 }
        NumberAnimation { from: body.y + 10; to: body.y - 34; duration: 1650; easing.type: Easing.OutQuad }
      }
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        PauseAnimation { duration: index * 550 }
        NumberAnimation { from: 0; to: 0.95; duration: 350 }
        NumberAnimation { to: 0; duration: 1300 }
      }
    }
  }

  // ---- thinking dots ------------------------------------------------------
  Row {
    visible: orb.thinking
    spacing: 4
    anchors.horizontalCenter: body.horizontalCenter
    anchors.bottom: body.top
    anchors.bottomMargin: 2
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: 6; height: 6; radius: 3
        color: orb.color
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: orb.thinking
          PauseAnimation { duration: index * 160 }
          NumberAnimation { to: 1; duration: 260 }
          NumberAnimation { to: 0.2; duration: 420 }
          PauseAnimation { duration: (2 - index) * 160 }
        }
      }
    }
  }

  // ---- zzz ---------------------------------------------------------------
  Repeater {
    model: orb.mood === "sleepy" ? 3 : 0
    Text {
      textFormat: Text.PlainText
      required property int index
      text: "z"
      color: orb.color
      font.pixelSize: 11 + index * 3
      font.bold: true
      // Driven by the clock (each z rises over 2.1 s, staggered by 0.7 s).
      readonly property real phase: ((orb.t + (3 - index) * 0.7) % 2.1) / 2.1
      x: body.x + body.width * 0.8 + phase * 6
      y: body.y - 30 * phase
      opacity: phase < 0.24 ? phase / 0.24 * 0.9 : 0.9 * (1 - (phase - 0.24) / 0.76)
    }
  }
}
