import QtQuick

// A selectable line in a detail view's list: glyph, name, trailing note.
Rectangle {
  id: row

  required property var tk
  property string glyph: ""
  property string title: ""
  property string note: ""
  property bool selected: false
  property bool enabledRow: true

  signal activated()
  // Right-click. Used for the destructive options — forget a network, remove a
  // pairing — so a mis-tap can never trigger one.
  signal secondary()

  height: tk.rowHeight
  radius: tk.px(8)
  color: mouse.pressed ? tk.cardPressed : (mouse.containsMouse ? tk.cardHover : "transparent")
  Behavior on color { ColorAnimation { duration: 120 } }
  opacity: enabledRow ? 1 : 0.4

  Text {
    id: mark
    anchors.left: parent.left
    anchors.leftMargin: row.tk.px(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.glyph
    font.family: row.tk.fontFamily
    font.pixelSize: row.tk.tileLabelSize
    color: row.selected ? row.tk.accent : row.tk.textDim
  }

  Text {
    anchors.left: mark.right
    anchors.leftMargin: row.tk.px(8)
    anchors.right: noteText.left
    anchors.rightMargin: row.tk.px(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.title
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: row.tk.fontFamily
    font.pixelSize: row.tk.tileValueSize
    font.weight: row.selected ? Font.DemiBold : Font.Normal
    renderType: Text.NativeRendering
    color: row.selected ? row.tk.text : row.tk.textDim
  }

  Text {
    id: noteText
    anchors.right: parent.right
    anchors.rightMargin: row.tk.px(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.note
    textFormat: Text.PlainText
    font.family: row.tk.fontFamily
    font.pixelSize: row.tk.tileLabelSize
    color: row.tk.textFaint
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: row.enabledRow
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) row.secondary()
      else row.activated()
    }
  }
}
