import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The open island.
//
//   ┌ strip: weather ─────────────────────────────────────────┐
//   ├──────────────────────────┬──────────────┬───────────────┤
//   │ Now playing (cover, ⏮ ⏯ ⏭, seek) │ Wi-Fi   │ Bluetooth   │
//   │                                  │ Sound   │ Battery     │
//   └──────────────────────────────────┴─────────┴─────────────┘
//   page 2 (Tab): IslandExtras — Claude Code · system · quick toggles
//
// The clock is deliberately absent: opening the island replaces the time
// rather than demoting it. The strip carries weather and nothing else — the
// per-device glyphs that used to sit on the right are the cards' job, and
// repeating them there only made the strip noisy.
//
// Clicking a card swaps this whole surface for that card's detail view, in
// place. Nothing about the island ever opens outside the island.
Item {
  id: tray

  required property var tk
  required property var sys
  property var status: null
  property bool revealed: false
  // Which page is showing: 0 = overview (now playing and the four device
  // cards), 1 = Claude Code, system load and quick toggles. Tab / Shift+Tab
  // (the island submap) or the dots in the strip switch it.
  property int page: 0
  readonly property int pageCount: 2

  signal openDetail(string kind)
  signal nudgeVolume(int steps)
  signal closeRequested()
  signal pageRequested(int page)
  signal openApp(string kind)

  // Everything fades as one group; the cards stagger within it.
  opacity: revealed ? 1 : 0
  visible: opacity > 0
  Behavior on opacity {
    SequentialAnimation {
      PauseAnimation { duration: tray.revealed ? tray.tk.contentInDelay : 0 }
      NumberAnimation {
        duration: tray.revealed ? tray.tk.contentInDuration : tray.tk.contentOutDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: tray.tk.fadeCurve
      }
    }
  }

  // ---------------------------------------------------------- status strip
  Row {
    id: strip
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.leftMargin: tray.tk.px(4)
    height: tray.tk.px(20)
    spacing: tray.tk.px(7)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.weatherGlyph
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.glyphSize
      color: tray.tk.textDim
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.weatherValue
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.statSize
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      color: tray.tk.text
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tray.sys.hasWeather
        ? tray.sys.weather.condition + (tray.sys.weatherPlace !== "" ? "  ·  " + tray.sys.weatherPlace : "")
        : "Weather unavailable"
      font.family: tray.tk.fontFamily
      font.pixelSize: tray.tk.tileLabelSize
      color: tray.tk.textFaint
    }
  }

  // ------------------------------------------------------------ app pills
  // The strip's right edge: WhatsApp always, and Shan Shui only while the
  // painted wallpaper is on. With the static wallpaper the strip is exactly
  // the plain one. State comes from zed.shanshui's own state file, re-read
  // only while the island is open.
  property bool shanshuiOn: false
  property bool shanshuiPaused: false

  FileView {
    id: shanshuiState
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zed.shanshui/estado.json"
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        tray.shanshuiOn = s.ativo !== false
        tray.shanshuiPaused = !!s.pausado
      } catch (e) { tray.shanshuiOn = false }
    }
    onLoadFailed: tray.shanshuiOn = false
  }
  Timer {
    interval: 1500
    running: tray.revealed
    repeat: true
    triggeredOnStart: true
    onTriggered: shanshuiState.reload()
  }
  function shanshui(cmd) {
    Quickshell.execDetached(["omarchy-shell", "-q", "shanshui", cmd])
    shanshuiRefresh.restart()
  }
  Timer { id: shanshuiRefresh; interval: 250; onTriggered: shanshuiState.reload() }

  IslandCard {
    id: shanshuiPill
    tk: tray.tk
    index: 0
    revealed: tray.revealed
    interactive: true
    hot: shanshuiMouse.containsMouse
    down: shanshuiMouse.pressed
    visible: tray.shanshuiOn
    anchors.right: whatsapp.left
    anchors.rightMargin: tray.tk.px(6)
    anchors.verticalCenter: strip.verticalCenter
    height: strip.height
    width: shanshuiRow.implicitWidth + tray.tk.px(16)

    Row {
      id: shanshuiRow
      anchors.centerIn: parent
      spacing: tray.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "山"
        font.pixelSize: tray.tk.glyphSize
        color: tray.shanshuiPaused ? tray.tk.textFaint : tray.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // Left click: settings (in-island). Middle: pause / resume. Right:
        // back to the static wallpaper (the pill then disappears).
        text: shanshuiMouse.containsMouse ? "SETTINGS"
                                          : (tray.shanshuiPaused ? "PAUSED" : "PAINTING")
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.cardTitleSize
        font.letterSpacing: 0.8
        color: tray.tk.textFaint
      }
    }

    MouseArea {
      id: shanshuiMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) tray.shanshui("desligar")
        else if (mouse.button === Qt.MiddleButton) tray.shanshui(tray.shanshuiPaused ? "continuar" : "pausar")
        else tray.openDetail("shanshui")
      }
    }
  }

  // An app launcher, not a status glyph. The island closes as the app opens.
  IslandCard {
    id: whatsapp
    tk: tray.tk
    index: 0
    revealed: tray.revealed
    interactive: true
    hot: whatsappMouse.containsMouse
    down: whatsappMouse.pressed
    anchors.right: parent.right
    anchors.verticalCenter: strip.verticalCenter
    height: strip.height
    width: whatsappRow.implicitWidth + tray.tk.px(16)

    Row {
      id: whatsappRow
      anchors.centerIn: parent
      spacing: tray.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.glyphSize
        color: tray.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "WHATSAPP"
        font.family: tray.tk.fontFamily
        font.pixelSize: tray.tk.cardTitleSize
        font.letterSpacing: 0.8
        color: tray.tk.textFaint
      }
    }

    MouseArea {
      id: whatsappMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tray.openApp("whatsapp")
    }
  }

  // ----------------------------------------------------------------- pages
  // Both pages are laid out once at full size, side by side, and slid under a
  // clip; switching never re-runs a layout mid-animation.
  Item {
    id: pager
    anchors.top: strip.bottom
    anchors.topMargin: tray.tk.px(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true

    readonly property real stride: width + tray.tk.cardGap * 2

    Item {
      id: page0
      width: pager.width
      height: pager.height
      x: (0 - tray.page) * pager.stride
      Behavior on x {
        NumberAnimation { duration: tray.tk.expandDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve }
      }

      RowLayout {
        id: body
        anchors.fill: parent
        spacing: tray.tk.cardGap

        // --- Now playing (Spotify or any MPRIS player) -----------------------
        IslandMedia {
          tk: tray.tk
          index: 0
          revealed: tray.revealed && tray.page === 0
          active: tray.revealed && tray.page === 0
          Layout.preferredWidth: 1
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        // --- controls ----------------------------------------------------------
        GridLayout {
          Layout.preferredWidth: 1
          Layout.fillWidth: true
          Layout.fillHeight: true
          columns: 2
          rowSpacing: tray.tk.cardGap
          columnSpacing: tray.tk.cardGap

          IslandTile {
            tk: tray.tk; index: 1; revealed: tray.revealed && tray.page === 0
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: tray.sys.netGlyph
            value: tray.sys.netValue
            label: "WI-FI"
            on: tray.sys.netKind === "wifi" || tray.sys.netKind === "ethernet"
            detail: tray.sys.netDetail
            dimmed: tray.sys.netKind !== "wifi" && tray.sys.netKind !== "ethernet"
            onActivated: tray.openDetail("network")
          }

          IslandTile {
            tk: tray.tk; index: 2; revealed: tray.revealed && tray.page === 0
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: tray.sys.btGlyph
            value: tray.sys.btValue
            label: "BLUETOOTH"
            on: tray.sys.btEnabled && tray.sys.btConnected.length > 0
            detail: tray.sys.btDetail
            dimmed: !tray.sys.btEnabled
            onActivated: tray.openDetail("bluetooth")
          }

          IslandTile {
            tk: tray.tk; index: 3; revealed: tray.revealed && tray.page === 0
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: tray.sys.audioGlyph
            value: tray.sys.audioValue
            label: "SOUND"
            detail: tray.sys.audioDevice
            dimmed: tray.sys.muted
            onActivated: tray.openDetail("audio")
            onScrolled: function(steps) { tray.nudgeVolume(steps) }
          }

          IslandTile {
            tk: tray.tk; index: 4; revealed: tray.revealed && tray.page === 0
            Layout.fillWidth: true; Layout.fillHeight: true
            glyph: tray.sys.batteryGlyph
            value: tray.sys.batteryValue
            label: "BATTERY"
            on: tray.sys.charging || tray.sys.batteryFull
            detail: tray.sys.batteryDetail
            attention: tray.sys.batteryLow
            onActivated: tray.openDetail("battery")
          }
        }
      }
    }

    Item {
      id: page1
      width: pager.width
      height: pager.height
      x: (1 - tray.page) * pager.stride
      Behavior on x {
        NumberAnimation { duration: tray.tk.expandDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve }
      }

      IslandExtras {
        anchors.fill: parent
        tk: tray.tk
        status: tray.status
        sys: tray.sys
        revealed: tray.revealed && tray.page === 1
        onCloseRequested: tray.closeRequested()
        onOpenDetail: function(kind) { tray.openDetail(kind) }
      }
    }
  }

  // Page dots, centred in the strip. Click one to jump to it.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: strip.verticalCenter
    spacing: tray.tk.px(6)

    Repeater {
      model: tray.pageCount
      delegate: Rectangle {
        required property int index
        readonly property bool current: index === tray.page
        anchors.verticalCenter: parent.verticalCenter
        width: current ? tray.tk.px(18) : tray.tk.px(6)
        height: tray.tk.px(6)
        radius: height / 2
        color: current ? tray.tk.text : (dotMouse.containsMouse ? tray.tk.textDim : tray.tk.textFaint)
        Behavior on width { NumberAnimation { duration: tray.tk.radiusDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: tray.tk.springCurve } }
        Behavior on color { ColorAnimation { duration: tray.tk.colorDuration } }
        MouseArea {
          id: dotMouse
          anchors.fill: parent
          anchors.margins: -tray.tk.px(5)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: tray.pageRequested(index)
        }
      }
    }
  }
}
