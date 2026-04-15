#!/usr/bin/env bash
set -Eeuo pipefail

HOSTAPD_BIN="${HOSTAPD_BIN:-/home/sean/dev/hostap/hostapd/hostapd}"
WPA_SUP_BIN="${WPA_SUP_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_supplicant}"
WPA_CLI_BIN="${WPA_CLI_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_cli}"

RUNNER="${RUNNER:-./one_laptop_sta_ap_test.sh}"
CLEANER="${CLEANER:-./cleanup_sta_ap_test.sh}"
CONF_DIR="${CONF_DIR:-/home/sean/dev/hostap/mt76_test}"

LOG_DIR="${LOG_DIR:-/tmp/sta_ap_role_logs}"
RESULT_FILE="${RESULT_FILE:-/tmp/sta_ap_role_results.tsv}"

mkdir -p "$LOG_DIR"
: > "$RESULT_FILE"

#IFACE_A="${IFACE_A:-wlxf695c8aae435}"
#IFACE_B="${IFACE_B:-wlp58s0}"

#IFACE_A="${IFACE_A:-wlx000c433a3348}"
#IFACE_B="${IFACE_B:-wlp58s0}"

IFACE_A="${IFACE_A:-wlp58s0}"
IFACE_B="${IFACE_B:-wlx000c433a3348}"

#IFACE_A="${IFACE_A:-wlp58s0}"
#IFACE_B="${IFACE_B:-wlx000c43baabd4}"

ROLE_MODE="${ROLE_MODE:-forward}"

TESTS=(
# format:
# "hostapd_conf|wpa_conf|case_name"

"hostapd_open_5g.conf|wpa-open-5g.conf|open_5g"
"hostapd_wpa3_5g_ht20_ch36_basic.conf|wpa_wpa3_5g_ht20_ch36_basic.conf|wpa3_5g_ht20_ch36"
"hostapd_open_5g_vht80_ch36_basic.conf|wpa_open_5g_vht80_ch36_basic.conf|open_5g_vht80_ch36"
"hostapd_wpa2_5g_vht80_ch36_basic.conf|wpa_wpa2_5g_vht80_ch36_basic.conf|wpa2_5g_vht80_ch36"
"hostapd_wpa3_5g_vht80_ch36_basic.conf|wpa_wpa3_5g_vht80_ch36_basic.conf|wpa3_5g_vht80_ch36"
"hostapd_wpa2wpa3_5g_vht80_ch36_transition.conf|wpa_wpa2wpa3_5g_vht80_ch36_transition.conf|wpa2wpa3_5g_vht80_ch36_transition" "hostapd_owe_5g_vht80_ch36_basic.conf|wpa_owe_5g_vht80_ch36_basic.conf|owe_5g_vht80_ch36" "hostapd_open_5g_vht80_ch149_basic.conf|wpa_open_5g_vht80_ch149_basic.conf|open_5g_vht80_ch149"
"hostapd_wpa2_5g_vht80_ch149_basic.conf|wpa_wpa2_5g_vht80_ch149_basic.conf|wpa2_5g_vht80_ch149"
"hostapd_wpa3_5g_vht80_ch149_basic.conf|wpa_wpa3_5g_vht80_ch149_basic.conf|wpa3_5g_vht80_ch149"
"hostapd_open_5g_vht80_ch36_hidden.conf|wpa_open_5g_vht80_ch36_hidden.conf|open_5g_vht80_ch36_hidden"
"hostapd_owe_5g_vht80_ch149_basic.conf|wpa_owe_5g_vht80_ch149_basic.conf|owe_5g_vht80_ch149"

"hostapd_open_2g_ht20_ch6_basic.conf|wpa_open_2g_ht20_ch6_basic.conf|open_2g_ht20_ch6"
"hostapd_wpa2_2g_ht20_ch6_basic.conf|wpa_wpa2_2g_ht20_ch6_basic.conf|wpa2_2g_ht20_ch6"
"hostapd_owe_2g_ht20_ch6_basic.conf|wpa_owe_2g_ht20_ch6_basic.conf|owe_2g_ht20_ch6"

"hostapd_open_5g_he80_ch36_basic.conf|wpa_open_5g_he80_ch36_basic.conf|open_5g_he80_ch36"
"hostapd_wpa2_5g_he80_ch36_basic.conf|wpa_wpa2_5g_he80_ch36_basic.conf|wpa2_5g_he80_ch36"
"hostapd_wpa3_5g_he80_ch36_basic.conf|wpa_wpa3_5g_he80_ch36_basic.conf|wpa3_5g_he80_ch36"
"hostapd_owe_5g_he80_ch36_basic.conf|wpa_owe_5g_he80_ch36_basic.conf|owe_5g_he80_ch36"

"hostapd_open_2g_he20_ch6_basic.conf|wpa_open_2g_he20_ch6_basic.conf|open_2g_he20_ch6"
"hostapd_wpa2_2g_he20_ch6_basic.conf|wpa_wpa2_2g_he20_ch6_basic.conf|wpa2_2g_he20_ch6"
"hostapd_owe_2g_he20_ch6_basic.conf|wpa_owe_2g_he20_ch6_basic.conf|owe_2g_he20_ch6"
"hostapd_wpa3_2g_he20_ch6_basic.conf|wpa_wpa3_2g_he20_ch6_basic.conf|wpa3_2g_he20_ch6"

"hostapd_open_5g_he80_ch149_basic.conf|wpa_open_5g_he80_ch149_basic.conf|open_5g_he80_ch149"
"hostapd_wpa2_5g_he80_ch149_basic.conf|wpa_wpa2_5g_he80_ch149_basic.conf|wpa2_5g_he80_ch149"
"hostapd_wpa3_5g_he80_ch149_basic.conf|wpa_wpa3_5g_he80_ch149_basic.conf|wpa3_5g_he80_ch149"
"hostapd_owe_5g_he80_ch149_basic.conf|wpa_owe_5g_he80_ch149_basic.conf|owe_5g_he80_ch149"
"hostapd_wpa2wpa3_5g_he80_ch36_transition.conf|wpa_wpa2wpa3_5g_he80_ch36_transition.conf|wpa2wpa3_5g_he80_ch36_transition"
"hostapd_wpa2wpa3_5g_he80_ch149_transition.conf|wpa_wpa2wpa3_5g_he80_ch149_transition.conf|wpa2wpa3_5g_he80_ch149_transition"

# examples to disable items:
# "hostapd_open_5g.conf|wpa-open-5g.conf|open_5g"
# "hostapd_wpa3_5g_ht20_ch36_basic.conf|wpa_wpa3_5g_ht20_ch36_basic.conf|wpa3_5g_ht20_ch36"
)

