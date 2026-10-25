# Dynamic Island

The top bar is a black notch flush with the screen's top edge that changes
shape and content, modelled on [Atoll](https://github.com/Ebullioscopic/Atoll).
It lives inside this bar plugin (`anshu.bar`), so it keeps everything the stock
bar already does: per-monitor surfaces, `omarchy toggle bar`, theme colours,
and the shell's plugin/panel machinery.

The outline is a direct port of Atoll's `NotchShape`: the top corners curve
*outward* into the bezel, the bottom corners are a large convex radius, and
both radii animate so the collapsed pill and the open panel read as one object
changing shape.

## Files

| File | Role |
|---|---|
| `IslandTokens.qml` | **The design system.** Every dimension, colour, radius, easing curve and duration. Tune the island here. |
| `IslandGlass.qml` | The notch outline (Atoll `NotchShape` port) and its shadow. Draws no content. |
| `IslandClock.qml` | `WED · SEP 23 · 7:41 PM`. One `SystemClock` at minute precision. |
| `IslandStatus.qml` | State machine for chips (ongoing states) and banners (momentary ones). |
| `IslandSystem.qml` | Live readouts: audio, battery, Bluetooth, Wi-Fi, weather, Claude Code. |
| `IslandTray.qml` | The open surface: status strip, Claude card, four control cards. |
| `IslandCard.qml` | A lifted-black content card. |
| `IslandTile.qml` | One control card: glyph, name, value, detail. |
| `IslandMeter.qml` | A labelled usage allowance with a fill bar and reset time. |
| `IslandDetail.qml` | The in-island detail views for all five cards. |
| `IslandRow.qml` | A label/value line inside a detail view. |
| `IslandListRow.qml` | A selectable line: network, device, output. |
| `island-network.sh` | Wi-Fi/Ethernet probe. Kept out of QML so the quoting is testable. |
| `island-notification.sh` | Prints the newest on-screen notification. |
| `Bar.qml` | Hosts all of the above in its `horizontalBar` component. |

## States

```
collapsed ──click / SUPER+B──▶ open ──click a card──▶ detail
    ▲                            ▲                      │
    └──── click away / Esc ──────┴──────── Esc ──────────┘
```

- **Collapsed** — day, date, time, plus a chip per ongoing state.
- **Open** — the clock is *gone*. The strip carries weather only; below it,
  Claude Code's two usage allowances and the Wi-Fi, Bluetooth, Sound and
  Battery cards.
- **Detail** — clicking a card swaps the whole surface for that card's detail,
  in place, and the island grows to `detailHeight`. Nothing about the island
  ever opens outside the island.
- **Banner** — a momentary takeover: DND, night light, stay awake, recording,
  dictation, a track change, a notification, a battery or network change.
  Dropped rather than queued while the island is open.
- **Chips** — recording, dictation, playing media, silent, stay awake, night
  light. Recording and dictation also tint the surface.

### What each detail shows

| Card | Detail |
|---|---|
| Claude Code | Both allowances as meters; today's prompts, sessions and tokens; seven days of token volume as bars |
| Wi-Fi | SSID, signal, rate, band, IP, gateway, adapter; the network list, click a **saved** network to join |
| Bluetooth | Adapter state and counts, an on/off row, and the paired-device list with connect/disconnect and device battery |
| Sound | Volume slider, mute, and every output with the active one marked |
| Battery | Percentage, charge state, time, draw, health, model |

Joining an unsaved secured network needs a password prompt the island has no
business owning, so those rows are inert and marked with a lock.

## Interaction

| Gesture | Effect |
|---|---|
| `SUPER + B` | Open; press again to close |
| Click the collapsed island | Open |
| Click a card | Its detail view, in place |
| **Escape** | One step back: detail → cards → closed |
| Click anywhere outside | Close |
| Scroll the Sound card | Volume, 5% a step |
| Right click during a banner | Dismiss it without opening |

Nothing times out. The island stays open until it is dismissed.

Click-away works through a transparent full-screen surface that exists only
while the island is open, masked to the three strips *around* the island — so
clicks on a card reach the bar underneath and everything else closes it.

Escape comes from a Hyprland submap (`island`, defined in `bindings.lua`) that
the shell switches into on open and out of on close. Two things forced that:
a layer surface with `WlrKeyboardFocus.Exclusive` **ignores its input mask**,
so holding the keyboard on the scrim made it swallow every click meant for a
card; and a submap leaves unbound keys going to the focused window, so typing
is unaffected while the island is open.

```bash
omarchy-shell omarchy.bar island toggle
# expand | collapse | toggle | back | dismiss | status | detail:<network|bluetooth|audio|battery|claude>
```

The `SUPER + B` binding lives in `~/.config/hypr/bindings.lua`.

## Customising

Almost everything is one number in `IslandTokens.qml`:

- size — `collapsedHeight`, `expandedWidth`, `expandedHeight`,
  `expandedPadX` / `PadTop` / `PadBottom`, `minWidth`
- shape — `collapsedTopRadius` / `collapsedBottomRadius`,
  `expandedTopRadius` / `expandedBottomRadius` (Atoll's two-radius notch)
- surface — `surfaceAlpha` (1.0 = the opaque bezel look), `card`, `cardHover`,
  `cardPressed`, `cardRadius`, `cardGap`, `cardPad`, `shadowBlur`, `shadowAlpha`
- motion — `expandDuration`, `collapseDuration`, `radiusDuration`,
  `springCurve`, `stagger`, `contentInDelay`, `contentOutDuration`
- behaviour — `bannerDuration`, `notificationDuration`, `autoExpandOnEvents`,
  `volumeBanners`
- `detailHeight` is the size the island grows to for a detail view;
  `overscan` is how far the surface is drawn above the screen's first row so
  the antialiased top edge never shows as a hairline of wallpaper

Values are authored against a 12px shell font and scale with
`[font] base-size`, so they hold at any font size, resolution or fractional
scale.

For a translucent variant: drop `surfaceAlpha` below 1 and uncomment the
`omarchy-bar` blur layer rule in `~/.config/hypr/looknfeel.lua`. It is
commented out because an opaque surface makes the compositor's blur pass
pure waste.

The open layout is laid out once at its final size and the pane is animated
around it (see `contentWidth` / `trayHeight` in `Bar.qml`). Re-running the card
layout on every frame of the morph is what made earlier versions stutter, so
keep new content fixed-size rather than anchored to the pane.

Two layer-shell traps worth knowing before touching the scrim: a `PanelWindow`'s
own `width`/`height` read 0 while it is being set up, and a `Region` whose base
is empty is treated as *no mask at all* — so region maths must come from a
full-fill child item, and a `Subtract` child of an empty base is silently
dropped (the scrim is built as three strips around the island for that reason).

## Known limits

- While the island is open Hyprland is in the `island` submap, so your other
  global keybindings are inactive until it closes. `SUPER + B` and Escape are
  bound inside the submap, and unbound keys still reach the focused window.
- Joining a new secured Wi-Fi network is not supported from the island; use
  `nmtui` or the network plugin's own panel for that.
- **Screen recording** is the one polled source (4s `pgrep`).
  gpu-screen-recorder publishes no signal and its marker file lives in `/tmp`.
- **Volume and brightness banners** are off by default (`volumeBanners`):
  Omarchy's OSD plugin already shows them. Turn them on together with
  `omarchy plugin disable omarchy.osd` or you will see each change twice.
- **Brightness** has no event source; `brightnessctl` would have to be polled,
  so it is not wired. `IslandStatus.qml`'s system-events `Connections` block is
  where it would go.
- **Reminders** are read through `omarchy-reminder show --json`, which is a
  poll, so they are not wired either; the same extension point applies.
- Notifications are drawn **only** by the island. `anshu.notifications` keeps
  delivery, timers, history and DND but its corner toast window is hidden
  (`islandOwnsPopups` in its `Service.qml`). A notification banner stays for as
  long as the toast is live (8 s normal, 5 s low, critical until acted on);
  click = open it, right click = dismiss. `+N` = more waiting behind it.
  The island acts through `notifications invokeOriginal|dismissOriginal <id>`.
- Volume, brightness, mic, keyboard light and output switching arrive as
  `omarchy-shell osd show`. `omarchy.osd` is disabled in shell.json and
  `IslandStatus.qml` answers the `osd` IPC target itself (level-bar banner).
  IPC handlers only register on `omarchy restart shell`, not on hot reload.
- The launcher/menus (SUPER+SPACE, SUPER+ALT+SPACE, SUPER+ESCAPE) are the
  `anshu.menu` clone. Its card hangs under the island and opens/closes with the
  macOS-Dock genie from ~/Work/Portfolio's résumé (`anshu.menu/genie/`). The
  mouth is read from `omarchy-shell omarchy.bar island geometry`. Colours live in
  `~/.config/omarchy/shell.toml` `[menu]`.
- The open island's lower half is `IslandExtras.qml`: Now Playing (MPRIS, with
  prev/play/next and click-to-seek), System (CPU, memory, temperature, disk,
  uptime from `island-stats.sh`, polled every 2s only while open; click opens
  btop), and quick toggles (Silent, Night Light, Stay Awake, Screenshot,
  Record, Lock).

## Window flights (IslandFlight.qml, island-window.sh)

Windows open and close through the genie with their **own live picture**:

- open: on `openwindow` the window is hidden at once by `island-window.sh hide`
  (Hyprland `set_prop` opacity override — instant, no fade; the original values
  go to `$XDG_RUNTIME_DIR/omarchy-island-hidden/`). A `ScreencopyView` of its
  toplevel (captures fine while hidden) is drawn through `genie/` from the
  island's middle onto the window's rect, then `show` restores it and the
  picture is dropped the next frame. Not ready within 900 ms -> shown as-is.
- close: the focused window is snapshotted (focus change + every 1.2 s) into a
  frozen `ShaderEffectSource`; on `closewindow` that is pulled into the island.
- The flight layer stays mapped (captures only run in a mapped window); its
  1px input region sits under the island.
- `recover` runs at shell start, so a restart mid-flight never strands a window.
- Mouth = half the island's body width, centred, so the island keeps its
  rounded corners (anshu.menu uses the same formula).
- Test: `omarchy-shell omarchy.flight window open|close 0xADDR` on an existing
  window (close needs it to be the focused one).

## Focus sessions and Claude alerts

- The island has **two pages**. Page 2 (Tab) = Focus card · System · quick toggles.
  Now Playing was removed (track changes still show as a chip and a banner).
- `IslandFocus.qml` — the focus state: `workMin` / `breakMin` / `rounds`, phases
  idle → work → break → … → work N → done, flowing on their own with a chime and
  a banner at each change. Wall-clock anchored and saved to
  `~/.local/state/omarchy/island-focus.json`, so it survives `omarchy restart shell`.
- `IslandFocusCard.qml` — idle: the plan as three pills (click − / +, or scroll;
  work moves in 5 min steps). Running: countdown, "until h:mm", play/pause · skip ·
  reset, a progress line (copper for work, cream for break) and one dot per round.
  The plan is locked while a session runs.
- Collapsed island: during **work** it shows only the countdown (clock and chips
  hidden); during a **break** the normal clock returns with a copper `󰾨 MM:SS`.
  A thin line along the bottom edge fills as the phase runs (copper work, cream break).
- Work phases turn on Silent (DND) and breaks/ending turn it off again — only if the
  timer was the one that turned it on (`silencedByFocus`); those flips skip their own
  banner (`dndFlippedAt`) so the phase banner stays visible.
- Breaks dim the screen to 50% with a short fade (`island-dim.sh dim|restore`,
  original level kept in `$XDG_RUNTIME_DIR/anshu-island-dim`, idempotent across restarts).
- Claude Code usage: `IslandStatus.claudeBand` banners once when the 5-hour or
  weekly allowance crosses 80% (accent) and 95% (danger). The first reading only
  sets the baseline.

```bash
omarchy-shell omarchy.bar focus start | pause | resume | toggle | reset | skip | set <work> <break> <rounds> | status
```
