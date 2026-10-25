#!/bin/bash
# Copy the active theme's gtk.css into GTK3/GTK4 user config (Nautilus etc.).
# Only manages files it created (marked with the OMARCHY- header).
THEME_CSS="$HOME/.local/state/omarchy/current/theme/gtk.css"
for dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
  target="$dir/gtk.css"
  mkdir -p "$dir"
  if [[ -f $target ]] && ! head -1 "$target" | grep -q 'OMARCHY-'; then
    continue # user's own gtk.css, leave it alone
  fi
  if [[ -f $THEME_CSS ]] && head -1 "$THEME_CSS" | grep -q 'OMARCHY-'; then
    cp "$THEME_CSS" "$target"
  else
    rm -f "$target"
  fi
done
# Restart Nautilus so it picks up the new styling (it re-launches on demand).
pkill -x nautilus 2>/dev/null || true
