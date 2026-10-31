import QtQuick
import Quickshell
import Quickshell.Io
import "IslandOsdModel.js" as OsdModel

// The island's state machine for everything that is not the clock.
//
// Two independent channels:
//
//   chips   — ongoing states (recording, dictation, silent, stay awake, night
//             light, playing media). They ride alongside the clock as small
//             glyphs and stay for as long as the state is true.
//   banner  — a momentary takeover. The island morphs into a message for a
//             few seconds, then hands itself back to the clock.
//
// Only states this machine can actually observe are represented. Every source
// is either a reactive shell service, a streaming process, or a file watch;
// the single exception is screen recording, noted at its declaration.
Item {
  id: status
  visible: false

  required property var tk
  // The bar's plugin shell API. Bar-kind plugins are handed narrow proxies for
  // the first-party services, which is where the toggles' real state lives.
  property var shell: null
  property var sys: null
  // IslandFocus, so a DND flip made by a focus phase change stays quiet.
  property var focusTimer: null
  function focusQuiet() { return !!focusTimer && Date.now() - focusTimer.flippedAt < 4000 }

  readonly property var notifications: shell ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var idle:          shell ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var nightlight:    shell ? shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var media:         shell ? shell.firstPartyServiceFor("omarchy.media") : null

  readonly property bool silent:     notifications ? notifications.doNotDisturb : false
  readonly property bool stayAwake:  idle ? idle.stayAwake : false
  readonly property bool nightLight: nightlight ? nightlight.enabled : false
  // The bar is handed a narrow proxy of each first-party service, not the
  // service itself: for media that is `activePlayer` and nothing else, so the
  // track fields are read off the player rather than the service.
  readonly property var player: media ? media.activePlayer : null
  readonly property bool playing: !!player
  readonly property string trackTitle:  player ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: player ? String(player.trackArtist || "") : ""

  // gpu-screen-recorder publishes no signal and writes its marker file into
  // /tmp, where a watch on a not-yet-existing path is unreliable. A four
  // second probe is the honest cost of knowing; nothing else here polls.
  property bool recording: false

  // omarchy-voxtype-status streams a line per state change, so dictation is
  // genuinely event-driven. Without voxtype installed the process never emits
  // and the state stays idle.
  property string dictation: "idle"
  readonly property bool dictating: dictation === "recording" || dictation === "transcribing"

  // ------------------------------------------------------------------ chips
  // Ordered by how much the user needs to know it right now.
  readonly property var chips: {
    var out = []
    if (recording)  out.push({ key: "recording",  glyph: "󰻂", tint: tk.accent })
    if (dictating)  out.push({ key: "dictation",  glyph: dictation === "transcribing" ? "󰔟" : "󰍬", tint: tk.accent })
    if (playing)    out.push({ key: "media",      glyph: "󰝚", tint: tk.textDim })
    if (silent)     out.push({ key: "silent",     glyph: "󰂛", tint: tk.textDim })
    if (stayAwake)  out.push({ key: "stayAwake",  glyph: "󰅶", tint: tk.textDim })
    if (nightLight) out.push({ key: "nightLight", glyph: "󰔎", tint: tk.textDim })
    return out
  }

  // The states that also tint the glass. Only those that warrant colouring the
  // whole surface qualify — a chip is enough for the rest.
  readonly property string surfaceState: recording ? "recording" : (dictating ? "dictation" : "")
  readonly property color surfaceTint: surfaceState === "" ? tk.accent : tk.accent
  readonly property real surfaceTintStrength: surfaceState === "recording" ? 0.20
    : surfaceState === "dictation" ? 0.13 : 0.0

  // ----------------------------------------------------------------- banner
  property string bannerKind: ""
  property string bannerGlyph: ""
  property string bannerTitle: ""
  property string bannerDetail: ""
  property color bannerTint: tk.text
  // "plain" | "osd" | "notification" — which IslandBanner layout to use.
  property string bannerMode: "plain"
  property int bannerProgress: -1
  property string bannerApp: ""
  property string bannerImage: ""
  property string bannerAppIcon: ""
  property int bannerUrgency: 1
  readonly property bool bannerActive: bannerKind !== ""

  // The newest live toast (its state-file JSON) and how many are live. The
  // notification banner is held for exactly as long as a toast is live, and
  // comes back after anything momentary (a volume change) interrupts it.
  property var liveNotification: null
  property int notificationCount: 0
  readonly property string liveNotificationId:
    liveNotification ? String(liveNotification.originalId) : ""

  // Manual interaction always outranks an automatic one: while the user holds
  // the island open, banners are dropped rather than queued, so nothing pops
  // up behind their back and nothing arrives stale afterwards.
  property bool suppressed: false

  // Nothing announces itself during startup, when every watcher reports its
  // initial value at once.
  property bool armed: false

  signal bannerShown(string kind)

  function show(kind, glyph, title, detail, tint, ms) {
    if (!armed || suppressed || !tk.autoExpandOnEvents) return
    present(kind, "plain", glyph, title, detail, tint, ms)
  }

  function present(kind, mode, glyph, title, detail, tint, ms) {
    bannerKind = kind
    bannerMode = mode
    bannerGlyph = glyph
    bannerTitle = title
    bannerDetail = detail || ""
    bannerTint = tint || tk.text
    if (mode !== "osd" && mode !== "charge") bannerProgress = -1
    // ms === 0 holds until something ends it (a live notification).
    if (ms === 0) holdTimer.stop()
    else {
      holdTimer.interval = ms || tk.bannerDuration
      holdTimer.restart()
    }
    bannerShown(kind)
  }

  // A momentary banner ending hands the island back to a still-live
  // notification instead of the clock.
  function bannerEnded() {
    bannerKind = ""
    if (liveNotification && notificationCount > 0 && !suppressed) presentNotification()
  }

  // `omarchy-shell omarchy.bar island demo:charge` — preview the plug-in banner.
  function demoCharge() {
    bannerProgress = sys && sys.batteryPercent >= 0 ? sys.batteryPercent : 64
    present("battery", "charge", "", "Charging", sys ? sys.batteryDetail : "", tk.accent, 3400)
  }

  function dismiss() {
    holdTimer.stop()
    bannerKind = ""
  }

  Timer {
    id: holdTimer
    interval: status.tk.bannerDuration
    onTriggered: status.bannerEnded()
  }

  onSuppressedChanged: {
    if (suppressed) dismiss()
    else if (liveNotification && notificationCount > 0) presentNotification()
  }

  // ------------------------------------------------------------------- osd
  // The stock omarchy.osd plugin is disabled, so its two entry points land
  // here and the level shows inside the island: scripts call
  // `omarchy-shell osd show <json>` (the IPC target below), and the shell's own
  // volume and brightness keys summon omarchy.osd in process, which the
  // anshu.osd plugin forwards to this function. Both must keep working.
  function showOsd(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { return }
    var s = OsdModel.stateForShow(p.icon || "", p.message || "",
      p.value === undefined ? "" : String(p.value),
      p.max === undefined ? "100" : String(p.max),
      p.progressText || "",
      p.duration === undefined || p.duration === "" ? "1400" : String(p.duration))
    if (suppressed) return
    bannerProgress = s.hasProgress ? Math.round(s.value * 100 / s.maxValue) : -1
    present("osd", s.hasProgress ? "osd" : "plain", s.icon, s.message, "",
            tk.text, s.duration > 0 ? Math.max(1100, s.duration) : 0)
  }

  function closeOsd() {
    if (bannerKind === "osd") bannerEnded()
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { status.showOsd(payloadJson); return "ok" }
    function close(): string { status.closeOsd(); return "ok" }
    function state(): string { return status.bannerKind === "osd" ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // --------------------------------------------------------- shell toggles
  Connections {
    target: status
    function onSilentChanged() {
      if (status.focusQuiet()) return
      status.show("silent", status.silent ? "󰂛" : "󰂟",
                  status.silent ? "Silent" : "Notifications on",
                  status.silent ? "Do not disturb" : "", status.tk.text)
    }
    function onStayAwakeChanged() {
      if (status.focusQuiet()) return
      status.show("stayAwake", "󰅶", status.stayAwake ? "Stay Awake" : "Idle allowed",
                  status.stayAwake ? "Screen will not sleep" : "", status.tk.text)
    }
    function onNightLightChanged() {
      if (status.focusQuiet()) return
      status.show("nightLight", "󰔎", status.nightLight ? "Night Light" : "Day Light", "", status.tk.text)
    }
    function onRecordingChanged() {
      status.show("recording", "󰻂", status.recording ? "Recording" : "Recording stopped",
                  status.recording ? "Screen capture is live" : "", status.tk.accent)
    }
    function onDictatingChanged() {
      if (!status.dictating) return
      status.show("dictation", status.dictation === "transcribing" ? "󰔟" : "󰍬",
                  status.dictation === "transcribing" ? "Transcribing" : "Listening", "", status.tk.accent)
    }
    function onTrackTitleChanged() {
      if (!status.playing || status.trackTitle === "") return
      var sig = status.trackTitle + "\u0000" + status.trackArtist
      if (sig === status.lastTrack) return
      status.lastTrack = sig
      status.show("media", "󰝚", status.trackTitle, status.trackArtist, status.tk.text)
    }
  }

  property string lastTrack: ""
  property var claudeBands: ({ session: -1, weekly: -1 })

  function claudeBand(which, pct, reset) {
    if (pct < 0) return
    var band = pct >= 95 ? 2 : pct >= 80 ? 1 : 0
    var prev = claudeBands[which]
    var next = Object.assign({}, claudeBands)
    next[which] = band
    claudeBands = next
    if (prev < 0 || band <= prev) return
    var label = which === "session" ? "5-hour limit" : "Weekly limit"
    status.show("claude", sys.claudeGlyph,
      "Claude " + pct + "% used",
      label + (reset !== "" ? "  ·  resets " + reset : ""),
      band === 2 ? tk.danger : tk.accent, 6000)
  }
  property string lastNetKind: ""

  // ---------------------------------------------------------- system events
  Connections {
    target: status.sys
    ignoreUnknownSignals: true

    function onChargingChanged() {
      if (!status.sys.hasBattery) return
      if (status.sys.charging) {
        if (!status.armed || status.suppressed || !status.tk.autoExpandOnEvents) return
        status.bannerProgress = status.sys.batteryPercent
        status.present("battery", "charge", status.sys.batteryGlyph, "Charging",
                       status.sys.batteryDetail, status.tk.accent, 3400)
        return
      }
      status.show("battery", status.sys.batteryGlyph,
                  status.sys.charging ? "Charging" : "On battery",
                  status.sys.batteryDetail, status.tk.text)
    }
    function onBatteryLowChanged() {
      if (!status.sys.batteryLow) return
      status.show("battery", "󰂃", "Low battery",
                  status.sys.batteryPercent + "% remaining", status.tk.accent, 6000)
    }
    function onNetKindChanged() {
      // The first probe resolving "unknown" into a real state is not a change
      // the user made; only transitions between two known states announce.
      var previous = status.lastNetKind
      status.lastNetKind = status.sys.netKind
      if (previous === "" || status.sys.netKind === "") return
      status.show("network", status.sys.netGlyph,
                  status.sys.netKind === "disconnected" ? "Offline" : status.sys.netValue,
                  status.sys.netDetail, status.tk.text)
    }
    function onBtValueChanged() {
      if (!status.sys.btEnabled) return
      status.show("bluetooth", status.sys.btGlyph, status.sys.btValue,
                  status.sys.btDetail, status.tk.text)
    }
    function onVolumeChanged() {
      if (!status.tk.volumeBanners) return
      status.show("volume", status.sys.audioGlyph, status.sys.audioValue, "", status.tk.text, 1400)
    }
    // Claude Code usage: one heads-up as each allowance crosses 80% and
    // again at 95%. The first value read only sets the baseline, so a shell
    // restart at 85% does not announce anything.
    function onClaudePercentChanged() {
      status.claudeBand("session", status.sys.claudePercent, status.sys.claudeSessionReset)
    }
    function onClaudeWeeklyPercentChanged() {
      status.claudeBand("weekly", status.sys.claudeWeeklyPercent, status.sys.claudeWeeklyReset)
    }
    function onMutedChanged() {
      if (!status.tk.volumeBanners) return
      status.show("volume", status.sys.audioGlyph,
                  status.sys.muted ? "Muted" : status.sys.audioValue, "", status.tk.text, 1400)
    }
  }

  // ----------------------------------------------------------- notifications
  // The daemon owns delivery, history and DND; the island only mirrors the
  // newest toast it has put on screen, so this is not a second notification
  // system. The proxy the bar is handed does not expose the popup model, but
  // the daemon keeps one file per visible toast, which a directory watch turns
  // into an event.
  property real lastNotificationAt: 0

  FileView {
    path: status.popupDir
    watchChanges: true
    printErrors: false
    onFileChanged: notificationProbe.restart()
  }

  readonly property string popupDir:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/notifications"

  Timer {
    id: notificationProbe
    interval: 120   // the daemon writes the file, then its image; read once
    onTriggered: if (!notificationRead.running) notificationRead.running = true
  }

  Process {
    id: notificationRead
    command: [Qt.resolvedUrl("island-notification.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        var state
        try { state = JSON.parse(raw) } catch (e) { return /* half-written; re-read on next change */ }
        status.applyNotifications(state.newest, Number(state.count || 0))
      }
    }
  }

  function cleanBody(s) {
    return String(s || "")
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<[^>]*>/g, "")
      .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
      .replace(/\s+/g, " ").trim()
  }

  function applyNotifications(newest, count) {
    notificationCount = count
    if (!newest || count === 0) {
      liveNotification = null
      if (bannerKind === "notification") dismiss()
      return
    }
    var at = Number(newest.timestamp || 0)
    var fresh = at > lastNotificationAt
    var changed = !liveNotification
      || String(liveNotification.originalId) !== String(newest.originalId)
      || liveNotification.summary !== newest.summary
      || liveNotification.body !== newest.body
    liveNotification = newest
    if (fresh) lastNotificationAt = at
    // New or updated: take the island over now. A count change on an
    // already-showing one only refreshes the badge (bound below).
    if ((fresh || changed) && armed && !suppressed) presentNotification()
    else if (bannerKind === "notification") presentNotification()
  }

  function presentNotification() {
    var n = liveNotification
    if (!n) return
    // A level change on screen keeps its few hundred ms; the notification
    // returns via bannerEnded() as soon as it is done.
    if (bannerKind === "osd" && holdTimer.running) return
    bannerApp = String(n.app === "notify-send" || n.app === "omarchy-action" ? "" : (n.app || ""))
    bannerImage = String(n.image || "")
    bannerAppIcon = String(n.appIcon || "")
    bannerUrgency = Number(n.urgency === undefined ? 1 : n.urgency)
    var summary = cleanBody(n.summary)
    // Omarchy's screenshot toast gets its own layout: thumbnail + actions.
    // Its image hint does not survive into the state file, but the click
    // command (`tensaku-edit <path>`, a JSON string) carries the file itself.
    if (/^Screenshot saved/i.test(summary)) {
      var argv = n.execArgv || []
      if (typeof argv === "string") { try { argv = JSON.parse(argv) } catch (e) { argv = [] } }
      var path = argv.length > 1 ? String(argv[argv.length - 1]) : ""
      if (path.charAt(0) === "/") {
        shotPath = path
        bannerImage = "file://" + path
        present("notification", "screenshot", "", "Screenshot", "", tk.text, 0)
        return
      }
    }
    present("notification", "notification", String(n.glyph || ""),
            summary !== "" ? summary : (n.app || "Notification"),
            cleanBody(n.body), tk.text, 0)
  }

  // Act on the toast the island is showing. The daemon moves its state file
  // out of the live directory, which the watch above turns into the island
  // moving on to the next toast, or back to the clock.
  // The file behind the screenshot banner.
  property string shotPath: ""

  function screenshotAction(act) {
    if (shotPath === "") return
    if (act === "copy")
      Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", shotPath])
    else if (act === "edit")
      invokeNotification()
    else if (act === "delete") {
      Quickshell.execDetached(["rm", "-f", "--", shotPath])
      dismissNotification()
    }
  }

  function invokeNotification() {
    if (liveNotificationId === "") return
    notifAction.command = ["omarchy-shell", "-q", "notifications", "invokeOriginal", liveNotificationId]
    notifAction.running = true
  }

  function dismissNotification() {
    if (liveNotificationId === "") { dismiss(); return }
    notifAction.command = ["omarchy-shell", "-q", "notifications", "dismissOriginal", liveNotificationId]
    notifAction.running = true
  }

  Process { id: notifAction }

  // ------------------------------------------------------------- recording
  Process {
    id: recordingProc
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(code) { status.recording = code === 0 }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!recordingProc.running) recordingProc.running = true
  }

  // ------------------------------------------------------------- dictation
  Process {
    command: ["omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(String(line))
          status.dictation = String(d.alt || d.class || "idle")
        } catch (e) { status.dictation = "idle" }
      }
    }
  }

  // ----------------------------------------------------------------- arming
  Timer {
    interval: 2500
    running: true
    onTriggered: {
      status.lastNotificationAt = Date.now()
      status.lastTrack = status.trackTitle + "\u0000" + status.trackArtist
      status.armed = true
    }
  }
}
