import QtQuick
import Quickshell

// Collapsed content: WED · SEP 23 · 6:50 PM
//
// Three runs rather than one formatted string, so the time can carry the
// emphasis and the separators can sit back without fighting it. SystemClock
// at minute precision means one property update a minute — no per-second timer.
Row {
  id: clock

  required property var tk

  spacing: tk.px(9)

  SystemClock {
    id: sysClock
    precision: SystemClock.Minutes
  }

  readonly property date now: sysClock.date

  component Run: Text {
    required property var tk
    textFormat: Text.PlainText
    font.family: "Maple Mono NF"
    font.pixelSize: tk.clockSize
    font.letterSpacing: tk.clockSpacing
    renderType: Text.NativeRendering
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }

  Run {
    tk: clock.tk
    text: Qt.formatDateTime(clock.now, "ddd").toUpperCase()
    color: clock.tk.textDim
  }
  Run {
    tk: clock.tk
    text: "·"
    color: clock.tk.textFaint
  }
  Run {
    tk: clock.tk
    text: Qt.formatDateTime(clock.now, "MMM d").toUpperCase()
    color: clock.tk.textDim
  }
  Run {
    tk: clock.tk
    text: "·"
    color: clock.tk.textFaint
  }
  Run {
    tk: clock.tk
    text: Qt.formatDateTime(clock.now, "h:mm AP")
    color: clock.tk.text
    font.weight: Font.DemiBold
  }
}
