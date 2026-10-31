import QtQuick
import "../anshu.bar/IslandBridge.js" as IslandBridge

// Stands in for omarchy.osd and draws nothing itself. Omarchy 4.5 stopped going
// through the `osd` IPC target for the volume and brightness keys: they call
// shell.summon("omarchy.osd", json) in process. Because this plugin declares
// clonedFrom omarchy.osd, PluginRegistry.resolveEnabledId routes those summons
// here, and they are handed to the island. The `osd` IPC target itself stays in
// IslandStatus.qml for scripts; do not register a second one here.
Item {
  id: root

  // shell.isPluginOpen reads this; the island owns the real state.
  property bool opened: false

  function open(payloadJson) {
    var bar = IslandBridge.bar
    if (bar) bar.showIslandOsd(payloadJson)
    else console.warn("anshu.osd: island not loaded, OSD dropped")
  }

  function close() {
    var bar = IslandBridge.bar
    if (bar) bar.closeIslandOsd()
  }
}
