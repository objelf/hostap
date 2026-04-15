#!/bin/bash

IFACE="wlp58s0"
WPA_CLI="sudo ./wpa_cli"
PING_IP="192.168.0.254"

ROUNDS=10000
CONNECT_TIMEOUT=20
POLL_INTERVAL=0.2

OUT="switch_ping_$(date +%Y%m%d_%H%M%S).csv"

echo "round,net_id,bssid,freq,connect_sec,ping_ok,ping_rtt_ms" > "$OUT"

measure_one()
{
    net="$1"
    round="$2"

    start_ms=$(date +%s%3N)

    if ! $WPA_CLI -i "$IFACE" select_network "$net" >/dev/null 2>&1; then
        echo "$round,$net,,,SELECT_FAIL,0," >> "$OUT"
        echo "round=$round net=$net SELECT_FAIL"
        return
    fi

    deadline=$(( $(date +%s) + CONNECT_TIMEOUT ))

    while true; do
        status=$($WPA_CLI -i "$IFACE" status 2>/dev/null)

        state=$(echo "$status" | awk -F= '/^wpa_state=/{print $2}')
        cur_id=$(echo "$status" | awk -F= '/^id=/{print $2}')
        bssid=$(echo "$status" | awk -F= '/^bssid=/{print $2}')
        freq=$(echo "$status" | awk -F= '/^freq=/{print $2}')

        if [ "$state" = "COMPLETED" ] && [ "$cur_id" = "$net" ]; then
            break
        fi

        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "$round,$net,$bssid,$freq,CONNECT_TIMEOUT,0," >> "$OUT"
            echo "round=$round net=$net CONNECT_TIMEOUT"
            return
        fi

        sleep "$POLL_INTERVAL"
    done

    end_ms=$(date +%s%3N)
    connect_sec=$(awk "BEGIN { printf \"%.3f\", ($end_ms - $start_ms) / 1000 }")

    ping_out=$(ping -I "$IFACE" -c 1 -W 3 "$PING_IP" 2>/dev/null)

    if echo "$ping_out" | grep -q "time="; then
        ping_ok=1
        ping_rtt=$(echo "$ping_out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n1)
    else
        ping_ok=0
        ping_rtt=""
    fi

    echo "$round,$net,$bssid,$freq,$connect_sec,$ping_ok,$ping_rtt" >> "$OUT"
    echo "round=$round net=$net bssid=$bssid freq=$freq connect=${connect_sec}s ping_ok=$ping_ok rtt=${ping_rtt:-NA}"
}

for i in $(seq 1 "$ROUNDS"); do
    measure_one 0 "$i"
    measure_one 1 "$i"
done

echo "done: $OUT"
