import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The island's second page: Claude Code usage, what the machine is doing, and
// the six things you reach for most. Everything here is live and clickable.
//
//   ┌ Claude Code ─ session + weekly allowance ──────────────┬ System ───────┐
//   │                                                       │ CPU  MEM      │
//   │                                                       │ TEMP DISK     │
//   ├───────────────────────────────────────────────────────┴───────────────┤
//   │ Silent · Night Light · Stay Awake · Screenshot · Record · Lock        │
//   └───────────────────────────────────────────────────────────────────────┘
Item {
  id: extras

  required property var tk
  required property var status          // IslandStatus: silent, nightLight, stayAwake, recording
  required property var sys             // IslandSystem: Claude usage
  property bool revealed: false

  // Asks the bar to fold the island away before an action that needs the
  // screen (a screenshot, a lock, a terminal).
  signal closeRequested()
  signal openDetail(string kind)

  function run(argv) { Quickshell.execDetached(argv) }
  // Run once the island has folded out of the way, so it is not in a
  // screenshot or covering a region picker.
  function runAfterClose(argv) {
    extras.closeRequested()
    deferred.argv = argv
    deferred.restart()
  }
  Timer {
    id: deferred
    property var argv: []
    interval: extras.tk.collapseDuration + 60
    onTriggered: Quickshell.execDetached(argv)
  }

  // ------------------------------------------------------------ live stats
  // Polled only while the island is open; closed, it costs nothing.
  property var stats: ({ cpu: -1, memPct: -1, memUsed: "", memTotal: "", temp: -1, diskPct: -1, diskFree: 0, up: "" })

  Process {
    id: statsProc
    command: [Qt.resolvedUrl("island-stats.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { extras.stats = JSON.parse(String(text || "").trim()) } catch (e) {}
      }
    }
  }
  Timer {
    interval: 2000
    repeat: true
    running: extras.revealed
    triggeredOnStart: true
    onTriggered: if (!statsProc.running) statsProc.running = true
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: extras.tk.cardGap

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: extras.tk.cardGap

      // --- Claude Code -------------------------------------------------------
      IslandCard {
        tk: extras.tk
        index: 5
        revealed: extras.revealed
        interactive: true
        hot: claudeMouse.containsMouse
        down: claudeMouse.pressed
        Layout.preferredWidth: 3
        Layout.fillWidth: true
        Layout.fillHeight: true

        Item {
          anchors.fill: parent
          anchors.margins: extras.tk.cardPad

          Row {
            id: claudeHead
            anchors.top: parent.top
            anchors.left: parent.left
            spacing: extras.tk.px(7)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: extras.sys.claudeGlyph
              font.family: extras.tk.fontFamily
              font.pixelSize: extras.tk.tileIconSize
              color: extras.tk.textDim
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "CLAUDE CODE"
              font.family: extras.tk.fontFamily
              font.pixelSize: extras.tk.cardTitleSize
              font.letterSpacing: 0.8
              color: extras.tk.textFaint
            }
          }

          Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: extras.sys.claudeTier
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            font.letterSpacing: 0.8
            color: extras.tk.textFaint
          }

          // Both allowances the usage record carries, each drawn only when it
          // reports a percentage. Nothing here is derived or estimated.
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: claudeHead.bottom
            anchors.topMargin: extras.tk.px(7)
            spacing: extras.tk.px(6)

            IslandMeter {
              compact: true
              width: parent.width
              tk: extras.tk
              label: extras.sys.claudeSessionLabel
              percent: extras.sys.claudePercent
              reset: extras.sys.claudeSessionReset
            }
            IslandMeter {
              compact: true
              width: parent.width
              visible: extras.sys.claudeHasWeekly
              tk: extras.tk
              label: extras.sys.claudeWeeklyLabel
              percent: extras.sys.claudeWeeklyPercent
              reset: extras.sys.claudeWeeklyReset
            }

            // Without a signed-in CLI the record carries no limits at all, so
            // say that rather than drawing two empty bars.
            Text {
              width: parent.width
              visible: !extras.sys.claudeHasLimits
              text: extras.sys.claudeDetail
              wrapMode: Text.WordWrap
              font.family: extras.tk.fontFamily
              font.pixelSize: extras.tk.tileLabelSize
              color: extras.tk.textDim
            }
          }
        }

        MouseArea {
          id: claudeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: extras.openDetail("claude")
        }
      }

      // --- System -----------------------------------------------------------
      IslandCard {
        tk: extras.tk
        index: 6
        revealed: extras.revealed
        interactive: true
        hot: sysMouse.containsMouse
        down: sysMouse.pressed
        Layout.preferredWidth: 2
        Layout.fillWidth: true
        Layout.fillHeight: true

        Item {
          anchors.fill: parent
          anchors.margins: extras.tk.cardPad

          Text {
            id: sysHead
            anchors.left: parent.left
            anchors.top: parent.top
            text: "SYSTEM"
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            font.letterSpacing: 0.8
            color: extras.tk.textFaint
          }
          Text {
            anchors.right: parent.right
            anchors.baseline: sysHead.baseline
            text: extras.stats.up !== "" ? "up " + extras.stats.up : ""
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.cardTitleSize
            color: extras.tk.textFaint
          }

          Grid {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            columns: 2
            columnSpacing: extras.tk.px(12)
            rowSpacing: extras.tk.px(7)

            Repeater {
              model: [
                { label: "CPU",  pct: extras.stats.cpu,     text: extras.stats.cpu >= 0 ? extras.stats.cpu + "%" : "—", warn: 85 },
                { label: "MEM",  pct: extras.stats.memPct,  text: extras.stats.memUsed !== "" ? extras.stats.memUsed + "/" + extras.stats.memTotal + "G" : "—", warn: 85 },
                { label: "TEMP", pct: extras.stats.temp,    text: extras.stats.temp >= 0 ? extras.stats.temp + "°C" : "—", warn: 85 },
                { label: "DISK", pct: extras.stats.diskPct, text: extras.stats.diskPct >= 0 ? extras.stats.diskFree + "G free" : "—", warn: 90 }
              ]
              delegate: Column {
                required property var modelData
                width: (parent.width - extras.tk.px(12)) / 2
                spacing: extras.tk.px(3)
                Item {
                  width: parent.width
                  height: lbl.implicitHeight
                  Text {
                    id: lbl
                    text: modelData.label
                    font.family: extras.tk.fontFamily
                    font.pixelSize: extras.tk.cardTitleSize
                    font.letterSpacing: 0.6
                    color: extras.tk.textFaint
                  }
                  Text {
                    anchors.right: parent.right
                    text: modelData.text
                    font.family: extras.tk.fontFamily
                    font.pixelSize: extras.tk.cardTitleSize
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: modelData.pct >= modelData.warn ? extras.tk.accent : extras.tk.text
                  }
                }
                Rectangle {
                  width: parent.width
                  height: extras.tk.px(3)
                  radius: height / 2
                  color: extras.tk.meterTrack
                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100
                    color: modelData.pct >= modelData.warn ? extras.tk.accent : extras.tk.text
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }
          }
        }

        MouseArea {
          id: sysMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: extras.runAfterClose(["omarchy-launch-or-focus-tui", "btop"])
        }
      }
    }

    // --- Quick row, after Panacea's: the wide "coffee mode" switch (stay
    // awake), then round icon buttons. Lit = on.
    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 38
      Layout.maximumHeight: 38
      Layout.minimumHeight: 38
      spacing: 8

      Rectangle {
        id: awakeRow
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        readonly property bool on: extras.status.stayAwake
        color: on ? Qt.alpha(extras.tk.text, 0.16) : (awakeMa.containsMouse ? extras.tk.cardHover : extras.tk.card)
        border.width: 1
        border.color: on ? Qt.alpha(extras.tk.text, 0.40) : extras.tk.line
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 13
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: awakeRow.on ? "󰅶" : "󰛊"
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.iconSize
            color: awakeRow.on ? extras.tk.text : extras.tk.textDim
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Stay awake"
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.fontSize - 2
            font.bold: awakeRow.on
            color: awakeRow.on ? extras.tk.text : extras.tk.textDim
          }
        }
        // the switch
        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 38; height: 21; radius: 11
          color: awakeRow.on ? extras.tk.text : Qt.alpha(extras.tk.text, 0.14)
          Behavior on color { ColorAnimation { duration: 180 } }
          Rectangle {
            width: 17; height: 17; radius: 9; y: 2
            x: awakeRow.on ? parent.width - width - 2 : 2
            color: awakeRow.on ? extras.tk.surface : extras.tk.text
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          }
        }
        MouseArea {
          id: awakeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: extras.run(["omarchy-toggle-idle"])
        }
      }

      Repeater {
        model: [
          { glyph: extras.status.silent ? "󰂛" : "󰂚", tip: "Silent", on: extras.status.silent,
            argv: ["omarchy-shell", "-q", "notifications", "toggleDnd"] },
          { glyph: "󰔎", tip: "Night light", on: extras.status.nightLight, argv: ["omarchy-toggle-nightlight"] },
          { glyph: "󰄀", tip: "Screenshot", on: false, close: true, argv: ["omarchy-capture-screenshot"] },
          { glyph: "󰻃", tip: extras.status.recording ? "Stop recording" : "Record", on: extras.status.recording,
            crit: true, close: !extras.status.recording,
            argv: extras.status.recording ? ["omarchy-capture-screenrecording", "--stop-recording"]
                                          : ["omarchy-capture-screenrecording"] },
          { glyph: "󰌾", tip: "Lock", on: false, close: true, argv: ["omarchy-system-lock"] }
        ]
        // Panacea's IconBtn: 12-radius square, hairline, glyph muted until lit.
        delegate: Rectangle {
          required property var modelData
          Layout.preferredWidth: 38
          Layout.fillHeight: true
          radius: 12
          color: modelData.on ? (modelData.crit ? extras.tk.crit : extras.tk.text)
               : ib.pressed ? extras.tk.cardPressed : ib.containsMouse ? extras.tk.cardHover : extras.tk.card
          border.width: 1
          border.color: modelData.on ? "transparent" : extras.tk.line
          Behavior on color { ColorAnimation { duration: 160 } }
          scale: ib.pressed ? 0.92 : 1
          Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
          Text {
            anchors.centerIn: parent
            text: modelData.glyph
            font.family: extras.tk.fontFamily
            font.pixelSize: extras.tk.iconSize - 1
            color: modelData.on ? (modelData.crit ? "#ffffff" : extras.tk.pillText)
                 : ib.containsMouse ? extras.tk.text : extras.tk.textDim
          }
          MouseArea {
            id: ib
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.close ? extras.runAfterClose(modelData.argv) : extras.run(modelData.argv)
          }
        }
      }
    }
  }
}
