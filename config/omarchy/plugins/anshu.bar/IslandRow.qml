import QtQuick

// A label/value line inside a detail view.
Item {
  id: row
  required property var tk
  property string label: ""
  property string value: ""
  height: tk.px(18)

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    font.family: row.tk.fontFamily
    font.pixelSize: row.tk.tileLabelSize
    color: row.tk.textFaint
  }
  Text {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.horizontalCenter
    horizontalAlignment: Text.AlignRight
    text: row.value === "" ? "—" : row.value
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: row.tk.fontFamily
    font.pixelSize: row.tk.tileLabelSize
    renderType: Text.NativeRendering
    color: row.tk.textDim
  }
}
