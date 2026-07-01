#!/usr/bin/env bash
set -u

STATE_DIR=/run/batenergy
STATE_FILE=${STATE_DIR}/state

state=${1:-}
sleep_type=${2:-unknown}

first_battery() {
  local battery
  for battery in /sys/class/power_supply/BAT*; do
    [[ -d "$battery" ]] || continue
    printf '%s\n' "$battery"
    return 0
  done
  return 1
}

first_adapter() {
  local adapter
  for adapter in /sys/class/power_supply/A*; do
    [[ -r "$adapter/online" ]] || continue
    printf '%s\n' "$adapter"
    return 0
  done
  return 1
}

read_int() {
  local file=$1 value
  [[ -r "$file" ]] || return 1
  read -r value < "$file" || return 1
  [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

read_energy_mwh() {
  local battery=$1 when=$2 value voltage

  if value=$(read_int "$battery/energy_$when"); then
    printf '%s\n' $(( value / 1000 ))
    return 0
  fi

  value=$(read_int "$battery/charge_$when") || return 1
  voltage=$(read_int "$battery/voltage_now") || return 1
  printf '%s\n' $(( value * voltage / 1000000000 ))
}

battery=$(first_battery) || exit 0
now=$(date +%s)
energy_now=$(read_energy_mwh "$battery" now) || exit 0
energy_full=$(read_energy_mwh "$battery" full) || exit 0

if adapter=$(first_adapter); then
  if [[ $(read_int "$adapter/online" || printf 0) -eq 1 ]]; then
    echo "Currently on mains."
  else
    echo "Currently on battery."
  fi
fi

case "$state" in
  pre)
    echo "Saving time and battery energy before sleeping ($sleep_type)."
    install -d -m 0700 -o root -g root "$STATE_DIR"
    tmpfile=$(mktemp "${STATE_DIR}/state.XXXXXX") || exit 1
    {
      printf '%s\n' "$now"
      printf '%s\n' "$energy_now"
    } > "$tmpfile"
    chmod 0600 "$tmpfile"
    mv -f "$tmpfile" "$STATE_FILE"
    ;;
  post)
    [[ -r "$STATE_FILE" ]] || exit 0
    {
      read -r prev
      read -r energy_prev
    } < "$STATE_FILE" || exit 0
    rm -f -- "$STATE_FILE"

    [[ "$prev" =~ ^[0-9]+$ ]] || exit 0
    [[ "$energy_prev" =~ ^-?[0-9]+$ ]] || exit 0

    time_diff=$(( now - prev ))
    (( time_diff > 0 )) || exit 0

    days=$(( time_diff / (3600 * 24) ))
    hours=$(( time_diff % (3600 * 24) / 3600 ))
    minutes=$(( time_diff % 3600 / 60 ))
    echo "Duration of $days days $hours hours $minutes minutes sleeping ($sleep_type)."

    energy_diff=$(( energy_now - energy_prev ))
    avg_rate=$(( energy_diff * 3600 / time_diff ))
    energy_diff_pct=$(awk -v diff="$energy_diff" -v full="$energy_full" 'BEGIN { if (full > 0) printf "%.1f", diff * 100 / full; else printf "n/a" }')
    avg_rate_pct=$(awk -v rate="$avg_rate" -v full="$energy_full" 'BEGIN { if (full > 0) printf "%.2f", rate * 100 / full; else printf "n/a" }')
    echo "Battery energy change of ${energy_diff_pct}% (${energy_diff} mWh) at an average rate of ${avg_rate_pct}%/h (${avg_rate} mW)."
    ;;
esac