#TESTS=(
#"hostapd_open_5g_he80_ch149_basic.conf|wpa_open_5g_he80_ch149_basic.conf|open_5g_he80_ch149"
#)

cleanup_once() {
    "$CLEANER" || true
}

extract_iperf_mbps() {
    local log_file="$1"
    awk '
    /receiver$/ {
        val=$(NF-2)
        unit=$(NF-1)
    }
    END {
        if (val == "") {
            print "NA"
        } else if (unit == "Gbits/sec") {
            printf "%.2f", val * 1000
        } else if (unit == "Mbits/sec") {
            printf "%.2f", val
        } else if (unit == "Kbits/sec") {
            printf "%.2f", val / 1000
        } else {
            print "NA"
        }
    }' "$log_file"
}

run_case() {
    local sta_if="$1"
    local ap_if="$2"
    local hostapd_conf="$3"
    local wpa_conf="$4"
    local case_name="$5"

    local hostapd_path="$CONF_DIR/$hostapd_conf"
    local wpa_path="$CONF_DIR/$wpa_conf"
    local log_file="$LOG_DIR/${case_name}.log"
    local rc throughput

    echo
    echo "================================================================"
    echo "CASE    : $case_name"
    echo "A       : $IFACE_A"
    echo "B       : $IFACE_B"
    echo "STA_IF  : $sta_if"
    echo "AP_IF   : $ap_if"
    echo "AP_CONF : $hostapd_path"
    echo "STA_CONF: $wpa_path"
    echo "LOG     : $log_file"

    if [[ ! -f "$hostapd_path" ]]; then
        echo "[FAIL] missing hostapd conf: $hostapd_path"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$case_name" "FAIL" "$sta_if" "$ap_if" "NA" "missing_hostapd_conf" "$log_file" >> "$RESULT_FILE"
        return 0
    fi

    if [[ ! -f "$wpa_path" ]]; then
        echo "[FAIL] missing wpa conf: $wpa_path"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$case_name" "FAIL" "$sta_if" "$ap_if" "NA" "missing_wpa_conf" "$log_file" >> "$RESULT_FILE"
        return 0
    fi

    set +e
    sudo PAUSE_BEFORE_RUN=no \
         STA_IF="$sta_if" \
         AP_BASE_IF="$ap_if" \
         HOSTAPD_BIN="$HOSTAPD_BIN" \
         WPA_SUP_BIN="$WPA_SUP_BIN" \
         WPA_CLI_BIN="$WPA_CLI_BIN" \
         HOSTAPD_CONF_MAIN="$hostapd_path" \
         WPA_CONF="$wpa_path" \
         "$RUNNER" 2>&1 | tee "$log_file"
    rc=${PIPESTATUS[0]}
    set -e

    throughput="$(extract_iperf_mbps "$log_file")"

    if [[ $rc -eq 0 ]]; then
        echo "[PASS] $case_name throughput=${throughput} Mbps"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$case_name" "PASS" "$sta_if" "$ap_if" "$throughput" "rc=0" "$log_file" >> "$RESULT_FILE"
    else
        echo "[FAIL] $case_name rc=$rc throughput=${throughput} Mbps"
        echo "----- tail $log_file -----"
        tail -n 40 "$log_file" || true
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$case_name" "FAIL" "$sta_if" "$ap_if" "$throughput" "rc=$rc" "$log_file" >> "$RESULT_FILE"
    fi

}

