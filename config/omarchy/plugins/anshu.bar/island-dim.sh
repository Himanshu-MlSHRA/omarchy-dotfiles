#!/bin/bash
# Gently dims the screen for a focus break and puts it back afterwards.
#   island-dim.sh dim | restore
# The pre-dim brightness is kept in $XDG_RUNTIME_DIR, so `dim` is idempotent
# (a shell restart mid-break does not save the dimmed level as the original).
set -u
F="${XDG_RUNTIME_DIR:-/tmp}/anshu-island-dim"
command -v brightnessctl >/dev/null || exit 0

fade() { # from to
  local from=$1 to=$2 i v
  for i in $(seq 1 12); do
    v=$(( from + (to - from) * i / 12 ))
    brightnessctl -q set "$v"
    sleep 0.04
  done
}

cur=$(brightnessctl -m | cut -d, -f3)
case "${1:-}" in
dim)
  [[ -f $F ]] && exit 0
  echo "$cur" >"$F"
  target=$(( cur * 50 / 100 ))
  (( target < 1 )) && target=1
  fade "$cur" "$target"
  ;;
restore)
  [[ -f $F ]] || exit 0
  orig=$(cat "$F")
  rm -f "$F"
  fade "$cur" "$orig"
  ;;
esac
