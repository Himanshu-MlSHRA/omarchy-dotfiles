import QtQuick

// One usage allowance: name, percentage, fill bar, and when it resets.
// Drawn only when the source actually reports a percentage — an empty bar
// would read as "nothing used" rather than "not known".
Item {
  id: meter

  required property var tk
  property string label: ""
  property string reset: ""
  property int percent: -1
  readonly property bool known: percent >= 0
  // Past this the allowance is worth noticing, so it takes the accent.
  property int warnAt: 80
  readonly property color fill: percent >= warnAt ? tk.accent : tk.text
  // Compact: the reset time moves up beside the percentage instead of taking
  // its own line under the bar (page 2's card is shorter).
  property bool compact: false

  implicitHeight: name.implicitHeight + tk.px(5) + track.height
                  + (compact ? 0 : tk.px(4) + resetText.implicitHeight)

  Text {
    id: name
    anchors.left: parent.left
    anchors.top: parent.top
    text: meter.label.toUpperCase()
    font.family: meter.tk.fontFamily
    font.pixelSize: meter.tk.cardTitleSize
    font.letterSpacing: 0.8
    color: meter.tk.textFaint
  }

  Text {
    anchors.right: pct.left
    anchors.rightMargin: meter.tk.px(8)
    anchors.baseline: name.baseline
    visible: meter.compact && meter.reset !== ""
    text: meter.reset.replace(/^resets in /, "")
    font.family: meter.tk.fontFamily
    font.pixelSize: meter.tk.tileLabelSize
    color: meter.tk.textFaint
  }

  Text {
    id: pct
    anchors.right: parent.right
    anchors.baseline: name.baseline
    text: meter.known ? meter.percent + "%" : "—"
    font.family: meter.tk.fontFamily
    font.pixelSize: meter.tk.tileValueSize
    font.weight: Font.DemiBold
    renderType: Text.NativeRendering
    color: meter.fill
    Behavior on color { ColorAnimation { duration: meter.tk.colorDuration } }
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: name.bottom
    anchors.topMargin: meter.tk.px(5)
    height: meter.tk.px(4)
    radius: height / 2
    color: meter.tk.meterTrack

    Rectangle {
      width: parent.width * (meter.known ? Math.max(0, Math.min(1, meter.percent / 100)) : 0)
      height: parent.height
      radius: parent.radius
      color: meter.fill
      Behavior on width {
        NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: meter.tk.springCurve }
      }
      Behavior on color { ColorAnimation { duration: meter.tk.colorDuration } }
    }
  }

  Text {
    id: resetText
    visible: !meter.compact
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: track.bottom
    anchors.topMargin: meter.tk.px(4)
    text: meter.reset
    elide: Text.ElideRight
    font.family: meter.tk.fontFamily
    font.pixelSize: meter.tk.tileLabelSize
    color: meter.tk.textFaint
  }
}
