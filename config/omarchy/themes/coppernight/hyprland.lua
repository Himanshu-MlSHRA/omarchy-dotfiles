local active_border_color = "rgb(E1DCC9)"
local inactive_border_color = "rgb(412D15)"

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 14,
    border_size = 2,
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
    resize_on_border = false,
    allow_tearing = false,
  },

  decoration = {
    rounding = 16,
    rounding_power = 2.0,

    active_opacity = 1.0,
    inactive_opacity = 0.96,
    fullscreen_opacity = 1.0,

    dim_inactive = false,

    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = "rgba(00000066)",
      color_inactive = "rgba(00000033)",
      offset = "0 8",
      scale = 1.0,
    },

    blur = {
      enabled = true,
      size = 10,
      passes = 2,
      contrast = 1.0,
      brightness = 1.05,
      vibrancy = 0.18,
      vibrancy_darkness = 0.05,
      noise = 0.015,
      ignore_opacity = true,
      new_optimizations = true,
      xray = false,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
    groupbar = {
      gradients = true,
      gradient_rounding = 14,
      gradient_round_only_edges = true,
    },
  },

  animations = {
    enabled = true,
  },

  misc = {
    animate_manual_resizes = true,
    animate_mouse_windowdragging = true,
  },
})

-- macOS-style curves: fast start, long gentle settle, no snap-back.
hl.curve("macEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })        -- easeOutQuint
hl.curve("macEaseOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })      -- easeOutExpo
hl.curve("macSpring", { type = "bezier", points = { { 0.34, 1.26 }, { 0.64, 1 } } })   -- soft overshoot
hl.curve("macEaseIn", { type = "bezier", points = { { 0.45, 0 }, { 0.2, 1 } } })       -- smooth close (ease-in-out)

-- Speed is in deciseconds (4 = 400ms). Tuned snappy: same macOS curves, ~40% shorter.
-- Windows come out of the Dynamic Island: the shell (anshu.bar IslandFlight)
-- throws a pane from the island to the window's rect, so Hyprland must not
-- move or scale windows itself. The window fades in on "islandReveal", a
-- gentle ease-in that trails the pane (fadeIn also runs when windows reappear,
-- e.g. after fullscreen, so it must not hold them invisible); on close it
-- vanishes quickly under the pane that flies back into the island.
hl.curve("islandReveal", { type = "bezier", points = { { 0.55, 0 }, { 0.6, 1 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "macSpring", style = "popin 100%" })
hl.animation({ leaf = "windowsIn", enabled = false })
hl.animation({ leaf = "windowsOut", enabled = false })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "macEase", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "macEaseOut" })
hl.animation({ leaf = "borderangle", enabled = false })
hl.animation({ leaf = "fade", enabled = true, speed = 4.5, bezier = "macEaseOut" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 4, bezier = "islandReveal" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "macEaseOut" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 3.5, bezier = "macEaseOut" })
-- Workspace switching slides like macOS Spaces.
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "macEase", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "macEase", style = "slidevert" })
hl.animation({ leaf = "layers", enabled = true, speed = 4.5, bezier = "macEase", style = "fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4.5, bezier = "macEaseOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3.5, bezier = "macEaseIn", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 4, bezier = "macEaseOut" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3.5, bezier = "macEaseIn" })
