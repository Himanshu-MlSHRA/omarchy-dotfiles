#!/bin/bash
# omarchy-dotfiles installer. Pick one:
#
#   island   the Dynamic Island bar only (notifications, volume and brightness inside it)
#   motion   the island, plus apps flying out of it and menus growing out of it
#   full     everything, exactly like the original: theme, lock screen, wallpaper, terminals
#   remove   put back what was there before the last install
#
#   curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh | bash -s -- island
#
# Nothing is overwritten without a copy: originals go to
# ~/.local/state/omarchy-dotfiles/backup-<time>/, and `remove` restores the latest one.
set -euo pipefail

REPO_URL="${OMARCHY_DOTFILES_REPO:-https://github.com/Himanshu-MlSHRA/omarchy-dotfiles}"
MODE="${1:-}"

say()  { printf '\033[38;2;201;149;92m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---- run from a checkout (curl | bash fetches one first)
SELF="${BASH_SOURCE[0]:-}"
R=""
[[ -n $SELF && -f $SELF ]] && R=$(cd "$(dirname "$SELF")" && pwd)
if [[ -z $R || ! -d $R/config/omarchy/plugins/anshu.bar ]]; then
  command -v git >/dev/null || die "git is needed"
  tmp=$(mktemp -d)
  say "Downloading omarchy-dotfiles"
  git clone -q --depth 1 "$REPO_URL" "$tmp/omarchy-dotfiles"
  exec bash "$tmp/omarchy-dotfiles/install.sh" "$@"
fi

if [[ -z $MODE ]]; then
  echo "Which one?"
  echo "  1) island   Dynamic Island bar only"
  echo "  2) motion   island + apps fly out of it + menus grow out of it"
  echo "  3) full     everything, exactly like the original"
  read -rp "Choose 1, 2 or 3: " n </dev/tty
  case $n in 1) MODE=island ;; 2) MODE=motion ;; 3) MODE=full ;; *) die "nothing chosen" ;; esac
fi

C="$HOME/.config"
P="$C/omarchy/plugins"
STATE="$HOME/.local/state/omarchy-dotfiles"
HYPR_MAIN="$C/hypr/hyprland.lua"
HYPR_LINE='require("hypr.island") -- omarchy-dotfiles'

