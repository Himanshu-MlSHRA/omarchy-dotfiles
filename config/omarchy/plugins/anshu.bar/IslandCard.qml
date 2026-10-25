import QtQuick

// A content card inside the open island: black lifted a few percent, softly
// rounded, no border. Atoll builds its panels out of these, and they are what
// stop a large black surface from reading as an empty void.
Rectangle {
  id: card

  required property var tk
  property int index: 0
  property bool revealed: false
  property bool interactive: false
  property bool hot: false
  property bool down: false

  radius: tk.cardRadius
  color: down ? tk.cardPressed : (interactive && hot ? tk.cardHover : tk.card)
  Behavior on color { ColorAnimation { duration: card.tk.hoverDuration; easing.type: Easing.OutCubic } }

  // Panacea's hairline edge; it brightens on hover so a pressable card says so.
  border.width: 1
  border.color: interactive && hot ? tk.cardPressed : tk.line
  Behavior on border.color { ColorAnimation { duration: card.tk.hoverDuration } }

  // Panacea: the page arrives as one — every card fades with it (animFast),
  // no per-card slide or scale.
  opacity: revealed ? 1 : 0

  Behavior on opacity {
    SequentialAnimation {
      PauseAnimation { duration: card.revealed ? card.tk.contentInDelay + card.index * card.tk.stagger : 0 }
      NumberAnimation {
        duration: card.revealed ? card.tk.contentInDuration : card.tk.contentOutDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: card.tk.fadeCurve
      }
    }
  }
}
