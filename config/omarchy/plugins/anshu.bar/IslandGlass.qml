import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// The island's surface: the macOS notch shape, in black.
//
// Same outline as the Atoll `NotchShape` port it replaces — top corners curve
// *outward* into the screen edge, bottom corners are a large convex radius,
// both radii animate — but built so a resize is cheap enough to run every
// frame at 90Hz:
//
//   body     a native Rectangle with per-corner radii (no path re-tessellation)
//   fillets  two small Shapes, only ever topRadius-sized
//   shadow   RectangularShadow (an analytic SDF), not a MultiEffect blur pass
//            over the whole surface
//
// The previous version re-tessellated a full-size curved path and re-blurred
// its shadow on every frame of a morph, which is what made SUPER+B and the
// menus stutter. Original kept in ~/.config/omarchy/island-v2-backup-*/.
Item {
  id: glass

  required property var tk
  property real topRadius: tk.collapsedTopRadius
  property real bottomRadius: tk.collapsedBottomRadius
  property color tint: "transparent"
  property real tintStrength: 0
  // Panacea's concave corners (NotchCorner): hidden at once when the pill
  // leaves its edge, faded back in (animFast) once it is home again.
  property bool cornersOn: true

  readonly property color surfaceColor: tintStrength > 0
    ? Qt.tint(tk.surface, Qt.rgba(tint.r, tint.g, tint.b, tintStrength))
    : tk.surface

  // Drawn from a couple of pixels above the surface so the antialiased top
  // edge never shows as a hairline of wallpaper on the screen's first row.
  readonly property int overscan: tk.overscan

  RectangularShadow {
    visible: glass.tk.shadowAlpha > 0
    anchors.fill: body
    radius: Math.min(glass.bottomRadius, body.height / 2)
    blur: glass.tk.shadowBlur
    offset.y: glass.tk.shadowOffsetY
    color: Qt.rgba(0, 0, 0, glass.tk.shadowAlpha)
    cached: false
  }

  Rectangle {
    id: body
    x: glass.topRadius
    y: -glass.overscan
    width: Math.max(0, glass.width - glass.topRadius * 2)
    height: glass.height + glass.overscan
    color: glass.surfaceColor
    topLeftRadius: 0
    topRightRadius: 0
    bottomLeftRadius: Math.min(glass.bottomRadius, height / 2, width / 2)
    bottomRightRadius: bottomLeftRadius
    antialiasing: true
  }

  // Concave corners into the screen edge, one per side: Panacea's
  // NotchCorner — an r x r square with a quarter circle cut out, centred on
  // its lower outer corner.
  component Fillet: Shape {
    id: f
    property bool mirrored: false
    readonly property real r: glass.topRadius
    width: r
    height: glass.overscan + r
    y: -glass.overscan
    opacity: glass.cornersOn ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      enabled: glass.cornersOn
      NumberAnimation { duration: glass.tk.contentInDuration }
    }
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.x: f.width / 2; xScale: f.mirrored ? -1 : 1 }
    ShapePath {
      fillColor: glass.surfaceColor
      strokeWidth: -1
      startX: 0; startY: 0
      PathLine { x: f.r; y: 0 }
      PathLine { x: f.r; y: f.height }
      PathArc { x: 0; y: glass.overscan; radiusX: f.r; radiusY: f.r; direction: PathArc.Counterclockwise }
      PathLine { x: 0; y: 0 }
    }
  }

  Fillet { x: 0 }
  Fillet { x: glass.width - glass.topRadius; mirrored: true }
}