# ---- remove: back to how things were before the FIRST install
if [[ $MODE == remove ]]; then
  first=$(ls -1d "$STATE"/backup-* 2>/dev/null | head -n1) || true
  [[ -n $first ]] || die "nothing to remove (no backup in $STATE)"
  say "Restoring your setup from $(basename "$first")"
  omarchy bar reset >/dev/null 2>&1 || true
  cat "$STATE"/backup-*/installed-plugins | sort -u | while read -r id; do
    [[ -n $id ]] && rm -rf "${P:?}/$id"
  done
  (cd "$first/files" && find . -type f) | while read -r f; do
    mkdir -p "$(dirname "$C/${f#./}")"; cp -a "$first/files/$f" "$C/${f#./}"
  done
  # anything any install created that was not there before the first one
  cat "$STATE"/backup-*/created-files | sort -u | while read -r f; do
    [[ -n $f && ! -e $first/files/$f ]] || continue
    rm -rf "${C:?}/$f"
    rmdir -p --ignore-fail-on-non-empty "$(dirname "$C/$f")" 2>/dev/null || true
  done
  sed -i "\|$HYPR_LINE|d" "$HYPR_MAIN"
  done_dir="$STATE/removed-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$done_dir"; mv "$STATE"/backup-* "$done_dir/"
  omarchy restart shell >/dev/null 2>&1 || true
  hyprctl reload >/dev/null 2>&1 || true
  say "Done. Everything is back the way it was."
  exit 0
fi

[[ $MODE =~ ^(island|motion|full)$ ]] || die "unknown option '$MODE' (use island, motion, full or remove)"

# ---- checks
command -v omarchy >/dev/null && [[ -f $C/omarchy/shell.json ]] \
  || die "this needs Omarchy 4 (the Quickshell shell): https://omarchy.org"
[[ -f $HYPR_MAIN ]] || die "no $HYPR_MAIN"

BK="$STATE/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK/files"; : > "$BK/installed-plugins"; : > "$BK/created-files"
backup() { # backup <path relative to ~/.config>
  local f="$C/$1"
  if [[ -e $f ]]; then mkdir -p "$BK/files/$(dirname "$1")"; cp -a "$f" "$BK/files/$1"
  else echo "$1" >> "$BK/created-files"; fi
}
put_plugin() { # put_plugin <id>  (an existing folder of the same name is kept whole in the backup)
  if [[ -d $P/$1 ]]; then mkdir -p "$BK/files/omarchy/plugins"; cp -a "$P/$1" "$BK/files/omarchy/plugins/$1"
  else echo "omarchy/plugins/$1" >> "$BK/created-files"; fi
  rm -rf "${P:?}/$1"; mkdir -p "$P"; cp -a "$R/config/omarchy/plugins/$1" "$P/$1"
  echo "$1" >> "$BK/installed-plugins"
}
put_file() { # put_file <path relative to ~/.config>
  backup "$1"; mkdir -p "$(dirname "$C/$1")"; cp -a "$R/config/$1" "$C/$1"
}

backup omarchy/shell.json
backup hypr/hyprland.lua
say "Backup of your current files: $BK"

# ---- the island (every option)
say "Installing the Dynamic Island"
put_plugin anshu.bar
put_plugin anshu.notifications
put_plugin anshu.osd
put_file omarchy/hooks/post-update.d/check-island-osd
fc-list | grep -qi "Maple Mono NF" || { say "Installing the Maple Mono NF font"; omarchy pkg aur add maplemono-nf || warn "font not installed; the island falls back to your mono font"; }

# window flight on/off
backup omarchy/island.json
if [[ $MODE == island ]]; then echo '{ "windowFlight": false }' > "$C/omarchy/island.json"
else echo '{ "windowFlight": true }' > "$C/omarchy/island.json"; fi

if [[ $MODE != island ]]; then
  say "Installing the island menus"
  put_plugin anshu.menu
fi

if [[ $MODE == full ]]; then
  say "Installing the lock screen and the restyled widgets"
  for p in anshu.lock anshu.clock anshu.workspaces anshu.weather anshu.audio anshu.bluetooth \
           anshu.network anshu.power anshu.monitor anshu.agents; do put_plugin "$p"; done

  say "Installing the Shan Shui painted wallpaper"
  [[ -d $P/zed.shanshui ]] || omarchy plugin add https://github.com/zednaked/omarchy-shanshui --yes >/dev/null \
    || warn "Shan Shui could not be added"

  say "Installing the Coppernight theme (by Nishant) with these tweaks"
  if [[ ! -d $C/omarchy/themes/coppernight ]]; then
    echo "omarchy/themes/coppernight" >> "$BK/created-files"
    omarchy theme install https://github.com/hembramnishant50-glitch/omarchy-coppernight-theme.git >/dev/null 2>&1 \
      || warn "could not fetch the original theme; using the files here without its wallpapers"
  fi
  [[ -d $C/omarchy/themes/coppernight ]] || echo "omarchy/themes/coppernight" >> "$BK/created-files"
  mkdir -p "$C/omarchy/themes/coppernight"
  rm -rf "$C/omarchy/themes/coppernight/.git"   # keeps the theme's own hyprland.lua (a cloned theme drops it)
  cp -a "$R/config/omarchy/themes/coppernight/." "$C/omarchy/themes/coppernight/"

  for f in omarchy/shell.toml omarchy/hooks/theme-set.d/theme-gtk-css.sh omarchy/branding/about.txt \
           omarchy/branding/screensaver.txt hypr/looknfeel.lua alacritty/alacritty.toml foot/foot.ini \
           kitty/kitty.conf ghostty/config starship.toml; do put_file "$f"; done
fi

# ---- shortcuts and animation settings: one file of our own, one line to load it
backup hypr/island.lua
{
  echo '-- Written by omarchy-dotfiles (https://github.com/Himanshu-MlSHRA/omarchy-dotfiles).'
  echo '-- Remove it with: install.sh remove'
  echo
  echo '-- SUPER+B opens the island. While it is open: Esc goes back, Tab / arrows flip pages.'
  echo 'hl.unbind("SUPER + B")'
  echo 'o.bind("SUPER + B", "Dynamic Island", "omarchy-shell -q omarchy.bar island toggle")'
  echo 'hl.define_submap("island", function()'
  echo '  hl.bind("ESCAPE", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island back"))'
  echo '  hl.bind("SUPER + B", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island toggle"))'
  echo '  hl.bind("TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))'
  echo '  hl.bind("SHIFT + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))'
  echo '  hl.bind("SUPER + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))'
  echo '  hl.bind("SUPER + SHIFT + TAB", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))'
  echo '  hl.bind("RIGHT", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:next"))'
  echo '  hl.bind("LEFT", hl.dsp.exec_cmd("omarchy-shell -q omarchy.bar island page:prev"))'
  echo 'end)'
  if [[ $MODE != island ]]; then
    echo
    echo '-- Apps fly out of the island, so Hyprland must not move or scale windows itself;'
    echo '-- windows only fade in behind the flying picture. Workspaces slide.'
    echo 'hl.curve("islandEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })'
    echo 'hl.curve("islandEaseOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })'
    echo 'hl.curve("islandReveal", { type = "bezier", points = { { 0.55, 0 }, { 0.6, 1 } } })'
    echo 'hl.animation({ leaf = "windowsIn", enabled = false })'
    echo 'hl.animation({ leaf = "windowsOut", enabled = false })'
    echo 'hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "islandEase", style = "slide" })'
    echo 'hl.animation({ leaf = "fadeIn", enabled = true, speed = 4, bezier = "islandReveal" })'
    echo 'hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "islandEaseOut" })'
    echo 'hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "islandEase", style = "slide" })'
    echo '-- The menus animate themselves out of the island.'
    echo 'hl.layer_rule({ match = { namespace = "omarchy-menu" }, no_anim = true })'
  fi
  if [[ $MODE == full ]]; then
    echo
    echo 'o.bind("SUPER + SHIFT + L", "Lock system", "omarchy-system-lock")'
    echo 'o.bind("SUPER + ALT + W", "Shan Shui / still wallpaper", "omarchy-shell -q shanshui alternar")'
    echo 'o.bind("SUPER + ALT + SHIFT + W", "Shan Shui settings", "omarchy-shell -q omarchy.bar island detail:shanshui")'
  fi
} > "$C/hypr/island.lua"
grep -qF "$HYPR_LINE" "$HYPR_MAIN" || printf '\n%s\n' "$HYPR_LINE" >> "$HYPR_MAIN"

# ---- switch the shell over
say "Switching the shell over"
omarchy restart shell >/dev/null 2>&1 || true
for _ in $(seq 1 20); do omarchy-shell shell rescanPlugins >/dev/null 2>&1 && break; sleep 0.5; done
omarchy bar use anshu.bar >/dev/null
omarchy plugin enable anshu.notifications >/dev/null
omarchy plugin enable anshu.osd >/dev/null
omarchy plugin disable omarchy.notifications >/dev/null 2>&1 || true
omarchy plugin disable omarchy.osd >/dev/null 2>&1 || true
if [[ $MODE != island ]]; then
  omarchy plugin enable anshu.menu >/dev/null
  omarchy plugin disable omarchy.menu >/dev/null 2>&1 || true
fi
if [[ $MODE == full ]]; then
  omarchy plugin enable anshu.lock >/dev/null
  omarchy plugin disable omarchy.lock >/dev/null 2>&1 || true
  [[ -d $P/zed.shanshui ]] && omarchy plugin enable zed.shanshui >/dev/null 2>&1 || true
  omarchy theme set coppernight >/dev/null 2>&1 || warn "run: omarchy theme set coppernight"
fi
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true

echo
say "Done ($MODE). Press SUPER+B, or click the island at the top of the screen."
say "To undo: curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh | bash -s -- remove"
