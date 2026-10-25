import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// Coppernight × Nothing lock. A dark, dot-gridded page with a big dot-matrix
// (Doto) clock dead centre, a thin monospace status line across the top and
// a quiet pill field at the bottom; one red dot is the only colour.
// The whole page is a sheet over a snapshot of the desktop: it drops down
// over it on lock and slides up off it on unlock, revealing the desktop.
// Props, signals and the focus/sync logic are omarchy.lock's — Service.qml
// drives them — plus `unlocking` and the snapshot.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool unlocking: false
  property string snapshotPath: ""
  property int snapshotVersion: 0
  property bool aod: false
  property int fingerprintFailures: 0
  // Set for the short success beat between auth passing and the sheet lifting.
  property bool success: false

  property date now: new Date()
  property bool idle: false
  // 0 = sheet fully on screen, -1 = slid up off the top.
  property real sheet: 0

  // Nothing red; a theme can override it with `[lock] accent` in shell.toml.
  readonly property color accent: Color.pick("lock.accent", "#D71921")
  readonly property color ink: Color.lock.text
  readonly property string monoFamily: Style.font.family

  readonly property string placeholderText: "Enter password"
  readonly property int fieldWidth: 280
  readonly property int fieldHeight: 46
  readonly property int outlineThickness: 1
  readonly property int fieldFontSize: Math.round(Style.font.heading * 0.8)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.0)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.2)
  // Dot pitch of the clock: 13 rows tall, ~35 cells wide for "HH:MM".
  readonly property real clockCell: Math.max(10, Math.min(height * 0.3 / 13, width * 0.72 / 35))
  readonly property color aodInk: "#E9E3D3"
  readonly property int statusFontSize: Math.max(12, Math.round(height * 0.0125))
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  // (The fingerprint badge now sits under the field, so nothing to reserve.)
  readonly property real fingerprintReserve: 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: success
    ? Border.surfaceSpec("lock", "border-active", root.ink, root.outlineThickness + 1, "border-alpha")
    : errorState
    ? Border.surfaceSpec("lock", "border-error", root.accent, root.outlineThickness, "border-alpha")
    : (passwordInput.text.length > 0 || authenticatingPassword)
      ? Border.surfaceSpec("lock", "border-active", Util.alpha(root.ink, 0.85), root.outlineThickness, "border-alpha")
      : Border.surfaceSpec("lock", "border", Util.alpha(root.ink, 0.25), root.outlineThickness, "border-alpha")

  // ---------------------------------------------------------------- info
  // Weather comes from the island's Open-Meteo cache, so the lock never hits
  // the network itself; anything older than three hours is hidden.
  property var weather: null
  readonly property bool hasWeather: !!weather && (Date.now() - Number(weather.at || 0)) < 3 * 3600 * 1000

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!(battery && battery.isPresent)
  readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
  readonly property int batteryPercent: hasBattery ? Math.round(Math.max(0, Math.min(1, battery.percentage)) * 100) : 0

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts an image by appending `?v=`. Adding a query string keeps
  // Image's loader happy while forcing it to reload when the file changes.
  function fileUrl(path, version) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + version
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  // Any sign of life: undim and restart the idle countdown.
  function poke() {
    idle = false
    if (inputEnabled && !unlocking) idleTimer.restart()
  }

  function playIntro() {
    outro.stop()
    success = false
    poke()
    console.log("anshu.lock intro: " + (snapshot.status === Image.Ready ? "drop" : "fade (no snapshot: " + snapshotPath + ")"))
    if (snapshot.status === Image.Ready) {
      dropIn.restart()
    } else {
      sheet = 0
      fadeIn.restart()
    }
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    poke()
  }
  onFailedAttemptsChanged: if (failedAttempts > 0) { poke(); shake.restart(); fieldFlash.play(root.accent) }
  onFingerprintFailuresChanged: if (fingerprintFailures > 0) { poke(); shake.restart(); fpBadge.fail() }
  onSuccessChanged: if (success) { fieldFlash.play(root.ink); fpBadge.pass() }
  onVisibleChanged: if (visible) playIntro()
  onUnlockingChanged: {
    if (unlocking) {
      idleTimer.stop()
      dropIn.stop()
      fadeIn.stop()
      outro.restart()
    } else {
      playIntro()
    }
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    playIntro()
  }

  // Ticks on the second boundary so the minute flips exactly on time.
  Timer {
    interval: 1000 - (root.now.getMilliseconds() % 1000) + 5
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  Timer {
    id: idleTimer
    interval: 12000
    onTriggered: root.idle = !root.errorState && passwordInput.text.length === 0 && !root.authenticatingPassword
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/island-weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.weather = JSON.parse(text()) } catch (e) { root.weather = null }
    }
    onFileChanged: reload()
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: root.monoFamily
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  // Lock in with a snapshot: the sheet drops over the desktop from the top.
  SequentialAnimation {
    id: dropIn
    PropertyAction { target: content; property: "opacity"; value: 0 }
    NumberAnimation { target: root; property: "sheet"; from: -1; to: 0; duration: 540; easing.type: Easing.OutCubic }
    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
  }

  // Lock in without one (preview, or a capture that missed): just fade up.
  NumberAnimation { id: fadeIn; target: content; property: "opacity"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }

  // Unlock: a short success beat (check pops, halo + fingerprint ripple),
  // then the UI fades and the whole sheet slides up and away.
  SequentialAnimation {
    id: outro
    PropertyAction { target: root; property: "success"; value: true }
    PauseAnimation { duration: 260 }
    NumberAnimation { target: content; property: "opacity"; to: 0; duration: 120 }
    NumberAnimation { target: root; property: "sheet"; to: -1; duration: 470; easing.type: Easing.InOutCubic }
  }

  // Hand-drawn 7×13 dot-matrix digits, Nothing-style: one-dot strokes on a
  // faint full grid. '#' is a lit dot.
  readonly property var glyphs: ({
    "0": ["..###..", ".#...#.", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", ".#...#.", "..###.."],
    "1": ["...#...", "..##...", ".#.#...", "...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "...#..."],
    "2": ["..###..", ".#...#.", "#.....#", "......#", "......#", ".....#.", "....#..", "...#...", "..#....", ".#.....", "#......", "#......", "#######"],
    "3": ["..###..", ".#...#.", "#.....#", "......#", "......#", ".....#.", "..###..", ".....#.", "......#", "......#", "#.....#", ".#...#.", "..###.."],
    "4": [".....#.", "....##.", "...#.#.", "...#.#.", "..#..#.", "..#..#.", ".#...#.", ".#...#.", "#....#.", "#######", ".....#.", ".....#.", ".....#."],
    "5": ["#######", "#......", "#......", "#......", "#.###..", "##...#.", "......#", "......#", "......#", "......#", "#.....#", ".#...#.", "..###.."],
    "6": ["...##..", "..#....", ".#.....", "#......", "#......", "#.###..", "##...#.", "#.....#", "#.....#", "#.....#", "#.....#", ".#...#.", "..###.."],
    "7": ["#######", "......#", "......#", ".....#.", ".....#.", "....#..", "....#..", "....#..", "...#...", "...#...", "...#...", "...#...", "...#..."],
    "8": ["..###..", ".#...#.", "#.....#", "#.....#", "#.....#", ".#...#.", "..###..", ".#...#.", "#.....#", "#.....#", "#.....#", ".#...#.", "..###.."],
    "9": ["..###..", ".#...#.", "#.....#", "#.....#", "#.....#", "#.....#", ".#...##", "..###.#", "......#", "......#", ".....#.", "....#..", "..##..."]
  })

  // One dot-matrix digit. On change the dots re-light in a quick top-down
  // wave instead of snapping.
  component DotDigit: Grid {
    id: dd
    property var glyph: []
    property real cell: 20
    property color ink: "white"
    property real gridAlpha: 0.025

    columns: 7
    Repeater {
      model: 91
      Item {
        required property int index
        readonly property int row: Math.floor(index / 7)
        readonly property bool lit: dd.glyph.length === 13 && dd.glyph[row].charAt(index % 7) === "#"
        width: dd.cell
        height: dd.cell

        Rectangle {
          anchors.centerIn: parent
          width: Math.round(dd.cell * 0.74)
          height: width
          radius: width / 2
          color: dd.ink
          opacity: parent.lit ? 1 : dd.gridAlpha
          scale: parent.lit ? 1 : 0.7
          Behavior on opacity {
            SequentialAnimation {
              PauseAnimation { duration: row * 22 }
              NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
          }
          Behavior on scale {
            SequentialAnimation {
              PauseAnimation { duration: row * 22 }
              NumberAnimation { duration: 300; easing.type: Easing.OutBack }
            }
          }
        }
      }
    }
  }

  // HH:MM built from DotDigits; the colon is two dots on rows 3 and 9.
  component DotClock: Row {
    id: dc
    property date time: new Date()
    property real cell: 20
    property color ink: "white"
    property color colonInk: "red"
    property real gridAlpha: 0.025
    property bool breathe: true
    property var glyphs: ({})
    readonly property string hhmm: Qt.formatDateTime(time, "HHmm")

    spacing: Math.round(cell * 1.4)

    DotDigit { glyph: dc.glyphs[dc.hhmm.charAt(0)] || []; cell: dc.cell; ink: dc.ink; gridAlpha: dc.gridAlpha }
    DotDigit { glyph: dc.glyphs[dc.hhmm.charAt(1)] || []; cell: dc.cell; ink: dc.ink; gridAlpha: dc.gridAlpha }
    Item {
      width: dc.cell
      height: dc.cell * 13
      SequentialAnimation on opacity {
        running: dc.breathe && dc.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
      }
      Repeater {
        model: [3, 9]
        Rectangle {
          required property int modelData
          x: (dc.cell - width) / 2
          y: modelData * dc.cell + (dc.cell - height) / 2
          width: Math.round(dc.cell * 0.74)
          height: width
          radius: width / 2
          color: dc.colonInk
        }
      }
    }
    DotDigit { glyph: dc.glyphs[dc.hhmm.charAt(2)] || []; cell: dc.cell; ink: dc.ink; gridAlpha: dc.gridAlpha }
    DotDigit { glyph: dc.glyphs[dc.hhmm.charAt(3)] || []; cell: dc.cell; ink: dc.ink; gridAlpha: dc.gridAlpha }
  }

  // Monospace caps label used across the status line.
  component Label: Text {
    textFormat: Text.PlainText
    color: Color.lock.text
    font.family: Style.font.family
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 2
  }

  // ------------------------------------------------------- desktop beneath
  // Only shown while the sheet is moving, so the desktop is never visible
  // behind a settled lock screen.
  Rectangle {
    anchors.fill: parent
    color: "black"
    visible: root.sheet < 0

    Image {
      id: snapshot
      anchors.fill: parent
      source: root.fileUrl(root.snapshotPath, root.snapshotVersion)
      fillMode: Image.PreserveAspectCrop
      asynchronous: false
      cache: false
      // Recedes and dims as the sheet covers it; comes forward as it leaves.
      scale: 0.96 - 0.04 * root.sheet
      opacity: 0.5 - 0.5 * root.sheet
    }
  }

  // --------------------------------------------------------------- sheet
  Rectangle {
    id: page
    width: parent.width
    height: parent.height
    y: root.sheet * height
    color: "#050505"
    clip: true

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath, root.backgroundVersion) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
      visible: false
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      visible: wallpaper.status === Image.Ready
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      blurMultiplier: 1.4
      brightness: -0.38
      saturation: -0.35
    }

    // Nothing's dot grid, painted once per size.
    Canvas {
      id: grid
      anchors.fill: parent
      opacity: 0.09
      renderStrategy: Canvas.Cooperative
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = "#ffffff"
        var step = 18
        for (var y = step / 2; y < height; y += step) {
          for (var x = step / 2; x < width; x += step) {
            ctx.beginPath()
            ctx.arc(x, y, 1.1, 0, 2 * Math.PI)
            ctx.fill()
          }
        }
      }
    }

    // Soft vignette so the edges sink into black.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
        GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.1) }
        GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.1) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
      }
    }
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: root.idle ? 0.35 : 0
      Behavior on opacity { NumberAnimation { duration: root.idle ? 900 : 220; easing.type: Easing.InOutCubic } }
    }

    // Sheet edge: a grab handle that reads as "this lifts away".
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 10
      width: 110
      height: 4
      radius: 2
      color: Util.alpha(root.ink, root.idle ? 0.12 : 0.3)
      Behavior on color { ColorAnimation { duration: 400 } }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.poke(); root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: { root.poke(); root.wakeRequested() }
    }

    Item {
      id: content
      anchors.fill: parent
      opacity: 0

      // ------------------------------------------------------ status line
      Item {
        id: status
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.035)
        anchors.leftMargin: Math.round(root.width * 0.04)
        anchors.rightMargin: Math.round(root.width * 0.04)
        height: Math.round(root.statusFontSize * 1.6)
        opacity: root.idle ? 0.45 : 0.85
        Behavior on opacity { NumberAnimation { duration: 600 } }

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(root.statusFontSize * 0.9)

          // The red dot: steady normally, blinks while the password is checked.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(root.statusFontSize * 0.6)
            height: width
            radius: width / 2
            color: root.accent
            SequentialAnimation on opacity {
              running: root.authenticatingPassword
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: 0.15; duration: 260 }
              NumberAnimation { to: 1; duration: 260 }
            }
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(root.now, "ddd  d MMM")
            font.pixelSize: root.statusFontSize
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(root.statusFontSize * 2.2)

          Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasWeather
            text: root.hasWeather ? Math.round(root.weather.temp) + "°  " + root.weather.condition : ""
            font.pixelSize: root.statusFontSize
          }

          // Battery: just the number; red when low.
          Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasBattery
            text: (root.charging ? "⚡" : "") + root.batteryPercent + "%"
            color: root.batteryPercent <= 20 && !root.charging ? root.accent : root.ink
            font.pixelSize: root.statusFontSize
          }
        }
      }

      // ----------------------------------------------------------- clock
      DotClock {
        id: clockRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Math.round(root.height * 0.04)
        time: root.now
        cell: root.clockCell
        ink: root.ink
        colonInk: root.accent
        glyphs: root.glyphs
        opacity: root.idle ? 0.75 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }
      }

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clockRow.bottom
        anchors.topMargin: Math.round(root.clockCell * 1.4)
        text: Qt.formatDateTime(root.now, "dddd")
        font.pixelSize: Math.round(root.statusFontSize * 1.15)
        font.letterSpacing: 6
        opacity: root.idle ? 0.35 : 0.55
        Behavior on opacity { NumberAnimation { duration: 600 } }
      }

      // ------------------------------------------------------------ auth
      Column {
        id: authBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shakeOffset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.09) + (root.idle ? -14 : 0)
        spacing: Math.round(root.statusFontSize * 1.2)
        opacity: root.idle ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.idle ? 700 : 200; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: root.idle ? 700 : 240; easing.type: Easing.OutCubic } }

        property real shakeOffset: 0

        SequentialAnimation {
          id: shake
          NumberAnimation { target: authBlock; property: "shakeOffset"; to: -10; duration: 45; easing.type: Easing.OutQuad }
          NumberAnimation { target: authBlock; property: "shakeOffset"; to: 9; duration: 70; easing.type: Easing.InOutQuad }
          NumberAnimation { target: authBlock; property: "shakeOffset"; to: -6; duration: 60; easing.type: Easing.InOutQuad }
          NumberAnimation { target: authBlock; property: "shakeOffset"; to: 3; duration: 50; easing.type: Easing.InOutQuad }
          NumberAnimation { target: authBlock; property: "shakeOffset"; to: 0; duration: 40; easing.type: Easing.OutQuad }
        }

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.fieldWidth
          height: root.fieldHeight

        // Halo that flashes red on a wrong password, off-white on success.
        Rectangle {
          id: fieldFlash
          anchors.fill: parent
          anchors.margins: -5
          radius: height / 2
          color: "transparent"
          border.width: 5
          opacity: 0
          function play(c) { border.color = c; flashAnim.restart() }
          SequentialAnimation {
            id: flashAnim
            NumberAnimation { target: fieldFlash; property: "opacity"; from: 0; to: 0.55; duration: 90 }
            NumberAnimation { target: fieldFlash; property: "opacity"; to: 0; duration: 650; easing.type: Easing.OutCubic }
          }
        }

        BorderSurface {
          id: inputField
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.45)
          borderSpec: root.inputBorderSpec
          radius: height / 2
          clip: true

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.topMargin: inputField.borderTop
            // Reserve the fingerprint icon's width on both sides so the centered
            // dots stay symmetric and never slide under the icon as they grow.
            anchors.rightMargin: inputField.borderRight + 20 + root.fingerprintReserve
            anchors.bottomMargin: inputField.borderBottom
            anchors.leftMargin: inputField.borderLeft + 20 + root.fingerprintReserve
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            opacity: root.success ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: root.ink
            selectionColor: Color.lock.selection
            selectedTextColor: root.ink
            font.family: root.monoFamily
            font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
            font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
            cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
            cursorDelegate: Rectangle {
              width: 2
              color: root.accent
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) {
                root.poke()
                root.wakeRequested()
              }
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: {
              var submitted = root.passwordText
              root.passwordTextEdited("")
              if (submitted.length > 0) root.submitPassword(submitted)
            }

            Keys.onPressed: function(event) {
              root.poke()
              root.wakeRequested()
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }

          Label {
            anchors.fill: passwordInput
            text: root.authenticatingPassword ? "Checking" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
            visible: passwordInput.text.length === 0 && !root.success
            color: root.failureMessage.length > 0 && !root.authenticatingPassword ? root.accent : Util.alpha(root.ink, root.authenticatingPassword ? 0.9 : 0.5)
            font.pixelSize: root.fieldFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Success: a check pops into the field.
          Text {
            anchors.centerIn: parent
            text: "󰄬"
            color: root.ink
            font.family: root.monoFamily
            font.pixelSize: Math.round(root.fieldFontSize * 1.6)
            opacity: root.success ? 1 : 0
            scale: root.success ? 1 : 0.3
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
          }
        }
        }

        // Fingerprint badge: breathes while the sensor is listening, wiggles
        // red with a ripple on a miss, pops with an off-white ripple on success.
        Item {
          id: fpBadge
          objectName: "fingerprintIndicator"
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.fingerprintConfigured
          width: 52
          height: 52

          property real wiggle: 0
          readonly property bool failing: failAnim.running
          readonly property color tone: root.success ? root.ink : failing ? root.accent : Util.alpha(root.ink, 0.6)

          function fail() { ripple.border.color = root.accent; rippleAnim.restart(); failAnim.restart() }
          function pass() { if (!visible) return; ripple.border.color = root.ink; rippleAnim.restart() }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: Util.alpha(fpBadge.tone, root.success || fpBadge.failing ? 0.9 : 0.22)
            Behavior on border.color { ColorAnimation { duration: 180 } }
          }

          Rectangle {
            id: ripple
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            opacity: 0
          }
          ParallelAnimation {
            id: rippleAnim
            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.1; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: ripple; property: "opacity"; from: 0.85; to: 0; duration: 700; easing.type: Easing.OutCubic }
          }

          Text {
            id: fpGlyph
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: fpBadge.wiggle
            text: "󰈷"
            color: fpBadge.tone
            font.family: root.monoFamily
            font.pixelSize: 26
            scale: root.success ? 1.18 : 1
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
            SequentialAnimation on opacity {
              running: fpBadge.visible && !root.success && !fpBadge.failing && !root.aod && root.visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.45; duration: 1400; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
            }
          }

          SequentialAnimation {
            id: failAnim
            PropertyAction { target: fpGlyph; property: "opacity"; value: 1 }
            NumberAnimation { target: fpBadge; property: "wiggle"; to: -6; duration: 50 }
            NumberAnimation { target: fpBadge; property: "wiggle"; to: 6; duration: 80 }
            NumberAnimation { target: fpBadge; property: "wiggle"; to: -4; duration: 70 }
            NumberAnimation { target: fpBadge; property: "wiggle"; to: 2; duration: 60 }
            NumberAnimation { target: fpBadge; property: "wiggle"; to: 0; duration: 50 }
            PauseAnimation { duration: 900 }
          }
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.success ? "Unlocked"
            : fpBadge.failing ? "Not recognised"
            : root.fingerprintConfigured ? "Touch to unlock" : "Type to unlock"
          color: fpBadge.failing ? root.accent : Util.alpha(root.ink, root.success ? 0.8 : 0.4)
          opacity: root.errorState && !fpBadge.failing ? 0 : 1
          font.pixelSize: Math.round(root.statusFontSize * 0.85)
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }
      }
    }
  }

  // ------------------------------------------------------- always-on display
  // Pure black with just the clock in dim off-white (no grid, no red), drifting
  // a few pixels every minute so nothing burns in. Any input wakes it.
  Rectangle {
    id: aodLayer
    anchors.fill: parent
    color: "black"
    opacity: root.aod && !root.unlocking ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.aod ? 900 : 260; easing.type: Easing.InOutCubic } }

    property point drift: Qt.point(0, 0)
    Timer {
      interval: 60000
      repeat: true
      running: root.aod
      onTriggered: aodLayer.drift = Qt.point(Math.round((Math.random() * 2 - 1) * 14), Math.round((Math.random() * 2 - 1) * 14))
    }

    DotClock {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: aodLayer.drift.x
      anchors.verticalCenterOffset: aodLayer.drift.y - Math.round(root.height * 0.04)
      time: root.now
      cell: root.clockCell
      ink: root.aodInk
      colonInk: root.aodInk
      gridAlpha: 0
      breathe: false
      glyphs: root.glyphs
      opacity: 0.7
    }
  }
}
