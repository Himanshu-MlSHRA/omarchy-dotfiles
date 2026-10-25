import QtQuick

// The collapsed island's content: just the clock, in Maple Mono.
//
//            SAT · OCT 25 · 6:50 PM
//
// `sys` and `status` stay as properties so Bar.qml and anshu.menu's ghost pill
// can keep passing them; the compact pill reads neither.
Item {
  id: pill

  required property var tk
  property var sys: null
  property var status: null

  implicitWidth: clock.implicitWidth
  implicitHeight: tk.pillH

  IslandClock {
    id: clock
    anchors.centerIn: parent
    tk: pill.tk
  }
}
