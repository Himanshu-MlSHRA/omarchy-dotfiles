import QtQuick

// The macOS-Dock "genie" from ~/Work/Portfolio's résumé, as a GPU mesh warp.
// Shared by anshu.bar (windows thrown out of the island) and anshu.menu
// (SUPER+SPACE and friends), so every surface leaves and returns the same way.
//
// Place it exactly over `target` (same parent, same x/y/width/height). While
// `progress` is below 1 the real item is hidden and its picture is drawn
// through the funnel instead; at 1 the real item is shown again, so it stays
// fully interactive once open.
//
// Or give it a ready texture (`source`, e.g. a live window capture) instead of
// a target; it is then drawn at every progress, 1 included.
//
//   progress  0 = inside the mouth, 1 = lying open. Animate it LINEARLY over
//             0.62s × |distance|, as the résumé does; the shader carries the
//             easing (pinch first, then an accelerating pull).
//   mouthX / mouthY / mouthWidth   the mouth, in this item's coordinates —
//                                  put it *inside* the island
//   islandX / islandWidth / islandHeight (= its bottom edge y) / islandRadius
//             the island's body, in this item's coordinates. Every pixel of the
//             sheet inside it is cut away, so the sheet comes out from under the
//             notch instead of being painted across it.
//   cornerRadius / borderWidth / borderColor
//             round the sheet into a window (with its border) — for `source`
Item {
  id: genie

  property Item target: null
  property var source: null
  property real progress: 0
  property real mouthX: 0
  property real mouthY: 0
  property real mouthWidth: 120
  // Output scale, so the warped picture is as sharp as the real thing.
  property real scaleFactor: 2

  property real islandX: 0
  property real islandWidth: 0
  property real islandHeight: 0
  property real islandRadius: 0

  property real cornerRadius: 0
  property real borderWidth: 0
  property color borderColor: "transparent"

  // Keep drawing through the shader at rest too (never show `target` raw):
  // for a picture whose real counterpart lives elsewhere, e.g. a window
  // capture that IslandFlight swaps for the real window itself.
  property bool alwaysWarp: false

  readonly property bool external: source !== null
  readonly property bool warping: external || alwaysWarp || progress < 1
  readonly property bool active: warping

  ShaderEffectSource {
    id: shot
    sourceItem: genie.external ? null : genie.target
    hideSource: !genie.external && genie.warping
    live: true
    visible: false
    mipmap: true
    smooth: true
    // Sized from what is sampled (the target), so text stays pixel-sharp.
    textureSize: genie.target
      ? Qt.size(Math.max(1, Math.ceil(genie.target.width * genie.scaleFactor)),
                Math.max(1, Math.ceil(genie.target.height * genie.scaleFactor)))
      : Qt.size(1, 1)
  }

  ShaderEffect {
    anchors.fill: parent
    visible: genie.progress > 0 && genie.warping
    mesh: GridMesh { resolution: Qt.size(6, 200) }
    vertexShader: Qt.resolvedUrl("genie.vert.qsb")
    fragmentShader: Qt.resolvedUrl("genie.frag.qsb")

    property variant source: genie.external ? genie.source : shot
    property real t: genie.progress
    property real tx: genie.mouthX
    property real tw: genie.mouthWidth
    property real ty: genie.mouthY
    property real w: genie.width
    property real h: genie.height
    property real ix: genie.islandX
    property real iw: genie.islandWidth
    property real ih: genie.islandHeight
    property real ir: genie.islandRadius
    property real bs: genie.borderWidth
    property real rr: genie.cornerRadius
    property color borderColor: genie.borderColor
  }
}
