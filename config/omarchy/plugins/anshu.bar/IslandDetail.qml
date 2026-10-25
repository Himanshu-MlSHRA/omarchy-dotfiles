import QtQuick
import Quickshell
import Quickshell.Io

// A detail view living *inside* the island. Opening one slides the card row
// out and this in; Escape or the back affordance reverses it. The island never
// hands a detail off to a popup outside its own surface.
//
// Every pane is sized to the content it actually has (IslandTokens.detailHeightFor)
// and carries only the facts the panel is for — the earlier version padded all
// five to the tallest one and filled the space with rows that were usually "—".
Item {
  id: detail

  required property var tk
  required property var sys
  property string kind: ""
  property bool revealed: false

  signal back()

  // The Wi-Fi password field needs real keyboard focus, which only the bar's
  // own layer surface can take. Bar.qml watches this and asks the compositor
  // for the keyboard exactly while it is true.
  readonly property bool keyboardWanted: revealed && ((kind === "network" && sys.promptActive)
                                                      || (kind === "shanshui" && shanHexFocused))
  // A Shan Shui hex field is being typed in.
  property bool shanHexFocused: false

  // Diagnostics for the password field: whether it holds focus and how much has
  // been typed. Never the text itself — the probe that reads this is a shell
  // command, and a password has no business on a terminal.
  property bool promptFieldFocused: false
  property int promptFieldLength: 0

  // ------------------------------------------------------------- components
  // A small pill button. Inline so the island keeps its file count.
  component ActionChip: Rectangle {
    id: chip
    required property var tk
    property string label: ""
    property string glyph: ""
    property bool danger: false
    property bool enabledChip: true
    property bool selected: false
    signal clicked()

    implicitWidth: chipRow.implicitWidth + chip.tk.px(20)
    implicitHeight: chip.tk.px(24)
    radius: height / 2
    opacity: enabledChip ? 1 : 0.35
    color: chipMouse.pressed ? chip.tk.cardPressed
      : (chipMouse.containsMouse || chip.selected ? chip.tk.cardHover : chip.tk.fieldBg)
    border.width: chip.selected ? 1 : 0
    border.color: chip.tk.accent
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: chip.tk.px(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.glyph !== ""
        text: chip.glyph
        font.family: chip.tk.fontFamily
        font.pixelSize: chip.tk.tileLabelSize
        color: chip.danger ? chip.tk.danger : chip.tk.textDim
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        font.family: chip.tk.fontFamily
        font.pixelSize: chip.tk.tileLabelSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        color: chip.danger ? chip.tk.danger : chip.tk.text
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.enabledChip
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // A labelled row of option chips (Shan Shui settings).
  component OptionRow: Row {
    id: optRow
    required property var tk
    required property string label
    property alias chips: chipRow.data
    spacing: tk.px(10)
    height: tk.px(24)

    Text {
      width: optRow.tk.px(64)
      anchors.verticalCenter: parent.verticalCenter
      text: optRow.label
      font.family: optRow.tk.fontFamily
      font.pixelSize: optRow.tk.cardTitleSize
      font.letterSpacing: 0.8
      color: optRow.tk.textFaint
    }
    Row {
      id: chipRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: optRow.tk.px(6)
    }
  }

  // A round colour swatch (Shan Shui ink / paper).
  component Swatch: Rectangle {
    id: sw
    required property var tk
    required property string hex
    property string name: ""
    property bool selected: false
    signal picked(string hex)
    width: tk.px(20)
    height: width
    radius: width / 2
    color: hex
    border.width: selected ? 2 : 1
    border.color: selected ? tk.accent : (swMouse.containsMouse ? tk.text : tk.line)
    MouseArea {
      id: swMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.picked(sw.hex)
    }
  }

  // A rainbow strip: click or drag anywhere to pick that hue.
  component HueBar: Rectangle {
    id: hue
    required property var tk
    property real saturation: 0.62
    property real lightness: 0.62
    signal picked(string hex)
    width: tk.px(120)
    height: tk.px(14)
    radius: height / 2
    border.width: 1
    border.color: tk.line
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.000; color: Qt.hsla(0.000, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.167; color: Qt.hsla(0.167, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.333; color: Qt.hsla(0.333, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.500; color: Qt.hsla(0.500, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.667; color: Qt.hsla(0.667, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 0.833; color: Qt.hsla(0.833, hue.saturation, hue.lightness, 1) }
      GradientStop { position: 1.000; color: Qt.hsla(0.999, hue.saturation, hue.lightness, 1) }
    }
    function pickAt(x) {
      var h = Math.max(0, Math.min(0.999, x / width))
      var c = Qt.hsla(h, saturation, lightness, 1)
      function two(v) { var t = Math.round(v * 255).toString(16); return t.length < 2 ? "0" + t : t }
      picked("#" + two(c.r) + two(c.g) + two(c.b))
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      onPressed: function(m) { hue.pickAt(m.x) }
      onPositionChanged: function(m) { if (pressed) hue.pickAt(m.x) }
    }
  }

  // "#rrggbb" entry; Enter applies. Any colour in the world.
  component HexField: Rectangle {
    id: hf
    required property var tk
    property string current: ""
    signal picked(string hex)
    signal focusChanged2(bool focused)
    width: tk.px(84)
    height: tk.px(22)
    radius: height / 2
    color: tk.fieldBg
    border.width: 1
    border.color: field.activeFocus ? tk.accent : "transparent"
    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: hf.tk.px(10)
      anchors.rightMargin: hf.tk.px(8)
      verticalAlignment: TextInput.AlignVCenter
      maximumLength: 7
      selectByMouse: true
      clip: true
      font.family: hf.tk.fontFamily
      font.pixelSize: hf.tk.tileLabelSize
      color: /^#?[0-9a-fA-F]{6}$/.test(text) || text === "" ? hf.tk.text : hf.tk.danger
      selectionColor: hf.tk.accent
      onActiveFocusChanged: { hf.focusChanged2(activeFocus); if (activeFocus) selectAll() }
      onAccepted: {
        var t = text.trim()
        if (t.charAt(0) !== "#") t = "#" + t
        if (/^#[0-9a-fA-F]{6}$/.test(t)) { hf.picked(t.toLowerCase()); field.focus = false }
      }
      Keys.onEscapePressed: { text = ""; field.focus = false }
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text === "" && !field.activeFocus
        text: hf.current !== "" ? hf.current : "#hex"
        font: field.font
        color: hf.tk.textFaint
      }
    }
  }

  // A section heading inside a card.
  component CardTitle: Text {
    required property var tk
    font.family: tk.fontFamily
    font.pixelSize: tk.cardTitleSize
    font.letterSpacing: 0.8
    color: tk.textFaint
  }

  // The one line at the foot of a panel that says what just happened. An error
  // outranks a notice, and a connection in flight outranks both.
  component FeedbackLine: Text {
    required property var tk
    property string error: ""
    property string notice: ""
    property string busy: ""
    text: busy !== "" ? busy : (error !== "" ? error : notice)
    visible: text !== ""
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: tk.fontFamily
    font.pixelSize: tk.tileLabelSize
    renderType: Text.NativeRendering
    color: busy !== "" ? tk.textDim : (error !== "" ? tk.danger : tk.textDim)
  }

  // ------------------------------------------------------------- header
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: detail.tk.px(20)

    Row {
      id: backRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: detail.tk.px(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""   // chevron-left
        font.family: detail.tk.fontFamily
        font.pixelSize: detail.tk.tileLabelSize
        color: backMouse.containsMouse ? detail.tk.text : detail.tk.textFaint
        Behavior on color { ColorAnimation { duration: 120 } }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: detail.title
        font.family: detail.tk.fontFamily
        font.pixelSize: detail.tk.detailTitleSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4
        renderType: Text.NativeRendering
        color: detail.tk.text
      }
    }

    MouseArea {
      id: backMouse
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: backRow.width + detail.tk.px(12)
      height: parent.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: detail.back()
    }

    // Right of the header: whatever the panel is currently doing, else ESC.
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: detail.headerNote
      font.family: detail.tk.fontFamily
      font.pixelSize: detail.tk.tileLabelSize
      font.letterSpacing: detail.headerNote === "ESC" ? 1.0 : 0.0
      color: detail.tk.textFaint
    }
  }

  readonly property string title: {
    if (kind === "network") return sys.netKind === "ethernet" ? "Ethernet" : "Wi-Fi"
    if (kind === "bluetooth") return "Bluetooth"
    if (kind === "audio") return "Sound"
    if (kind === "battery") return "Battery"
    if (kind === "claude") return "Claude Code"
    if (kind === "shanshui") return "山  Shan Shui"
    return ""
  }

  readonly property string headerNote: {
    if (kind === "network" && sys.wifiDevice && sys.wifiDevice.scannerEnabled) return "scanning"
    if (kind === "bluetooth" && sys.btScanning) return "scanning"
    if (kind === "claude" && sys.claudeAge !== "") return sys.claudeAge
    if (kind === "shanshui") return shan.statusText
    return "ESC"
  }

  // -------------------------------------------------------------- body
  Loader {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: detail.tk.px(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    sourceComponent: detail.kind === "network" ? networkBody
      : detail.kind === "bluetooth" ? bluetoothBody
      : detail.kind === "audio" ? audioBody
      : detail.kind === "battery" ? batteryBody
      : detail.kind === "claude" ? claudeBody
      : detail.kind === "shanshui" ? shanshuiBody : null
  }

  // ------------------------------------------------------- shan shui state
  // zed.shanshui (the painted wallpaper) is driven through its own IPC and its
  // own config.json, which it watches and reloads. Polled only while this pane
  // is up.
  QtObject {
    id: shan
    property bool on: false
    property bool paused: false
    property bool covered: false
    property string error: ""
    property int scroll: 0
    property var opts: ({})
    readonly property string statusText: error === "node" ? "needs nodejs"
      : error === "rsvg" ? "needs librsvg"
      : !on ? "static wallpaper"
      : paused ? "paused · scroll " + scroll
      : covered ? "waiting (fullscreen)"
      : "painting · scroll " + scroll

    function ipc(cmd, arg) {
      var c = ["omarchy-shell", "-q", "shanshui", cmd]
      if (arg !== undefined) c.push(String(arg))
      Quickshell.execDetached(c)
      shanRefresh.restart()
    }
    function same(a, b) { return String(a || "").toLowerCase() === String(b || "").toLowerCase() }
    // Merge one change into the full option set and write config.json.
    function set(change) {
      var o = {}
      for (var k in opts) o[k] = opts[k]
      for (k in change) o[k] = change[k]
      opts = o
      shanConfig.setText(JSON.stringify(o, null, 2) + "\n")
    }
  }

  Process {
    id: shanProbe
    command: ["omarchy-shell", "shanshui", "estado"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var e = JSON.parse(text)
          shan.on = !!e.ativo
          shan.paused = !!e.pausado
          shan.covered = !!e.encoberto
          shan.error = e.erro || ""
          shan.scroll = (e.kFrente || 0) + 1
          shan.opts = e.opcoes || {}
        } catch (err) { shan.error = "plugin not running" }
      }
    }
  }
  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: detail.revealed && detail.kind === "shanshui"
    onTriggered: if (!shanProbe.running) shanProbe.running = true
  }
  Timer { id: shanRefresh; interval: 300; onTriggered: if (!shanProbe.running) shanProbe.running = true }

  FileView {
    id: shanConfig
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zed.shanshui/config.json"
    printErrors: false
    blockLoading: false
  }

  // --------------------------------------------------------- network
  Component {
    id: networkBody

    Item {
      anchors.fill: parent

      // ---- the password prompt takes the whole pane while it is up ----------
      // It replaces the list rather than squeezing in beside it: the network is
      // already chosen by the time this appears, and a password field wants the
      // width more than the list does.
      IslandCard {
        id: prompt
        anchors.fill: parent
        tk: detail.tk
        revealed: true
        visible: detail.sys.promptActive
        z: 2

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(7)

          Text {
            width: parent.width
            text: "Join “" + detail.sys.promptName + "”"
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.tk.text
          }

          Rectangle {
            width: parent.width
            height: detail.tk.fieldHeight
            radius: detail.tk.px(8)
            color: detail.tk.fieldBg
            border.width: 1
            border.color: password.activeFocus ? detail.tk.accent : "transparent"

            TextInput {
              id: password
              anchors.fill: parent
              anchors.leftMargin: detail.tk.px(10)
              anchors.rightMargin: eye.width + detail.tk.px(14)
              verticalAlignment: TextInput.AlignVCenter
              echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              selectByMouse: true
              clip: true
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.tileValueSize
              color: detail.tk.text
              selectionColor: detail.tk.accent
              onAccepted: detail.sys.submitPassword(password.text)

              Keys.onEscapePressed: detail.sys.cancelPrompt()

              onActiveFocusChanged: detail.promptFieldFocused = activeFocus
              onTextChanged: detail.promptFieldLength = text.length

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: password.text === ""
                text: "Password"
                font: password.font
                color: detail.tk.textFaint
              }
            }

            // Show/hide, because a mistyped key is the usual reason this fails.
            Item {
              id: eye
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: detail.tk.px(28)
              height: parent.height

              QtObject { id: reveal; property bool checked: false }

              Text {
                anchors.centerIn: parent
                text: reveal.checked ? "󰛐" : "󰛑"
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                color: eyeMouse.containsMouse ? detail.tk.text : detail.tk.textFaint
              }
              MouseArea {
                id: eyeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: reveal.checked = !reveal.checked
              }
            }
          }

          FeedbackLine {
            width: parent.width
            tk: detail.tk
            error: detail.sys.netError
          }

          Row {
            spacing: detail.tk.px(7)

            ActionChip {
              tk: detail.tk
              label: "Connect"
              glyph: "󰤨"
              enabledChip: password.text.length > 0
              onClicked: detail.sys.submitPassword(password.text)
            }
            ActionChip {
              tk: detail.tk
              label: "Cancel"
              onClicked: detail.sys.cancelPrompt()
            }
          }
        }

        // Focus follows the prompt appearing, so the password can be typed
        // straight away without clicking into the field first.
        Connections {
          target: detail.sys
          function onPromptNameChanged() {
            if (detail.sys.promptActive) { password.text = ""; password.forceActiveFocus() }
          }
        }
        onVisibleChanged: if (visible) { password.text = ""; password.forceActiveFocus() }
      }

      // ---- normal two-card layout -----------------------------------------
      Row {
        anchors.fill: parent
        spacing: detail.tk.cardGap
        visible: !detail.sys.promptActive

        // Left: what this connection is, and what can be done to it.
        IslandCard {
          tk: detail.tk
          revealed: true
          width: (parent.width - detail.tk.cardGap) * 0.44
          height: parent.height

          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: detail.tk.cardPad
            spacing: detail.tk.px(2)

            Text {
              width: parent.width
              text: detail.sys.netValue
              elide: Text.ElideRight
              textFormat: Text.PlainText
              font.family: detail.tk.fontFamily
              font.pixelSize: detail.tk.cardValueSize
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
              color: detail.tk.text
            }
            Item { width: 1; height: detail.tk.px(5) }

            // Only the facts that change what you would do next. Adapter name,
            // gateway and band were filler on a panel this size.
            IslandRow {
              tk: detail.tk; width: parent.width; label: "Signal"
              value: detail.sys.netSignal >= 0 ? detail.sys.netSignal + "%" : ""
            }
            IslandRow {
              tk: detail.tk; width: parent.width; label: "Rate"
              value: detail.sys.netDetail2.rate || ""
            }
            IslandRow {
              tk: detail.tk; width: parent.width; label: "IP"
              value: detail.sys.netDetail2.ip || ""
            }
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: detail.tk.px(8)
            spacing: detail.tk.px(6)

            FeedbackLine {
              width: parent.width
              tk: detail.tk
              error: detail.sys.netError
              notice: detail.sys.netNotice
              busy: detail.sys.netBusyName !== "" ? "Connecting to " + detail.sys.netBusyName + "…" : ""
            }

            Row {
              spacing: detail.tk.px(6)

              ActionChip {
                tk: detail.tk
                label: detail.sys.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                glyph: detail.sys.wifiEnabled ? "󰤨" : "󰖪"
                enabledChip: !detail.sys.wifiBlocked
                onClicked: detail.sys.toggleWifi()
              }
              ActionChip {
                tk: detail.tk
                label: "Disconnect"
                visible: !!detail.sys.activeWifi
                onClicked: detail.sys.disconnectNetwork(detail.sys.activeWifi)
              }
            }
          }
        }

        // Right: every network in range, live.
        IslandCard {
          tk: detail.tk
          revealed: true
          width: (parent.width - detail.tk.cardGap) * 0.56
          height: parent.height

          CardTitle {
            id: netListTitle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: detail.tk.cardPad
            tk: detail.tk
            text: "NETWORKS"
          }

          Text {
            anchors.centerIn: parent
            visible: detail.sys.wifiNetworks.length === 0
            text: !detail.sys.wifiEnabled ? "Wi-Fi is off" : "Looking for networks…"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            color: detail.tk.textFaint
          }

          ListView {
            anchors.top: netListTitle.bottom
            anchors.topMargin: detail.tk.px(5)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: detail.tk.px(4)
            anchors.rightMargin: detail.tk.px(4)
            anchors.bottomMargin: detail.tk.px(6)
            clip: true
            model: detail.sys.wifiNetworks
            boundsBehavior: Flickable.StopAtBounds

            delegate: IslandListRow {
              required property var modelData
              width: ListView.view.width
              tk: detail.tk
              glyph: detail.sys.wifiBarsFor(modelData)
              title: String(modelData.name || "")
              selected: modelData.connected
              // Every network is actionable now: an unsaved secured one opens
              // the password prompt instead of sitting inert.
              enabledRow: !detail.sys.wifiIsEnterprise(modelData.security)
              note: {
                if (detail.sys.netBusyName === String(modelData.name || "")) return "Connecting…"
                if (modelData.connected) return "Connected"
                if (modelData.stateChanging) return "…"
                if (detail.sys.wifiIsEnterprise(modelData.security)) return "802.1X"
                var pct = Math.round(modelData.signalStrength * 100) + "%"
                if (modelData.known) return "Saved · " + pct
                return detail.sys.wifiIsOpen(modelData.security) ? pct : "󰍁 " + pct
              }
              onActivated: detail.sys.activateNetwork(modelData)
              // Right-click forgets a saved profile, which is the only
              // destructive thing here and so is kept off the primary tap.
              onSecondary: if (modelData.known) detail.sys.forgetNetwork(modelData)
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- bluetooth
  Component {
    id: bluetoothBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(2)

          Text {
            width: parent.width
            text: detail.sys.btValue
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.btEnabled ? detail.tk.text : detail.tk.textFaint
          }
          Item { width: 1; height: detail.tk.px(5) }

          IslandRow {
            tk: detail.tk; width: parent.width; label: "Paired"
            value: String(detail.sys.btDevices.length)
          }
          IslandRow {
            tk: detail.tk; width: parent.width; label: "In range"
            value: detail.sys.btScanning ? String(detail.sys.btNearby.length) : ""
          }
        }

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: detail.tk.px(8)
          spacing: detail.tk.px(6)

          FeedbackLine {
            width: parent.width
            tk: detail.tk
            error: detail.sys.btError
            notice: detail.sys.btNotice
            busy: detail.sys.btBusyVerb !== ""
              ? (detail.sys.btBusyVerb === "pair" ? "Pairing…"
                : detail.sys.btBusyVerb === "connect" ? "Connecting…" : "Disconnecting…")
              : ""
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            maximumLineCount: 3
          }

          ActionChip {
            tk: detail.tk
            label: detail.sys.btEnabled ? "Bluetooth on" : "Bluetooth off"
            glyph: detail.sys.btEnabled ? "󰂱" : "󰂲"
            enabledChip: detail.sys.btAvailable
            onClicked: detail.sys.toggleBluetooth()
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        CardTitle {
          id: btListTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: detail.tk.cardPad
          tk: detail.tk
          text: "DEVICES"
        }

        Text {
          anchors.centerIn: parent
          visible: detail.sys.btDevices.length === 0 && detail.sys.btNearby.length === 0
          text: !detail.sys.btEnabled ? "Bluetooth is off" : "Looking for devices…"
          font.family: detail.tk.fontFamily
          font.pixelSize: detail.tk.tileLabelSize
          color: detail.tk.textFaint
        }

        // Paired devices and unpaired ones in range, in one list with a
        // divider. Discovery is on while this pane is open, which is what makes
        // a never-before-seen device appear here at all.
        ListView {
          anchors.top: btListTitle.bottom
          anchors.topMargin: detail.tk.px(5)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)
          anchors.bottomMargin: detail.tk.px(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          model: {
            var out = []
            var paired = detail.sys.btDevices
            for (var i = 0; i < paired.length; i++) out.push({ device: paired[i], header: "" })
            var near = detail.sys.btNearby
            for (var j = 0; j < near.length; j++)
              out.push({ device: near[j], header: j === 0 ? "IN RANGE" : "" })
            return out
          }

          delegate: Column {
            required property var modelData
            width: ListView.view.width
            spacing: 0

            CardTitle {
              visible: modelData.header !== ""
              tk: detail.tk
              text: modelData.header
              topPadding: detail.tk.px(6)
              leftPadding: detail.tk.px(8)
              bottomPadding: detail.tk.px(2)
            }

            IslandListRow {
              width: parent.width
              tk: detail.tk
              glyph: detail.sys.btGlyphFor(modelData.device)
              title: detail.sys.btLabel(modelData.device)
              selected: modelData.device.connected
              enabledRow: !detail.sys.btBusyAddress
                || detail.sys.btIsBusy(modelData.device)
              note: {
                var d = modelData.device
                if (detail.sys.btIsBusy(d))
                  return detail.sys.btBusyVerb === "pair" ? "Pairing…"
                    : detail.sys.btBusyVerb === "connect" ? "Connecting…" : "…"
                if (d.pairing) return "Pairing…"
                if (d.connected)
                  return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected"
                if (!d.paired && !d.bonded) return "Tap to pair"
                return ""
              }
              onActivated: detail.sys.activateDevice(modelData.device)
              // Right-click removes the pairing — destructive, so never the tap.
              onSecondary: if (modelData.device.paired || modelData.device.bonded)
                detail.sys.forgetDevice(modelData.device)
            }
          }
        }
      }
    }
  }

  // ----------------------------------------------------------- audio
  Component {
    id: audioBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.fill: parent
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(2)

          Text {
            text: detail.sys.muted ? "Muted" : detail.sys.volumePercent + "%"
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.muted ? detail.tk.textFaint : detail.tk.text
          }

          Item { width: 1; height: detail.tk.px(8) }

          // Drag or click anywhere on the track to set the level.
          Rectangle {
            id: track
            width: parent.width
            height: detail.tk.px(6)
            radius: height / 2
            color: detail.tk.meterTrack

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, detail.sys.volume))
              height: parent.height
              radius: parent.radius
              color: detail.sys.muted ? detail.tk.textFaint : detail.tk.text
              Behavior on width { NumberAnimation { duration: 90 } }
            }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -detail.tk.px(7)
              cursorShape: Qt.PointingHandCursor
              function apply(x) { detail.sys.setVolume(x / track.width) }
              onPressed: function(mouse) { apply(mouse.x) }
              onPositionChanged: function(mouse) { if (pressed) apply(mouse.x) }
              onWheel: function(wheel) {
                detail.sys.setVolume(detail.sys.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
              }
            }
          }

          Item { width: 1; height: detail.tk.px(8) }

          IslandListRow {
            width: parent.width
            tk: detail.tk
            glyph: detail.sys.muted ? "󰝟" : "󰕾"
            title: detail.sys.muted ? "Unmute" : "Mute"
            onActivated: detail.sys.toggleMute()
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        CardTitle {
          id: sinkTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: detail.tk.cardPad
          tk: detail.tk
          text: "OUTPUT"
        }

        ListView {
          anchors.top: sinkTitle.bottom
          anchors.topMargin: detail.tk.px(5)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: detail.tk.px(4)
          anchors.rightMargin: detail.tk.px(4)
          anchors.bottomMargin: detail.tk.px(6)
          clip: true
          model: detail.sys.sinks
          boundsBehavior: Flickable.StopAtBounds

          delegate: IslandListRow {
            required property var modelData
            width: ListView.view.width
            tk: detail.tk
            glyph: modelData === detail.sys.sink ? "󰕾" : "󰘄"
            title: detail.sys.sinkLabel(modelData)
            selected: modelData === detail.sys.sink
            note: modelData === detail.sys.sink ? "Active" : ""
            onActivated: detail.sys.selectSink(modelData)
          }
        }
      }
    }
  }

  // --------------------------------------------------------- battery
  // The shortest pane of the five: a level, a bar, and the five numbers UPower
  // actually reports for this battery. They come from the physical device now,
  // not from UPower's synthetic display device, which carried no model, no
  // health and no charge rate — that is why most of this read "—".
  Component {
    id: batteryBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(8)

          Text {
            text: detail.sys.batteryValue
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.cardValueSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: detail.sys.batteryLow ? detail.tk.accent : detail.tk.text
          }

          Rectangle {
            width: parent.width
            height: detail.tk.px(6)
            radius: height / 2
            color: detail.tk.meterTrack

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, detail.sys.batteryPercent / 100))
              height: parent.height
              radius: parent.radius
              color: detail.sys.batteryLow ? detail.tk.accent : detail.tk.text
              Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: detail.tk.springCurve } }
            }
          }

          Text {
            width: parent.width
            text: detail.sys.batteryDetail
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: detail.tk.fontFamily
            font.pixelSize: detail.tk.tileLabelSize
            renderType: Text.NativeRendering
            color: detail.tk.textDim
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(1)

          IslandRow {
            tk: detail.tk; width: parent.width; label: "State"
            value: detail.sys.batteryState
          }
          IslandRow {
            tk: detail.tk; width: parent.width
            label: detail.sys.charging ? "Time to full" : "Time left"
            value: detail.sys.batteryTime
          }
          IslandRow { tk: detail.tk; width: parent.width; label: "Draw"; value: detail.sys.batteryRate }
          IslandRow {
            tk: detail.tk; width: parent.width; label: "Health"
            value: detail.sys.batteryHealth >= 0 ? detail.sys.batteryHealth + "%" : ""
          }
          IslandRow { tk: detail.tk; width: parent.width; label: "Capacity"; value: detail.sys.batteryCapacity }
          IslandRow { tk: detail.tk; width: parent.width; label: "Cell"; value: detail.sys.batteryModel }
        }
      }
    }
  }

  // ---------------------------------------------------------- claude
  Component {
    id: claudeBody

    Row {
      spacing: detail.tk.cardGap

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.44
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: detail.tk.cardPad
          anchors.rightMargin: detail.tk.cardPad
          spacing: detail.tk.px(10)

          IslandMeter {
            width: parent.width
            tk: detail.tk
            label: detail.sys.claudeSessionLabel
            percent: detail.sys.claudePercent
            reset: detail.sys.claudeSessionReset
          }
          IslandMeter {
            width: parent.width
            visible: detail.sys.claudeHasWeekly
            tk: detail.tk
            label: detail.sys.claudeWeeklyLabel
            percent: detail.sys.claudeWeeklyPercent
            reset: detail.sys.claudeWeeklyReset
          }
        }
      }

      IslandCard {
        tk: detail.tk
        revealed: true
        width: (parent.width - detail.tk.cardGap) * 0.56
        height: parent.height

        Column {
          id: claudeStats
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: detail.tk.cardPad
          spacing: detail.tk.px(1)

          CardTitle { tk: detail.tk; text: "TODAY" }
          Item { width: 1; height: detail.tk.px(3) }
          IslandRow { tk: detail.tk; width: parent.width; label: "Prompts"; value: String(detail.sys.claudeTodayPrompts) }
          IslandRow { tk: detail.tk; width: parent.width; label: "Tokens"; value: detail.sys.compactNumber(detail.sys.claudeTodayTokens) }
        }

        // Seven days of token volume, each bar scaled to the busiest day.
        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: detail.tk.cardPad
          height: detail.tk.px(30)
          spacing: detail.tk.px(5)

          Repeater {
            model: detail.sys.claudeRecentDays

            delegate: Item {
              required property var modelData
              required property int index
              width: (parent.width - detail.tk.px(5) * 6) / 7
              height: parent.height

              readonly property real ratio: detail.sys.claudePeakDay > 0
                ? Number(modelData.messageCount || 0) / detail.sys.claudePeakDay : 0
              readonly property bool today: index === detail.sys.claudeRecentDays.length - 1

              Rectangle {
                anchors.bottom: dayLabel.top
                anchors.bottomMargin: detail.tk.px(3)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: Math.max(detail.tk.px(2), (parent.height - detail.tk.px(13)) * parent.ratio)
                radius: detail.tk.px(2)
                color: parent.today ? detail.tk.text : detail.tk.meterTrack
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: detail.tk.springCurve } }
              }

              Text {
                id: dayLabel
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(new Date(String(modelData.date)), "ddd").charAt(0)
                font.family: detail.tk.fontFamily
                font.pixelSize: detail.tk.tileLabelSize
                color: parent.today ? detail.tk.textDim : detail.tk.textFaint
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- shan shui
  Component {
    id: shanshuiBody

    Item {
      anchors.fill: parent

      Column {
        anchors.fill: parent
        spacing: detail.tk.px(8)

        // Playback and the wallpaper switch.
        Row {
          spacing: detail.tk.px(6)

          ActionChip {
            tk: detail.tk
            glyph: shan.on ? "󰸉" : "󰋩"
            label: shan.on ? "Static wallpaper" : "Paint wallpaper"
            onClicked: shan.ipc(shan.on ? "desligar" : "ligar")
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: shan.paused ? "󰐊" : "󰏤"
            label: shan.paused ? "Resume" : "Pause"
            onClicked: shan.ipc(shan.paused ? "continuar" : "pausar")
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: "󰒭"
            label: "Skip ahead"
            onClicked: shan.ipc("pular", 0.5)
          }
          ActionChip {
            tk: detail.tk
            enabledChip: shan.on
            glyph: "󰑓"
            label: "New landscape"
            onClicked: shan.ipc("nova")
          }
        }

        OptionRow {
          tk: detail.tk
          label: "SPEED"
          chips: Repeater {
            model: [{ v: 10, l: "10 min" }, { v: 5, l: "5 min" }, { v: 2, l: "2 min" },
                    { v: 1, l: "1 min" }, { v: 0.5, l: "30 s" }, { v: 0.25, l: "15 s" }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.minPorTela) === modelData.v
              onClicked: shan.set({ minPorTela: modelData.v })
            }
          }
        }

        OptionRow {
          tk: detail.tk
          label: "MOTION"
          chips: Repeater {
            model: [{ v: 6, l: "Light" }, { v: 12, l: "Normal" }, { v: 24, l: "Smooth" }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.fps) === modelData.v
              onClicked: shan.set({ fps: modelData.v })
            }
          }
        }

        // Curated looks: ink on paper. The OLED ones keep the paper truly
        // black, so most of the panel stays switched off.
        OptionRow {
          tk: detail.tk
          label: "LOOK"
          chips: [
            Repeater {
              model: [{ l: "Theme", t: "foreground", p: "background" },
                      { l: "Night silk", t: "#e8dcc4", p: "#000000" },
                      { l: "Cinnabar", t: "#e0503c", p: "#000000" },
                      { l: "Jade", t: "#6fbf9a", p: "#000000" },
                      { l: "Rice paper", t: "#2b2b2b", p: "#f2e8d5" }]
              ActionChip {
                required property var modelData
                tk: detail.tk
                label: modelData.l
                selected: shan.same(shan.opts.tinta, modelData.t) && shan.same(shan.opts.papel, modelData.p)
                onClicked: shan.set({ tinta: modelData.t, papel: modelData.p, inverter: false })
              }
            },
            ActionChip {
              tk: detail.tk
              glyph: "󰌁"
              label: "Invert"
              selected: shan.opts.inverter === true
              onClicked: shan.set({ inverter: !(shan.opts.inverter === true) })
            }
          ]
        }

        OptionRow {
          tk: detail.tk
          label: "INK"
          chips: [
            Repeater {
              model: ["#f2efe8", "#e8dcc4", "#c9955c", "#e6c15a", "#e0503c", "#e8a0b4", "#6fbf9a", "#7da6e8"]
              Swatch {
                required property string modelData
                tk: detail.tk
                hex: modelData
                selected: shan.same(shan.opts.tinta, modelData)
                onPicked: function(h) { shan.set({ tinta: h }) }
              }
            },
            HueBar {
              tk: detail.tk
              onPicked: function(h) { shan.set({ tinta: h }) }
            },
            HexField {
              tk: detail.tk
              current: /^#/.test(String(shan.opts.tinta)) ? shan.opts.tinta : ""
              onPicked: function(h) { shan.set({ tinta: h }) }
              onFocusChanged2: function(f) { detail.shanHexFocused = f }
            }
          ]
        }

        OptionRow {
          tk: detail.tk
          label: "PAPER"
          chips: [
            Repeater {
              model: ["#000000", "#0b0a08", "#10141f", "#1f150c", "#3a1414", "#e9dfc9", "#f2e8d5", "#f7f5f0"]
              Swatch {
                required property string modelData
                tk: detail.tk
                hex: modelData
                selected: shan.same(shan.opts.papel, modelData)
                onPicked: function(h) { shan.set({ papel: h }) }
              }
            },
            HueBar {
              tk: detail.tk
              saturation: 0.45
              lightness: 0.12
              onPicked: function(h) { shan.set({ papel: h }) }
            },
            HexField {
              tk: detail.tk
              current: /^#/.test(String(shan.opts.papel)) ? shan.opts.papel : ""
              onPicked: function(h) { shan.set({ papel: h }) }
              onFocusChanged2: function(f) { detail.shanHexFocused = f }
            }
          ]
        }

        // Where the front sits and how soft the brush is: the two knobs the
        // plugin's own menu does not expose.
        OptionRow {
          tk: detail.tk
          label: "BRUSH"
          chips: Repeater {
            model: [{ l: "Crisp", s: 20, g: 0.03 }, { l: "Ink", s: 40, g: 0.06 }, { l: "Wash", s: 90, g: 0.10 }]
            ActionChip {
              required property var modelData
              tk: detail.tk
              label: modelData.l
              selected: Number(shan.opts.suave) === modelData.s && Number(shan.opts.grao) === modelData.g
              onClicked: shan.set({ suave: modelData.s, grao: modelData.g })
            }
          }
        }
      }
    }
  }
}
