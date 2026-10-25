#!/bin/bash
# How bright is the desktop right behind the island? Prints one line of JSON:
#   {"lum":0.0017,"src":"wallpaper"}   (lum 0 = black, 1 = white)
#
# The island is opaque black, so on a pitch-black backdrop it vanishes; the bar
# flips to its beige variant when lum is near 0. Two sources, in order:
#   - Shan Shui (zed.shanshui) painting, when it is on: its paper colour.
#   - The static wallpaper: the top-centre band the island sits on.
# The wallpaper measurement is cached per file + mtime, so the regular poll is a
# readlink and a stat, and ImageMagick only runs when the wallpaper changes.

state="${XDG_STATE_HOME:-$HOME/.local/state}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
cache="${XDG_RUNTIME_DIR:-/tmp}/anshu-island-backdrop"
colors="$state/omarchy/current/theme/colors.toml"

hex_lum() {
  local h="${1#\#}"
  [[ "$h" =~ ^[0-9A-Fa-f]{6}$ ]] || { echo ""; return; }
  awk -v r=$((16#${h:0:2})) -v g=$((16#${h:2:2})) -v b=$((16#${h:4:2})) \
    'BEGIN { printf "%.4f", (0.2126*r + 0.7152*g + 0.0722*b) / 255 }'
}

theme_color() {
  sed -nE "s/^$1[[:space:]]*=[[:space:]]*\"(#[0-9A-Fa-f]{6})\".*/\1/p" "$colors" 2>/dev/null | head -1
}

json_field() {
  # $1 file, $2 key -> raw value (string without quotes, or true/false)
  sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?.*/\1/p" "$1" 2>/dev/null | head -1
}

# --- Shan Shui -------------------------------------------------------------
estado="$state/zed.shanshui/estado.json"
if [[ -f "$estado" ]] && [[ "$(json_field "$estado" ativo)" != "false" ]] \
   && [[ -d "$config/omarchy/plugins/zed.shanshui" ]]; then
  cfg="$config/zed.shanshui/config.json"
  papel=$(json_field "$cfg" papel); papel=${papel:-background}
  tinta=$(json_field "$cfg" tinta); tinta=${tinta:-foreground}
  paper="$papel"
  [[ "$(json_field "$cfg" inverter)" == "true" ]] && paper="$tinta"
  [[ "$paper" =~ ^# ]] || paper=$(theme_color "$paper")
  lum=$(hex_lum "$paper")
  if [[ -n "$lum" ]]; then
    printf '{"lum":%s,"src":"shanshui"}\n' "$lum"
    exit 0
  fi
fi

# --- static wallpaper --------------------------------------------------------
wall=$(readlink -f "$state/omarchy/current/background" 2>/dev/null)
if [[ -z "$wall" || ! -f "$wall" ]]; then
  echo '{"lum":1,"src":"none"}'
  exit 0
fi
key="$wall:$(stat -c %Y "$wall" 2>/dev/null)"
if [[ -f "$cache" ]] && [[ "$(head -1 "$cache")" == "$key" ]]; then
  lum=$(sed -n 2p "$cache")
else
  lum=$(nice -n 19 magick "$wall" -gravity North -crop 50%x8%+0+0 +repage \
        -resize 1x1\! -colorspace gray -format "%[fx:mean]" info: 2>/dev/null)
  [[ "$lum" =~ ^[0-9.]+$ ]] || lum=1
  printf '%s\n%s\n' "$key" "$lum" > "$cache"
fi
printf '{"lum":%s,"src":"wallpaper"}\n' "$lum"
