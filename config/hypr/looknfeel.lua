-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- macOS-style: menu bar slides in from the top, launcher/menus pop in smoothly.
-- (Overrides Omarchy's default no_anim rules for these shell surfaces.)
hl.layer_rule({ match = { namespace = "omarchy-bar" }, no_anim = false, animation = "slide top" })
-- Menus drop out of the Dynamic Island at the top edge instead of popping in.
-- omarchy-menu animates itself (anshu.menu grows out of the island), so the
-- compositor must not animate the layer on top of that.
hl.layer_rule({ match = { namespace = "omarchy-menu" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^(omarchy-emojis|omarchy-clipboard)$" }, no_anim = false, animation = "slide top" })
hl.layer_rule({ match = { namespace = "omarchy-image-selector" }, no_anim = false, animation = "popin 90%" })

-- Dim unfocused windows so the active one stands out (fades smoothly via fadeDim).
hl.config({
  decoration = {
    dim_inactive = true,
    dim_strength = 0.18,
  },
})

-- See-through apps with blur behind them (focused, unfocused).
-- Apps that opt out of default-opacity (browsers/video, etc.) stay solid.
o.window({ tag = "default-opacity" }, { opacity = "0.90 0.82" })

-- Spotify stays solid (the 0.80 glass made its text look washed out); a hint
-- of see-through only when unfocused.
o.window("^(Spotify|spotify)$", { tag = "-default-opacity", opacity = "1.0 0.96" })

-- Blur behind the translucent launcher card, but not the faint full-screen scrim.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })

-- The Dynamic Island is opaque black (it imitates a bezel cut-out), so there is
-- nothing to blur behind it. Re-enable this only if IslandTokens.surfaceAlpha
-- is dropped below 1 for a translucent variant.
-- hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.12 })
