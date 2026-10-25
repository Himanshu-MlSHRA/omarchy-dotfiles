import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "genie"

// Windows come out of the Dynamic Island and go back into it, the way macOS
// pours a window out of its Dock icon — with the window's own picture, not a
// stand-in sheet.
//
// open   the new window is hidden the moment it maps (island-window.sh, an
//        instant Hyprland opacity override), its *live* capture is drawn
//        through the genie (genie/, the résumé effect) from the island onto
//        the window's rect, and on landing the real window is switched back
//        on in the same frame the picture leaves.
// close  the active window is snapshotted every so often (and whenever focus
//        changes); when it closes, that snapshot is pulled back through the
//        funnel into the island.
//
// Hyprland cannot draw a window outside its own box, so the travel is drawn
// here, on a click-through layer. The layer stays mapped (nothing visible at
// rest) because a toplevel capture only runs inside a mapped window, and the
// close snapshot has to exist before the window is gone.
Scope {
  id: flight

  required property var tk
  // The island as it is drawn this frame (anshu.bar keeps these current).
  property real islandWidth: tk.px(200)
  property real islandHeight: tk.collapsedHeight
  property real islandTopRadius: tk.collapsedTopRadius
  property real islandBottomRadius: tk.collapsedBottomRadius

  // Hyprland's decoration, so the picture lands as the window's exact shape.
  property real windowRadius: 16
  property real borderSize: 2
  property color borderColor: "#E1DCC9"

  // The résumé's genie: linear; the shader carries the easing.
  readonly property int genieDuration: 420
  readonly property string helper: Qt.resolvedUrl("island-window.sh").toString().replace("file://", "")

  // address ("0x…") -> { x, y, w, h }
  property var rects: ({})
  // address -> active opacity (what the real window is drawn at)
  property var opacities: ({})
  property int activeWs: -1
  property int specialWs: 0

  ListModel { id: flights }

  function toplevelFor(address) {
    var bare = String(address).replace(/^0x/, "")
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i].address === bare || list[i].address === address) return list[i]
    return null
  }

  function indexOf(address, kind) {
    for (var i = 0; i < flights.count; i++) {
      var f = flights.get(i)
      if (f.address === address && (!kind || f.kind === kind)) return i
    }
    return -1
  }

  // ----------------------------------------------------------- geometry
  property var pendingOpen: []

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: flight.ingest(String(text || ""))
    }
  }
  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var ms = JSON.parse(String(text || "[]"))
          for (var i = 0; i < ms.length; i++) if (ms[i].focused) {
            flight.activeWs = ms[i].activeWorkspace ? ms[i].activeWorkspace.id : -1
            flight.specialWs = ms[i].specialWorkspace ? ms[i].specialWorkspace.id : 0
          }
        } catch (e) {}
        if (!clientsProc.running) clientsProc.running = true
      }
    }
  }

  function visibleClient(c) {
    if (!c || !c.mapped || c.hidden) return false
    if (c.fullscreen && c.fullscreen !== 0) return false
    var ws = c.workspace ? c.workspace.id : -999
    return ws === activeWs || (specialWs !== 0 && ws === specialWs)
  }

  function ingest(raw) {
    var list
    try { list = JSON.parse(raw) } catch (e) { return }
    var next = ({})
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!visibleClient(c)) continue
      next[c.address] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] }
    }
    rects = next
    // Windows that mapped since the last read: give them their rect, or let
    // them go (another workspace, fullscreen, too small to be worth a flight).
    var waiting = pendingOpen
    pendingOpen = []
    for (var j = 0; j < waiting.length; j++) {
      var idx = indexOf(waiting[j], "open")
      if (idx < 0) continue
      var r = next[waiting[j]]
      if (r && r.w >= 80 && r.h >= 60)
        flights.set(idx, { rx: r.x, ry: r.y, rw: r.w, rh: r.h, placed: true })
      else
        flights.setProperty(idx, "aborted", true)
    }
  }

  function refresh() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  // Tiled neighbours reflow on windowsMove; read the cache once they settle.
  Timer { id: settle; interval: 420; onTriggered: flight.refresh() }
  // A just-mapped window has its final rect a moment after the event.
  Timer {
    id: openProbe
    interval: 30
    onTriggered: {
      if (monitorsProc.running || clientsProc.running) { restart(); return }
      flight.refresh()
    }
  }

  function startOpen(address) {
    if (indexOf(address, "") >= 0) return
    flights.append({ kind: "open", address: address, rx: 0, ry: 0, rw: 0, rh: 0,
                     placed: false, aborted: false })
    pendingOpen = pendingOpen.concat([address])
    openProbe.restart()
  }

  function startClose(address) {
    var r = rects[address]
    if (!r || snapshot.frozenAddress !== address || !snapshot.frozenReady) return
    if (indexOf(address, "") >= 0) return
    snapshot.held += 1
    flights.append({ kind: "close", address: address, rx: r.x, ry: r.y, rw: r.w, rh: r.h,
                     placed: true, aborted: false })
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      var data = String(event.data || "")
      if (name === "openwindow") {
        flight.startOpen("0x" + data.split(",")[0])
        settle.restart()
      } else if (name === "closewindow") {
        flight.startClose("0x" + data)
        settle.restart()
      } else if (name === "activewindowv2") {
        snapshot.retarget(data === "" ? "" : "0x" + data)
        settle.restart()
      } else if (name === "movewindowv2" || name === "changefloatingmode" || name === "fullscreen"
                 || name === "workspacev2" || name === "activespecial" || name === "focusedmonv2") {
        settle.restart()
      }
    }
  }

  // Hyprland's decoration values.
  Process {
    command: ["sh", "-c", "for o in decoration:rounding general:border_size general:col.active_border; do hyprctl -j getoption $o | tr -d '\\n'; echo; done"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var v = JSON.parse(line)
          if (v.option === "decoration:rounding" && v.int >= 0) flight.windowRadius = v.int
          else if (v.option === "general:border_size" && v.int >= 0) flight.borderSize = v.int
          else if (v.option === "general:col.active_border" && v.gradient) {
            var hex = String(v.gradient).split(" ")[0]          // aarrggbb
            if (/^[0-9a-fA-F]{8}$/.test(hex)) flight.borderColor = "#" + hex
          }
        } catch (e) {}
      }
    }
  }

  // Anything a previous shell left hidden mid-flight comes back first.
  Process { id: recoverProc; command: ["bash", flight.helper, "recover"] }
  // The window focused when the shell starts gets its snapshot too.
  Process {
    id: activeProc
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { var a = JSON.parse(String(text || "{}")).address; if (a) snapshot.retarget(a) } catch (e) {}
      }
    }
  }
  Component.onCompleted: {
    recoverProc.running = true
    activeProc.running = true
    refresh()
  }

  // Test on an existing window without opening or closing anything:
  //   omarchy-shell omarchy.flight window open 0x…   (hidden, flown out, shown)
  //   omarchy-shell omarchy.flight window close 0x…  (snapshot flown in; the
  //                                                    window is hidden meanwhile)
  IpcHandler {
    target: "omarchy.flight"
    function window(kind: string, address: string): string {
      if (kind === "close") {
        if (snapshot.frozenAddress !== address) return "no snapshot of " + address + " (have " + snapshot.frozenAddress + ")"
        Quickshell.execDetached(["bash", flight.helper, "hide", address])
        flight.startClose(address)
        testShow.address = address
        testShow.restart()
        return "close"
      }
      flight.startOpen(address)
      return "open"
    }
  }
  Timer {
    id: testShow
    property string address: ""
    interval: flight.genieDuration + 500
    onTriggered: Quickshell.execDetached(["bash", flight.helper, "show", address])
  }

  // -------------------------------------------------------------- the layer
  PanelWindow {
    id: layer
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: true
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-island-flight"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Click-through. An empty region counts as "no mask" (it would swallow
    // every click), so the input region is one pixel that the island itself
    // always covers.
    Item { id: hitPixel; x: Math.round(stage.width / 2); y: 1; width: 1; height: 1 }
    mask: Region { item: hitPixel }

    Item {
      id: stage
      anchors.fill: parent

      readonly property real dpr: layer.screen ? layer.screen.devicePixelRatio : 2

      // The island's body (between the outward fillets), where the genie's
      // mouth sits and inside which the picture is cut away.
      readonly property real bodyWidth: Math.max(40, flight.islandWidth - flight.islandTopRadius * 2)
      readonly property real bodyX: (width - bodyWidth) / 2

      // ---------------------------------------------------- close snapshot
      // The focused window, captured now and then and frozen into a texture
      // that outlives the window itself.
      Item {
        id: snapshot
        property string address: ""
        property string frozenAddress: ""
        property bool frozenReady: false
        property int held: 0           // close flights still drawing `frozen`
        property var target: null

        x: 0; y: 0
        width: { var r = flight.rects[address]; return r ? r.w : 1 }
        height: { var r = flight.rects[address]; return r ? r.h : 1 }

        function retarget(addr) {
          retargetDelay.address = addr
          retargetDelay.restart()
        }

        Timer {
          id: retargetDelay
          property string address: ""
          interval: 260
          onTriggered: {
            if (snapshot.held > 0) { restart(); return }
            var t = address !== "" ? flight.toplevelFor(address) : null
            snapshot.address = t ? address : ""
            snapshot.target = t ? t.wayland : null
          }
        }

        ScreencopyView {
          id: snapView
          anchors.fill: parent
          live: false
          captureSource: snapshot.target
          onHasContentChanged: if (hasContent) freezeDelay.restart()
        }

        // Re-shoot every so often, so what flies back is what was on screen.
        Timer {
          interval: 2000
          repeat: true
          running: snapshot.target !== null
          onTriggered: {
            if (snapshot.held > 0 || flights.count > 0) return
            snapView.captureFrame()
            freezeDelay.restart()
          }
        }
        Timer {
          id: freezeDelay
          interval: 90
          onTriggered: {
            if (snapshot.held > 0) return
            if (!snapView.hasContent || snapshot.address === "") return
            frozen.textureSize = Qt.size(Math.ceil(snapshot.width * stage.dpr), Math.ceil(snapshot.height * stage.dpr))
            frozen.scheduleUpdate()
            snapshot.frozenAddress = snapshot.address
            snapshot.frozenReady = true
            opacityProbe.address = snapshot.address
            opacityProbe.running = true
          }
        }
      }

      ShaderEffectSource {
        id: frozen
        sourceItem: snapView
        hideSource: true
        live: false
        visible: false
        mipmap: true
        smooth: true
      }

      Process {
        id: opacityProbe
        property string address: ""
        command: ["hyprctl", "getprop", "address:" + address, "opacity"]
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: {
            var v = parseFloat(String(text || ""))
            if (v > 0 && v <= 1) {
              var o = flight.opacities
              o[opacityProbe.address] = v
              flight.opacities = o
            }
          }
        }
      }

      // ------------------------------------------------------------ flights
      Repeater {
        model: flights

        delegate: Item {
          id: pane
          required property int index
          required property string kind
          required property string address
          required property real rx
          required property real ry
          required property real rw
          required property real rh
          required property bool placed
          required property bool aborted

          readonly property bool opening: kind === "open"
          readonly property real bs: flight.borderSize
          // 0 = inside the island, 1 = lying on the window's rect
          property real progress: opening ? 0 : 1
          property real paneOpacity: flight.opacities[address] !== undefined ? flight.opacities[address] : 1
          property bool finished: false

          // The window's outer box, border included.
          x: rx - bs; y: ry - bs
          width: rw + bs * 2; height: rh + bs * 2

          // ------------------------------------------------- open: live
          property var toplevel: opening ? flight.toplevelFor(address) : null
          Connections {
            target: Hyprland.toplevels
            enabled: pane.opening && (pane.toplevel === null || pane.toplevel.wayland === null)
            function onValuesChanged() { pane.toplevel = flight.toplevelFor(pane.address) }
          }

          ScreencopyView {
            id: live
            x: pane.bs; y: pane.bs
            width: pane.rw; height: pane.rh
            visible: pane.opening
            live: pane.opening && !pane.finished
            captureSource: pane.opening && pane.toplevel ? pane.toplevel.wayland : null
          }

          Genie {
            anchors.fill: parent
            opacity: pane.paneOpacity
            target: pane.opening ? live : null
            source: pane.opening ? null : frozen
            alwaysWarp: true
            progress: pane.progress
            scaleFactor: stage.dpr
            cornerRadius: flight.windowRadius
            borderWidth: pane.bs
            borderColor: flight.borderColor
            // The mouth sits inside the island's flat bottom, and everything
            // inside the island's outline is cut away: the window pours out
            // from *under* the notch, never across it.
            // Half the island's width, centred: the neck leaves through the
            // middle of the flat bottom and the island keeps its rounded
            // corners the whole way (a full-width neck turned them into a
            // square black shoulder).
            mouthWidth: Math.max(40, Math.min(stage.bodyWidth - flight.islandBottomRadius * 2 - flight.tk.px(8),
                                              stage.bodyWidth * 0.5))
            mouthX: (stage.width - mouthWidth) / 2 - pane.x
            mouthY: Math.round(flight.islandHeight * 0.5) - pane.y
            islandX: stage.bodyX - pane.x
            islandWidth: stage.bodyWidth
            islandHeight: flight.islandHeight - pane.y
            islandRadius: Math.min(flight.islandBottomRadius, flight.islandHeight, stage.bodyWidth / 2)
          }

          // Hide the real window the moment it maps; its picture does the
          // travelling.
          Process {
            id: hideProc
            running: pane.opening
            command: ["bash", flight.helper, "hide", pane.address]
            stdout: StdioCollector {
              waitForEnd: true
              onStreamFinished: {
                var v = parseFloat(String(text || ""))
                if (v > 0 && v <= 1) pane.paneOpacity = v
              }
            }
          }
          Process {
            id: showProc
            command: ["bash", flight.helper, "show", pane.address]
            // The real window is back (Hyprland applies it instantly); the
            // picture leaves on the next frame.
            onExited: dropTimer.restart()
          }
          Timer { id: dropTimer; interval: 1; onTriggered: pane.done() }

          readonly property bool ready: placed && !hideProc.running && live.hasContent
          onReadyChanged: if (ready && opening && !openAnim.running && !finished) openAnim.start()
          onAbortedChanged: if (aborted) bail()
          // Never leave a window hidden: if the picture is not there in time,
          // the window simply appears.
          Timer {
            interval: 900
            running: pane.opening && !pane.ready && !pane.finished
            onTriggered: pane.bail()
          }

          function bail() {
            if (finished) return
            finished = true
            openAnim.stop()
            progress = 0
            if (!showProc.running) showProc.running = true
          }

          function done() {
            if (!opening) snapshot.held = Math.max(0, snapshot.held - 1)
            var i = flight.indexOf(address, kind)
            if (i >= 0) flights.remove(i)
          }

          NumberAnimation {
            id: openAnim
            target: pane; property: "progress"; from: 0; to: 1
            duration: flight.genieDuration; easing.type: Easing.Linear
            onFinished: {
              pane.finished = true
              if (!showProc.running) showProc.running = true
            }
          }

          SequentialAnimation {
            running: !pane.opening
            NumberAnimation {
              target: pane; property: "progress"; from: 1; to: 0
              duration: flight.genieDuration; easing.type: Easing.Linear
            }
            ScriptAction { script: pane.done() }
          }
        }
      }
    }
  }
}
