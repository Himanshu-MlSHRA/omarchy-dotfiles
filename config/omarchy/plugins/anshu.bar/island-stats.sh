#!/bin/bash
# One JSON line of live system load for the island's System card. Polled
# every 2s, and only while the island is open.
#   cpu   busy % over a 250ms window (/proc/stat)
#   mem   used / total GiB (MemTotal - MemAvailable)
#   temp  CPU package °C (x86_pkg_temp, else the first thermal zone)
#   disk  used % and free GiB of /
#   up    uptime, e.g. "3h 12m"
set -uo pipefail
read -r _ a1 b1 c1 d1 e1 f1 g1 h1 _ < /proc/stat
sleep 0.25
read -r _ a2 b2 c2 d2 e2 f2 g2 h2 _ < /proc/stat
idle=$(( (d2 + e2) - (d1 + e1) ))
total=$(( (a2+b2+c2+d2+e2+f2+g2+h2) - (a1+b1+c1+d1+e1+f1+g1+h1) ))
cpu=0; (( total > 0 )) && cpu=$(( (100 * (total - idle)) / total ))

mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
mem_used=$(awk -v t="$mt" -v a="$ma" 'BEGIN{printf "%.1f", (t-a)/1048576}')
mem_total=$(awk -v t="$mt" 'BEGIN{printf "%.0f", t/1048576}')
mem_pct=$(( (100 * (mt - ma)) / mt ))

temp=0
for z in /sys/class/thermal/thermal_zone*; do
  [[ $(<"$z/type") == x86_pkg_temp ]] && { temp=$(( $(<"$z/temp") / 1000 )); break; }
done
(( temp == 0 )) && [[ -r /sys/class/thermal/thermal_zone0/temp ]] && temp=$(( $(</sys/class/thermal/thermal_zone0/temp) / 1000 ))

read -r disk_pct disk_free < <(df -B1 --output=pcent,avail / | awk 'NR==2{gsub("%","",$1); printf "%d %.0f\n", $1, $2/1073741824}')

s=$(cut -d. -f1 /proc/uptime); d=$((s/86400)); h=$(((s%86400)/3600)); m=$(((s%3600)/60))
if (( d > 0 )); then up="${d}d ${h}h"; elif (( h > 0 )); then up="${h}h ${m}m"; else up="${m}m"; fi

printf '{"cpu":%d,"memPct":%d,"memUsed":"%s","memTotal":"%s","temp":%d,"diskPct":%d,"diskFree":%d,"up":"%s"}\n' \
  "$cpu" "$mem_pct" "$mem_used" "$mem_total" "$temp" "$disk_pct" "$disk_free" "$up"
