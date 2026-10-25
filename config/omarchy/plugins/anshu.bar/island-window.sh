#!/usr/bin/env bash
# Hides a window while IslandFlight draws its live picture coming out of the
# island, and puts it back exactly as it was.
#
#   island-window.sh hide 0xADDR    -> prints the window's active opacity
#   island-window.sh show 0xADDR
#   island-window.sh recover        (shell start: un-hide anything left hidden)
#
# Hyprland applies these props instantly (no fade), so the hand-off from the
# picture to the real window is a single frame. The original values are kept
# in a state file, so a shell restart mid-flight can never strand a window
# invisible.
set -u
state="${XDG_RUNTIME_DIR:-/tmp}/omarchy-island-hidden"
mkdir -p "$state"

prop() { hyprctl getprop "address:$1" "$2" 2>/dev/null | head -n1; }
setp() { printf 'dispatch hl.dsp.window.set_prop({ prop = "%s", value = "%s", window = "address:%s" }) ; ' "$2" "$3" "$1"; }

case "${1:-}" in
  hide)
    a="$2"
    f="$state/$a"
    if [[ ! -f $f ]]; then
      op=$(prop "$a" opacity); oi=$(prop "$a" opacity_inactive)
      oo=$(prop "$a" opacity_override); io=$(prop "$a" opacity_inactive_override)
      [[ $op =~ ^[0-9.]+$ ]] || op=1
      [[ $oi =~ ^[0-9.]+$ ]] || oi=1
      [[ $oo == true ]] && oo=1 || oo=0
      [[ $io == true ]] && io=1 || io=0
      printf '%s %s %s %s\n' "$op" "$oi" "$oo" "$io" > "$f"
    fi
    hyprctl --batch "$(setp "$a" opacity_override 1)$(setp "$a" opacity 0)$(setp "$a" opacity_inactive_override 1)$(setp "$a" opacity_inactive 0)" >/dev/null
    read -r op _ < "$f"
    echo "$op"
    ;;
  show)
    a="$2"
    f="$state/$a"
    [[ -f $f ]] || exit 0
    read -r op oi oo io < "$f"
    rm -f "$f"
    hyprctl --batch "$(setp "$a" opacity "$op")$(setp "$a" opacity_inactive "$oi")$(setp "$a" opacity_override "$oo")$(setp "$a" opacity_inactive_override "$io")" >/dev/null
    ;;
  recover)
    for f in "$state"/0x*; do
      [[ -f $f ]] && "$0" show "$(basename "$f")"
    done
    ;;
esac
exit 0
