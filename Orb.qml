import QtQuick
import QtQuick.Effects

// Nyx's body: a glowing orb with expressive eyes.
// mood: idle | thinking | happy | proud | curious | worried | sleepy | yawn | vibing | neutral
Item {
  id: orb

  property color color: "#e8a2c8"
  property color eyeColor: "#13111c"
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

  function squish() { squishAnim.restart() }
  function hop() { hopAnim.restart() }

  // ---- glow -------------------------------------------------------------
  Rectangle {
    id: glow
    anchors.centerIn: body
    width: orb.size * 1.35
    height: width
    radius: width / 2
    color: orb.color
    opacity: orb.thinking ? 0.75 : (orb.hovered ? 0.6 : 0.42)
    Behavior on opacity { NumberAnimation { duration: 300 } }
    layer.enabled: true
    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; autoPaddingEnabled: true }

    SequentialAnimation on scale {
      loops: Animation.Infinite
      running: true
      NumberAnimation { to: orb.thinking ? 1.18 : 1.06; duration: orb.thinking ? 500 : 1800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.96; duration: orb.thinking ? 500 : 1800; easing.type: Easing.InOutSine }
    }
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

    SequentialAnimation on sway {
      loops: Animation.Infinite
      running: orb.vibing
      NumberAnimation { to: 9; duration: 300; easing.type: Easing.InOutSine }
      NumberAnimation { to: -9; duration: 600; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0; duration: 300; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) body.sway = 0
    }

    SequentialAnimation on bob {
      loops: Animation.Infinite
      running: !orb.asleep && !orb.vibing
      NumberAnimation { to: -4; duration: 1400; easing.type: Easing.InOutSine }
      NumberAnimation { to: 2; duration: 1400; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on bob {
      loops: Animation.Infinite
      running: orb.vibing
      NumberAnimation { to: -6; duration: 300; easing.type: Easing.OutQuad }
      NumberAnimation { to: 1; duration: 300; easing.type: Easing.InQuad }
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

    // breathing
    SequentialAnimation {
      running: true
      loops: Animation.Infinite
      NumberAnimation { target: body; property: "breath"; to: orb.asleep ? 0.94 : 1.025; duration: orb.asleep ? 2200 : 1600; easing.type: Easing.InOutSine }
      NumberAnimation { target: body; property: "breath"; to: 1; duration: orb.asleep ? 2200 : 1600; easing.type: Easing.InOutSine }
    }

    Rectangle {
      id: shell
      anchors.fill: parent
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.lighter(orb.color, 1.22) }
        GradientStop { position: 0.55; color: orb.color }
        GradientStop { position: 1.0; color: Qt.darker(orb.color, 1.35) }
      }
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.18)
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
      required property int index
      text: "z"
      color: orb.color
      font.pixelSize: 11 + index * 3
      font.bold: true
      x: body.x + body.width * 0.8
      y: body.y
      opacity: 0
      SequentialAnimation on y {
        loops: Animation.Infinite
        PauseAnimation { duration: index * 700 }
        NumberAnimation { from: body.y; to: body.y - 30; duration: 2100 }
      }
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        PauseAnimation { duration: index * 700 }
        NumberAnimation { from: 0; to: 0.9; duration: 500 }
        NumberAnimation { to: 0; duration: 1600 }
      }
    }
  }
}
