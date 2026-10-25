import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris

// Now playing, after Panacea's media card: the cover, title in bold, artist
// muted, transport on the right and a seek bar you can click or drag. Behind it
// all the cover itself, blurred and faint, so the card takes the colour of the
// record (the "see-through" look).
//
// Nothing playing: one line and a button that opens Spotify.
IslandCard {
  id: media

  property bool active: false     // page visible: only then poll position

  // Prefer whatever is actually playing; otherwise Spotify; otherwise the last
  // player still around, so a paused track stays one click from resuming.
  readonly property var players: Mpris.players.values
  readonly property var player: {
    var list = players || []
    for (var i = 0; i < list.length; i++) if (list[i].isPlaying) return list[i]
    for (i = 0; i < list.length; i++) if (/spotify/i.test(list[i].identity || "")) return list[i]
    return list.length > 0 ? list[list.length - 1] : null
  }
  readonly property bool hasPlayer: !!player
  readonly property string art: hasPlayer ? (player.trackArtUrl || "") : ""

  // MPRIS does not push position; read it while playing and visible.
  property real pos: 0
  property bool dragging: false
  Timer {
    interval: 500
    repeat: true
    triggeredOnStart: true
    running: media.active && media.hasPlayer && media.player.isPlaying && !media.dragging
    onTriggered: { media.player.positionChanged(); media.pos = media.player.position }
  }
  onPlayerChanged: pos = hasPlayer ? player.position : 0

  function clock(sec) {
    sec = Math.max(0, Math.floor(sec || 0))
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
  }
  readonly property real length: hasPlayer && player.lengthSupported ? player.length : 0
  readonly property real frac: length > 0 ? Math.max(0, Math.min(1, pos / length)) : 0

  clip: true

  // ------------------------------------------------------------ backdrop
  Item {
    id: backdrop
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Image {
      id: backdropArt
      anchors.fill: parent
      anchors.margins: -media.tk.px(30)
      source: media.art
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 96
      sourceSize.height: 96
    }
  }
  Item {
    id: backdropMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle { anchors.fill: parent; radius: media.radius; color: "#ffffff" }
  }
  MultiEffect {
    anchors.fill: parent
    source: backdrop
    blurEnabled: true
    blurMax: 48
    blur: 1.0
    saturation: 0.15
    maskEnabled: true
    maskSource: backdropMask
    opacity: backdropArt.status === Image.Ready ? (media.tk.light ? 0.30 : 0.38) : 0
    Behavior on opacity { NumberAnimation { duration: media.tk.colorDuration } }
  }

  // ------------------------------------------------------------- content
  // Panacea's media card, compact: [cover | title / artist | ⏮ ⏯ ⏭] on top,
  // and under it the seek bar drawn as an equaliser — the played part lit,
  // the rest dim. Click or drag anywhere on it to seek.
  Item {
    anchors.fill: parent
    anchors.margins: media.tk.cardPad

    Rectangle {
      id: cover
      anchors.left: parent.left
      anchors.top: parent.top
      width: media.tk.px(44)
      height: width
      radius: media.tk.px(10)
      color: media.tk.card

      Image {
        id: coverArt
        anchors.fill: parent
        source: media.art
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 140
        visible: false
        layer.enabled: true
      }
      Item {
        id: coverMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: cover.radius; color: "#ffffff" }
      }
      MultiEffect {
        anchors.fill: parent
        source: coverArt
        maskEnabled: true
        maskSource: coverMask
        visible: coverArt.status === Image.Ready
      }
      Text {
        anchors.centerIn: parent
        visible: coverArt.status !== Image.Ready
        text: "󰝚"
        font.family: media.tk.fontFamily
        font.pixelSize: media.tk.tileIconSize + 2
        color: media.tk.textFaint
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: media.hasPlayer ? media.player.togglePlaying() : media.openSpotify()
      }
    }

    Column {
      anchors.left: cover.right
      anchors.leftMargin: media.tk.px(10)
      anchors.right: transport.visible ? transport.left : parent.right
      anchors.rightMargin: media.tk.px(6)
      anchors.verticalCenter: cover.verticalCenter
      spacing: media.tk.px(2)

      Text {
        width: parent.width
        text: media.hasPlayer ? (media.player.trackTitle || "Unknown track") : "Nothing playing"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: media.tk.fontFamily
        font.pixelSize: media.tk.tileValueSize + 1
        font.weight: Font.Bold
        color: media.hasPlayer ? media.tk.text : media.tk.textDim
      }
      Text {
        width: parent.width
        text: media.hasPlayer ? (media.player.trackArtist || media.player.identity || "") : "Spotify is closed"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: media.tk.fontFamily
        font.pixelSize: media.tk.tileLabelSize
        color: media.tk.textDim
      }
    }

    // transport: two ghost buttons around a filled one, as in Panacea
    Row {
      id: transport
      anchors.right: parent.right
      anchors.verticalCenter: cover.verticalCenter
      spacing: media.tk.px(3)
      visible: media.hasPlayer

      Repeater {
        model: [
          { glyph: "󰒮", act: "prev" },
          { glyph: media.hasPlayer && media.player.isPlaying ? "󰏤" : "󰐊", act: "toggle" },
          { glyph: "󰒭", act: "next" }
        ]
        delegate: Rectangle {
          required property var modelData
          readonly property bool primary: modelData.act === "toggle"
          anchors.verticalCenter: parent.verticalCenter
          width: primary ? media.tk.px(34) : media.tk.px(28)
          height: width
          radius: width / 2
          color: primary ? (ctl.pressed ? media.tk.textDim : media.tk.text)
               : ctl.pressed ? media.tk.cardPressed : ctl.containsMouse ? media.tk.cardHover : media.tk.card
          scale: ctl.pressed ? 0.92 : 1
          Behavior on color { ColorAnimation { duration: media.tk.hoverDuration } }
          Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
          Text {
            anchors.centerIn: parent
            text: modelData.glyph
            font.family: media.tk.fontFamily
            font.pixelSize: parent.primary ? media.tk.tileIconSize + 1 : media.tk.tileIconSize - 1
            color: parent.primary ? media.tk.pillText : media.tk.text
          }
          MouseArea {
            id: ctl
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var p = media.player
              if (!p) return
              if (modelData.act === "prev" && p.canGoPrevious) p.previous()
              else if (modelData.act === "next" && p.canGoNext) p.next()
              else if (modelData.act === "toggle" && p.canTogglePlaying) p.togglePlaying()
            }
          }
        }
      }
    }

    // Idle: open Spotify.
    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      visible: !media.hasPlayer
      width: openRow.implicitWidth + media.tk.px(22)
      height: media.tk.px(28)
      radius: height / 2
      color: openMouse.pressed ? media.tk.cardPressed : openMouse.containsMouse ? media.tk.cardHover : media.tk.fieldBg
      Behavior on color { ColorAnimation { duration: media.tk.hoverDuration } }
      Row {
        id: openRow
        anchors.centerIn: parent
        spacing: media.tk.px(7)
        Text { anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: media.tk.fontFamily; font.pixelSize: media.tk.tileIconSize; color: media.tk.text }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Open Spotify"; font.family: media.tk.fontFamily; font.pixelSize: media.tk.tileLabelSize; font.weight: Font.Bold; color: media.tk.text }
      }
      MouseArea { id: openMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: media.openSpotify() }
    }

    // -------- equaliser seek (Panacea's WaveBars, without needing cava) ----
    // Each track gets its own fixed bar profile (seeded from the title), and
    // while it plays the bars breathe gently. Played bars are lit, the rest
    // dim; a few quiet ones are drawn as dots like Panacea's.
    Item {
      id: wave
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: cover.bottom
      anchors.topMargin: media.tk.px(10)
      anchors.bottom: times.top
      anchors.bottomMargin: media.tk.px(2)
      visible: media.hasPlayer && media.length > 0

      readonly property int barW: media.tk.px(4)
      readonly property int gap: media.tk.px(3)
      readonly property int count: Math.max(8, Math.floor((width + gap) / (barW + gap)))
      property real phase: 0
      NumberAnimation on phase {
        from: 0; to: Math.PI * 2; duration: 2400; loops: Animation.Infinite
        running: wave.visible && media.active && media.hasPlayer && media.player.isPlaying
      }

      function seed(str) {
        var h = 2166136261
        for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = (h * 16777619) >>> 0 }
        return h
      }
      readonly property var profile: {
        var t = media.hasPlayer ? (media.player.trackTitle || "") + (media.player.trackArtist || "") : ""
        var h = seed(t), out = []
        for (var i = 0; i < count; i++) {
          h = (h * 1103515245 + 12345) >>> 0
          var r = (h % 1000) / 1000
          // smooth it a little so it reads as a song, not noise
          var prev = i > 0 ? out[i - 1] : r
          out.push(0.15 + 0.85 * (r * 0.6 + prev * 0.4))
        }
        return out
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: wave.gap
        Repeater {
          model: wave.count
          delegate: Rectangle {
            required property int index
            readonly property real base: wave.profile[index] || 0.3
            readonly property real lvl: Math.max(0.12, Math.min(1, base * (0.82 + 0.18 * Math.sin(wave.phase + index * 0.55))))
            readonly property bool dot: base < 0.3
            readonly property bool played: (index + 0.5) / wave.count <= media.frac
            width: wave.barW
            height: dot ? wave.barW : Math.max(wave.barW, Math.round(wave.height * lvl))
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: played ? media.tk.text : media.tk.meterTrack
            opacity: played ? 1 : (seekMouse.containsMouse ? 0.9 : 0.75)
            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }
      }

      // the drag thumb Panacea shows on hover
      Rectangle {
        visible: seekMouse.containsMouse || seekMouse.pressed
        x: Math.round(wave.width * media.frac) - width / 2
        width: seekMouse.pressed ? 3 : 2
        height: wave.height
        radius: 1
        color: media.tk.text
      }

      MouseArea {
        id: seekMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: media.hasPlayer && media.player.canSeek
        function fracAt(x) { return Math.max(0, Math.min(1, x / wave.width)) }
        onPressed: function(m) { media.dragging = true; media.pos = fracAt(m.x) * media.length }
        onPositionChanged: function(m) { if (pressed) media.pos = fracAt(m.x) * media.length }
        onReleased: { if (media.player) media.player.position = media.pos; media.dragging = false }
        onCanceled: media.dragging = false
      }
    }

    Item {
      id: times
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: media.tk.px(12)
      visible: wave.visible
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: media.clock(media.pos)
        font.family: media.tk.fontFamily
        font.pixelSize: media.tk.cardTitleSize
        font.features: { "tnum": 1 }
        color: media.tk.textDim
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: media.clock(media.length)
        font.family: media.tk.fontFamily
        font.pixelSize: media.tk.cardTitleSize
        font.features: { "tnum": 1 }
        color: media.tk.textFaint
      }
    }
  }

  function openSpotify() {
    Quickshell.execDetached(["omarchy-launch-or-focus", "spotify"])
  }
}
