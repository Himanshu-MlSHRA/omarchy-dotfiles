#!/bin/bash
# Prints the live notification state as one JSON line:
#   {"count": <toasts on screen>, "newest": <newest toast's state file> | null}
# The notification daemon keeps exactly one file per live toast in this
# directory and moves it to history/ the moment it expires, is dismissed, or is
# acted on, so the directory *is* "what is on screen right now". The daemon's
# own toast window is hidden; the island is the only place these are drawn.
set -uo pipefail
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/notifications"
shopt -s nullglob
files=("$dir"/*.json)
count=${#files[@]}
newest=null
if (( count > 0 )); then
  f=$(printf '%s\n' "${files[@]}" | sort | tail -n1)
  newest=$(jq -c . "$f" 2>/dev/null) || newest=null
  [[ -n $newest ]] || newest=null
fi
printf '{"count":%d,"newest":%s}\n' "$count" "$newest"
