IFACE="wlp58s0"
PHY_DBG="/sys/kernel/debug/ieee80211/phy9/mt76/chip_reset"
PING_IP="192.168.1.254"
ROUNDS=10000
POLL_INTERVAL="0.2"

for i in $(seq 1 "$ROUNDS"); do
    echo "=== round $i ==="

    t0=$(date +%s.%N)

    sudo sh -c "echo 1 > $PHY_DBG"

    while true; do
        ping -I "$IFACE" -c 1 -W 1 "$PING_IP" >/dev/null 2>&1 && break
        sleep "$POLL_INTERVAL"
    done

    t1=$(date +%s.%N)
    total_time=$(echo "$t1 - $t0" | bc)

    echo "reset->ping=${total_time}s"
    echo
done
