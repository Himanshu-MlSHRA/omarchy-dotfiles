import QtQuick
import qs.Commons

// ---------------------------------------------------------------------------
// The Dynamic Island design system.
//
// Modelled on Atoll (github.com/Ebullioscopic/Atoll): a black notch flush with
// the top edge, square-cornered where it meets the bezel, heavily rounded
// below, with content laid out on lifted-black cards.
//
// Base values are authored against a 12px shell font (the Omarchy default);
// `u` rescales them with `[font] base-size`, which is what the rest of the
// shell scales by. Wayland hands us logical pixels, so these are already
// correct under fractional scaling and at any resolution.
// ---------------------------------------------------------------------------
QtObject {
  id: tk

  readonly property real u: Style.fontScale
  function px(v) { return Math.round(v * u) }

  // ------------------------------------------------------------- geometry
  // The island hangs off the top edge like the notch it imitates: no margin,
  // nothing floating.
  readonly property int topMargin:        0
  // Panacea's pill (EnsixD/Panacea, notch mode at the top edge): 38px tall,
  // at least 420 wide, content kept 18px in from each end.
  readonly property int pillH:            38
  readonly property int collapsedHeight:  pillH
  readonly property int collapsedPadX:    18
  readonly property int pillMinWidth:     240
  readonly property int bannerHeight:     px(46)
  readonly property int bannerPadX:       px(22)
  readonly property int bannerMaxWidth:   px(680)
  // Notifications are drawn only here (the daemon's corner toasts are off).
  // Compact: title + app/time on one line, the whole message wrapped under
  // it. The banner is sized to its text, up to these limits.
  // Wide rather than tall: a long message wraps onto fewer lines, and the
  // whole of it is always shown (the line cap only stops a novel).
  readonly property int notificationWidth:       px(680)   // max outer width
  readonly property int notificationMinWidth:    px(170)
  readonly property int notificationPadY:        px(7)
  readonly property int notificationPadX:        px(16)
  readonly property int notificationIcon:        px(22)
  readonly property int notificationBodyLines:   10
  // Volume / brightness / mic levels (the island owns the `osd` IPC target).
  readonly property int osdTrackWidth:    px(160)
  readonly property int expandedWidth:    px(640)
  // One page at a time (Tab switches): overview cards, or IslandExtras.
  readonly property int expandedHeight:   px(218)
  readonly property int expandedPadX:     px(16)
  readonly property int expandedPadTop:   px(9)
  readonly property int expandedPadBottom: px(20)   // clears the bottom radius
  readonly property int minWidth:         pillMinWidth
  // A detail view replaces the card row. Each kind is sized to the content it
  // actually has rather than to the tallest one: a battery readout has five
  // rows and no list, so growing the pane to the Wi-Fi list's height left it
  // two-thirds empty. `detailHeight` stays the largest of them because the
  // surface's window and the click-away scrim are sized from it.
  function detailHeightFor(kind) {
    if (kind === "network")   return px(252)
    if (kind === "bluetooth") return px(252)
    if (kind === "audio")     return px(206)
    if (kind === "battery")   return px(170)
    if (kind === "claude")    return px(192)
    if (kind === "shanshui")  return px(266)
    return px(206)
  }
  readonly property int detailHeight:     px(252)

  // A password prompt takes over the Wi-Fi detail's lower half rather than
  // opening a window of its own.
  readonly property int fieldHeight:      px(30)
  // How far the surface is drawn above the screen's top row; see IslandGlass.
  readonly property int overscan:         2

  // Atoll's NotchShape radii. The top pair curve outward into the bezel; the
  // bottom pair are the visible rounding.
  // Panacea: the two concave corners where the pill meets the screen edge are
  // a 12px quarter circle (notchFlare), the pill's free corners are round
  // (pillH / 2) and the open panel's are 26.
  readonly property int flare:                 12
  readonly property int collapsedTopRadius:    flare
  readonly property int collapsedBottomRadius: pillH / 2
  readonly property int expandedTopRadius:     flare
  readonly property int expandedBottomRadius:  26

  readonly property int reservedHeight: topMargin + collapsedHeight
  readonly property int windowHeight: topMargin + Math.max(detailHeight, expandedHeight) + shadowBlur + px(8)

  // ---------------------------------------------------------------- color
  // Black, like the bezel it pretends to be. Drop `surfaceAlpha` below 1 and
  // re-add the `omarchy-bar` blur rule in looknfeel.lua for a glass variant.
  readonly property real surfaceAlpha: 1.0

  // Light variant: on a pitch-black backdrop (black wallpaper, or a Shan Shui
  // painting on black paper) a black island disappears, so it lifts to a soft
  // graphite that sits with the black; ink stays white. Bar.qml sets this from
  // island-backdrop.sh.
  property bool light: false
  readonly property color beige:  "#1F1F22"   // graphite on black (was silver #C7C9CD, beige #E8DCC4)
  readonly property color ink:    "#FFFFFF"   // white ink on graphite too
  // What colour a "lifted" layer is drawn in: white on black, ink on beige.
  readonly property color lift:   "#FFFFFF"

  readonly property color surface: Util.alpha(light ? beige : "#000000", surfaceAlpha)

  // Cards: the surface lifted just enough to separate, with a hairline edge
  // (Panacea's card: 5% fill, 1px line, 16px radius).
  readonly property color card:        Util.alpha(lift, 0.05)
  readonly property color cardHover:   Util.alpha(lift, 0.10)
  readonly property color cardPressed: Util.alpha(lift, 0.16)
  readonly property color line:        Util.alpha(lift, 0.10)
  readonly property int cardRadius:    px(16)
  readonly property int cardGap:       px(9)
  readonly property int cardPad:       px(12)

  // Panacea's Nothing palette: white ink, muted = the ink at 45%, and the
  // accent is the ink itself (Nothing highlights by brightness, not hue).
  readonly property color text:      "#FFFFFF"
  readonly property color textDim:   Util.alpha(text, 0.45)
  readonly property color textFaint: Util.alpha(text, 0.30)
  readonly property color accent:    text
  readonly property color crit:      "#D71921"
  // Text drawn on a filled "on" pill (the pill is `text` at ~92%).
  readonly property color pillText:    "#000000"
  readonly property color meterTrack: Util.alpha(lift, 0.10)
  // Connection failures and refusals. Distinct from `accent`, which the meters
  // already use for "worth noticing" rather than "went wrong".
  readonly property color danger:     "#FF6B6B"
  readonly property color fieldBg:    Util.alpha(lift, 0.085)

  // --------------------------------------------------------------- shadow
  readonly property int  shadowBlur:    px(26)
  readonly property int  shadowOffsetY: px(7)
  readonly property real shadowAlpha:   0      // Panacea's pill has no shadow

  // ----------------------------------------------------------- typography
  readonly property string fontFamily:  Style.font.family
  // Panacea: fontSize 15, iconSize 17; labels at fontSize - 2, captions - 4.
  readonly property int fontSize:       15
  readonly property int iconSize:       17
  readonly property real dotClock:      fontSize - 1    // dot-matrix clock in the pill
  readonly property real dotSmall:      fontSize - 3    // dot numbers beside icons
  readonly property int clockSize:      fontSize - 2
  readonly property real clockSpacing:  0.8
  readonly property int bannerSize:     fontSize - 1
  readonly property int statSize:       fontSize - 2
  readonly property int cardTitleSize:  fontSize - 4
  readonly property int cardValueSize:  fontSize + 3
  readonly property int tileValueSize:  fontSize - 2
  readonly property int tileLabelSize:  fontSize - 4
  readonly property int tileIconSize:   iconSize - 2
  readonly property int glyphSize:      iconSize - 2
  readonly property int detailTitleSize: Style.font.subtitle
  readonly property int rowHeight:       px(26)

  // ------------------------------------------------------------ animation
  // cubic-bezier(0.32, 0.72, 0, 1) — the curve Apple uses for island and sheet
  // transforms. Fast out of the gate, long settle, no oscillation.
  // Panacea's timeline: size and position move on InOutCubic over 230ms,
  // opacity and colour fade over 200ms, hover answers in 150ms.
  readonly property var springCurve: [0.65, 0.0, 0.35, 1.0, 1.0, 1.0]
  readonly property var fadeCurve:   [0.33, 1.0, 0.68, 1.0, 1.0, 1.0]

  readonly property int expandDuration:     230
  readonly property int collapseDuration:   230
  readonly property int radiusDuration:     230
  readonly property int hoverDuration:      150
  // The old content clears out before the pane starts moving, and the new
  // content arrives only once the pane has committed to its size. Nothing is
  // ever on screen at a size it is not going to settle at.
  // Panacea: the open page fades in over animFast (0.52 x 230 = 120ms,
  // OutCubic) while the pane grows over it, out in 90ms; no stagger.
  readonly property int contentInDelay:     0
  readonly property int contentInDuration:  120
  readonly property int contentOutDuration: 90
  readonly property int stagger:            0
  // Concave corners come back this long after the pill is home (animMs + 40).
  readonly property int cornerRevealDelay:  270
  readonly property int colorDuration:      200

  // ---------------------------------------------------------- interaction
  // The island stays open until you dismiss it: click away, press Escape, or
  // hit the toggle again. Nothing times out from under you.
  readonly property int bannerDuration:       2600
  readonly property int notificationDuration: 5200

  // Master switch for automatic banners. Off means the island only ever
  // changes state because you clicked it.
  readonly property bool autoExpandOnEvents: true
  // Volume and brightness arrive through the `osd` IPC target, which the island
  // answers itself (omarchy.osd is disabled in shell.json). These watcher-
  // driven volume banners would show each change twice on top of that.
  readonly property bool volumeBanners: false
}
