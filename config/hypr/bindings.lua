-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Dynamic Island: open it, press again to close (Escape steps back a level).
o.bind("SUPER + B", "Panacea / Dynamic Island", os.getenv("HOME") .. "/.local/bin/panacea-mode panel")

-- While the island is open the shell switches Hyprland into this submap, so
-- Escape steps back a level (detail -> cards -> closed). Keys that are not
-- bound here still reach the focused window, so typing is unaffected; a
-- keyboard grab on the island's own surface would instead have disabled its
-- click-through mask and made the cards unclickable.
hl.define_submap("island", function()
  hl.bind("ESCAPE", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island back"))
  hl.bind("SUPER + B", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island toggle"))
  -- Pages: overview <-> media / system / toggles.
  hl.bind("SHIFT + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))
  hl.bind("TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))
  -- Same with SUPER still held from SUPER + B, and with the arrow keys.
  hl.bind("SUPER + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))
  hl.bind("SUPER + SHIFT + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))
  hl.bind("RIGHT", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))
  hl.bind("LEFT", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))
end)


-- Lock (same as the default SUPER+CTRL+L).
o.bind("SUPER + SHIFT + L", "Lock system", "omarchy-system-lock")

-- OmaWhatsApp: open/close the native WhatsApp app (replaces the default Omawrite bind).
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "OmaWhatsApp", "omarchy-shell io.github.moizibnyousaf.omawhatsapp toggleApp '{}'")

-- Shan Shui wallpaper: switch between the painted landscape and the static wallpaper,
-- or open its settings inside the island.
o.bind("SUPER + ALT + W", "Shan Shui / static wallpaper", "omarchy-shell -q shanshui alternar")
o.bind("SUPER + ALT + SHIFT + W", "Shan Shui settings", "omarchy-shell -q omarchy.bar island detail:shanshui")
