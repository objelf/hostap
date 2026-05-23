#!/bin/bash
set -euo pipefail

SNIFFER=wlx000c43baabd4
MON=mon0
DWELL=1

sudo nmcli dev disconnect "$SNIFFER" 2>/dev/null || true
sudo nmcli dev set "$SNIFFER" managed no 2>/dev/null || true

sudo ip link set "$SNIFFER" down 2>/dev/null || true
sudo ip link set "$MON" down 2>/dev/null || true
sudo iw dev "$MON" del 2>/dev/null || true

PHY=$(iw dev "$SNIFFER" info | awk '/wiphy/ {print "phy"$2}')
echo "[INFO] PHY=$PHY"

sudo iw phy "$PHY" interface add "$MON" type monitor flags fcsfail control otherbss
sudo ip link set "$MON" up

CHANNELS=$(iw phy "$PHY" channels | awk '
  /\* [0-9]+ MHz/ && $0 !~ /disabled/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "MHz")
        print $(i-1)
    }
  }
')

get_inuse_survey_block()
{
    sudo iw dev "$MON" survey dump | awk '
      /^Survey data from/ {
        if (block ~ /\[in use\]/)
          print block
        block = $0 "\n"
        next
      }
      {
        block = block $0 "\n"
      }
      END {
        if (block ~ /\[in use\]/)
          print block
      }
    '
}

get_inuse_survey_values()
{
    get_inuse_survey_block | awk '
      /frequency:/ {
        freq=$2
        inuse=($0 ~ /\[in use\]/) ? "yes" : "no"
      }
      /channel active time:/ {
        active=$4
      }
      /channel busy time:/ {
        busy=$4
      }
      /channel receive time:/ {
        rx=$4
      }
      /channel transmit time:/ {
        tx=$4
      }
      /noise:/ {
        noise=$2
      }
      END {
        if (noise == "")
          noise="NA"
        printf "%s %s %s %s %s %s %s\n", freq, inuse, active, busy, rx, tx, noise
      }
    '
}

get_mon_channel()
{
    iw dev "$MON" info | awk '
      /channel/ {
        # Example:
        # channel 1 (2412 MHz), width: 20 MHz (no HT), center1: 2412 MHz
        ch=$2
        freq=$3
        gsub(/[()]/, "", freq)
        width=""
        center1=""

        for (i = 1; i <= NF; i++) {
          if ($i == "width:") {
            width=$(i+1)
          }
          if ($i ~ /^center1:/) {
            center1=$(i+1)
          }
        }

        printf "%s %s %s %s\n", ch, freq, width, center1
      }
    '
}

printf "%-8s %-8s %-10s %-10s %-10s %-10s %-10s %-8s %-8s %-8s\n" \
       "REQ" "IW_CH" "IW_FREQ" "SURV_FREQ" "ACTIVE" "BUSY" "RX" "TX" "BUSY%" "NOISE"

for FREQ in $CHANNELS; do
    if ! sudo iw dev "$MON" set freq "$FREQ" 2>/dev/null; then
        echo "[WARN] failed to set freq $FREQ, skip"
        continue
    fi

    sleep 0.2

    read iw_ch iw_freq iw_width iw_center1 < <(get_mon_channel)

    read f0 inuse0 active0 busy0 rx0 tx0 noise0 < <(get_inuse_survey_values)

    sleep "$DWELL"

    read f1 inuse1 active1 busy1 rx1 tx1 noise1 < <(get_inuse_survey_values)

    da=$((active1 - active0))
    db=$((busy1 - busy0))
    dr=$((rx1 - rx0))
    dt=$((tx1 - tx0))

    if [ "$da" -gt 0 ]; then
        busy_pct=$(awk -v b="$db" -v a="$da" 'BEGIN { printf "%.1f", (b * 100.0 / a) }')
    else
        busy_pct="NA"
    fi

    if [ "$FREQ" != "$iw_freq" ] || [ "$FREQ" != "$f1" ]; then
        tag="MISMATCH"
    else
        tag="OK"
    fi

    printf "%-8s %-8s %-10s %-10s %-10s %-10s %-10s %-8s %-8s %-8s %s\n" \
           "$FREQ" "$iw_ch" "$iw_freq" "$f1" "$da" "$db" "$dr" "$dt" "$busy_pct" "$noise1" "$tag"
done