run_one_test_item() {
    local hostapd_conf="$1"
    local wpa_conf="$2"
    local base_name="$3"

    case "$ROLE_MODE" in
        forward)
            run_case "$IFACE_A" "$IFACE_B" "$hostapd_conf" "$wpa_conf" "${base_name}__A_sta_B_ap"
            ;;
        reverse)
            run_case "$IFACE_B" "$IFACE_A" "$hostapd_conf" "$wpa_conf" "${base_name}__B_sta_A_ap"
            ;;
        both)
            run_case "$IFACE_A" "$IFACE_B" "$hostapd_conf" "$wpa_conf" "${base_name}__A_sta_B_ap"
            run_case "$IFACE_B" "$IFACE_A" "$hostapd_conf" "$wpa_conf" "${base_name}__B_sta_A_ap"
            ;;
        *)
            echo "[ERR ] invalid ROLE_MODE: $ROLE_MODE"
            echo "Use ROLE_MODE=forward | reverse | both"
            exit 1
            ;;
    esac
}

print_summary() {
    local total pass fail
    total=$(awk 'END{print NR+0}' "$RESULT_FILE")
    pass=$(awk -F '\t' '$2=="PASS"{c++} END{print c+0}' "$RESULT_FILE")
    fail=$(awk -F '\t' '$2=="FAIL"{c++} END{print c+0}' "$RESULT_FILE")

    echo
    echo "================ FINAL SUMMARY ================"
    echo "A = $IFACE_A"
    echo "B = $IFACE_B"
    echo
    printf "%-34s %-6s %-18s %-18s %-12s %-14s %s\n" \
        "CASE" "RES" "STA_IF" "AP_IF" "THR(Mbps)" "INFO" "LOG"
    printf "%-34s %-6s %-18s %-18s %-12s %-14s %s\n" \
        "----------------------------------" "------" "------------------" "------------------" "------------" "--------------" "------------------------------"

    while IFS=$'\t' read -r case_name result sta_if ap_if thr info log_file; do
        printf "%-34s %-6s %-18s %-18s %-12s %-14s %s\n" \
            "$case_name" "$result" "$sta_if" "$ap_if" "$thr" "$info" "$log_file"
    done < "$RESULT_FILE"

    echo
    echo "Total : $total"
    echo "PASS  : $pass"
    echo "FAIL  : $fail"
    echo "Logs  : $LOG_DIR"
}

echo "A = $IFACE_A"
echo "B = $IFACE_B"
echo "ROLE_MODE = $ROLE_MODE"

for t in "${TESTS[@]}"; do
    IFS='|' read -r hostapd_conf wpa_conf case_name <<< "$t"
    run_one_test_item "$hostapd_conf" "$wpa_conf" "$case_name"
done

print_summary
