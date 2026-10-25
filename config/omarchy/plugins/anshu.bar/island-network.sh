#!/bin/bash
# Network probe for the island. Kept out of the QML so the quoting stays
# readable and every mode can be run by hand.
#
#   status   kind<TAB>name<TAB>signal            (kind: wifi|ethernet|disconnected)
#   detail   key<TAB>value per line              (ip, gateway, freq, speed, iface)
#   list     active<TAB>ssid<TAB>signal<TAB>secured<TAB>known   per network
set -uo pipefail

active_row() {
  nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null \
    | awk -F: '$3=="connected" && ($2=="wifi" || $2=="ethernet") {print; exit}'
}

row=$(active_row)
iface=${row%%:*}
kind=$(printf '%s' "${row#*:}" | cut -d: -f1)

case "${1:-status}" in
status)
  if [[ -z $row ]]; then
    printf 'disconnected\t\t-1\n'
    exit 0
  fi
  if [[ $kind == ethernet ]]; then
    printf 'ethernet\t%s\t-1\n' "$iface"
    exit 0
  fi
  nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list ifname "$iface" 2>/dev/null \
    | awk -F: '$1=="yes" { printf "wifi\t%s\t%s\n", $2, $3; found=1; exit }
               END { if (!found) printf "wifi\t\t-1\n" }'
  ;;

detail)
  [[ -z $row ]] && exit 0
  printf 'iface\t%s\n' "$iface"
  nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,GENERAL.CONNECTION dev show "$iface" 2>/dev/null \
    | while IFS=: read -r key value; do
        case "$key" in
          IP4.ADDRESS*) printf 'ip\t%s\n' "${value%%/*}" ;;
          IP4.GATEWAY)  [[ -n $value ]] && printf 'gateway\t%s\n' "$value" ;;
          GENERAL.CONNECTION) printf 'profile\t%s\n' "$value" ;;
        esac
      done
  if [[ $kind == wifi ]]; then
    nmcli -t -f ACTIVE,RATE,FREQ dev wifi list ifname "$iface" 2>/dev/null \
      | awk -F: '$1=="yes" { printf "rate\t%s\nfreq\t%s\n", $2, $3; exit }'
  else
    nmcli -t -f CAPABILITIES.SPEED dev show "$iface" 2>/dev/null \
      | awk -F: 'NF>1 { printf "rate\t%s\n", $2; exit }'
  fi
  ;;

list)
  # Saved profiles first, so the list can mark which networks will just work.
  known=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2 ~ /wireless/ {print $1}')
  nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null \
    | awk -F: -v known="$known" '
        BEGIN { n = split(known, k, "\n"); for (i = 1; i <= n; i++) saved[k[i]] = 1 }
        $2 == "" { next }
        seen[$2]++ { next }
        {
          secured = ($4 == "" || $4 == "--") ? 0 : 1
          printf "%s\t%s\t%s\t%s\t%s\n", ($1 == "yes" ? 1 : 0), $2, $3, secured, (saved[$2] ? 1 : 0)
        }' \
    | sort -t$'\t' -k1,1nr -k3,3nr \
    | head -n 24
  ;;
esac
exit 0
