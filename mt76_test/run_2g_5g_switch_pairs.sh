#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/home/sean/dev/hostap/mt76_test"
TEST_SH="$BASE_DIR/one_laptop_sta_ap_test.sh"

STA_IF="${STA_IF:-wlp58s0}"
AP_BASE_IF="${AP_BASE_IF:-wlx000c433a3348}"

HOSTAPD_BIN="${HOSTAPD_BIN:-/home/sean/dev/hostap/hostapd/hostapd}"
WPA_SUP_BIN="${WPA_SUP_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_supplicant}"
WPA_CLI_BIN="${WPA_CLI_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_cli}"

ROUNDS="${ROUNDS:-20}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-2}"

OUT_DIR="$BASE_DIR/switch_2g_5g_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"

run_pair()
{
    local name="$1"
    local hostapd_conf="$BASE_DIR/$2"
    local wpa_conf="$BASE_DIR/$3"
    local round="$4"
    local log="$OUT_DIR/round_${round}_${name}.log"

    echo
    echo "===== ROUND $round: $name ====="
    echo "AP : $hostapd_conf"
    echo "STA: $wpa_conf"
    echo "LOG: $log"

    if [[ ! -f "$hostapd_conf" || ! -f "$wpa_conf" ]]; then
        echo "[SKIP] missing config for $name"
        return 0
    fi

    if sudo PAUSE_BEFORE_RUN=no \
        STA_IF="$STA_IF" \
        AP_BASE_IF="$AP_BASE_IF" \
        HOSTAPD_BIN="$HOSTAPD_BIN" \
        WPA_SUP_BIN="$WPA_SUP_BIN" \
        WPA_CLI_BIN="$WPA_CLI_BIN" \
        HOSTAPD_CONF_MAIN="$hostapd_conf" \
        WPA_CONF="$wpa_conf" \
        "$TEST_SH" 2>&1 | tee "$log"; then

        tput="$(grep -E 'IPERF|receiver|bits/sec' "$log" | tail -n 1 || true)"
        echo "[PASS] $name ${tput:+- $tput}"
    else
        echo "[FAIL] $name"
        tail -n 80 "$log"
        return 1
    fi

    sleep "$SLEEP_BETWEEN"
}

# Pair list: same security/mode family, switch 2G <-> 5G
PAIRS_2G=(
    "open_2g_he20_ch6_basic:hostapd_open_2g_he20_ch6_basic.conf:wpa_open_2g_he20_ch6_basic.conf"
    "open_2g_ht20_ch6_basic:hostapd_open_2g_ht20_ch6_basic.conf:wpa_open_2g_ht20_ch6_basic.conf"
    "owe_2g_he20_ch6_basic:hostapd_owe_2g_he20_ch6_basic.conf:wpa_owe_2g_he20_ch6_basic.conf"
    "owe_2g_ht20_ch6_basic:hostapd_owe_2g_ht20_ch6_basic.conf:wpa_owe_2g_ht20_ch6_basic.conf"
    "wpa2_2g_he20_ch6_basic:hostapd_wpa2_2g_he20_ch6_basic.conf:wpa_wpa2_2g_he20_ch6_basic.conf"
    "wpa2_2g_ht20_ch6_basic:hostapd_wpa2_2g_ht20_ch6_basic.conf:wpa_wpa2_2g_ht20_ch6_basic.conf"
    "wpa3_2g_he20_ch6_basic:hostapd_wpa3_2g_he20_ch6_basic.conf:wpa_wpa3_2g_he20_ch6_basic.conf"
)

PAIRS_5G=(
    "open_5g_he80_ch149_basic:hostapd_open_5g_he80_ch149_basic.conf:wpa_open_5g_he80_ch149_basic.conf"
    "open_5g_vht80_ch149_basic:hostapd_open_5g_vht80_ch149_basic.conf:wpa_open_5g_vht80_ch149_basic.conf"
    "owe_5g_he80_ch149_basic:hostapd_owe_5g_he80_ch149_basic.conf:wpa_owe_5g_he80_ch149_basic.conf"
    "owe_5g_vht80_ch149_basic:hostapd_owe_5g_vht80_ch149_basic.conf:wpa_owe_5g_vht80_ch149_basic.conf"
    "wpa2_5g_he80_ch149_basic:hostapd_wpa2_5g_he80_ch149_basic.conf:wpa_wpa2_5g_he80_ch149_basic.conf"
    "wpa2_5g_vht80_ch149_basic:hostapd_wpa2_5g_vht80_ch149_basic.conf:wpa_wpa2_5g_vht80_ch149_basic.conf"
    "wpa3_5g_he80_ch149_basic:hostapd_wpa3_5g_he80_ch149_basic.conf:wpa_wpa3_5g_he80_ch149_basic.conf"
    "wpa3_5g_vht80_ch149_basic:hostapd_wpa3_5g_vht80_ch149_basic.conf:wpa_wpa3_5g_vht80_ch149_basic.conf"
)

total_2g="${#PAIRS_2G[@]}"
total_5g="${#PAIRS_5G[@]}"

pass=0
fail=0
round=1

for i in $(seq 0 $((ROUNDS - 1))); do
    pair2="${PAIRS_2G[$((i % total_2g))]}"
    pair5="${PAIRS_5G[$((i % total_5g))]}"

    IFS=: read -r name ap sta <<< "$pair2"
    if run_pair "$name" "$ap" "$sta" "$round"; then
        ((++pass))
    else
        ((++fail))
    fi
    ((round++))

    IFS=: read -r name ap sta <<< "$pair5"
    if run_pair "$name" "$ap" "$sta" "$round"; then
        ((++pass))
    else
        ((++fail))
    fi
    ((round++))
done

echo
echo "===== SUMMARY ====="
echo "PASS: $pass"
echo "FAIL: $fail"
echo "LOGS: $OUT_DIR"
