#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# User config
###############################################################################
STA_IF="${STA_IF:-wlx000c433a3336}"          # station interface
AP_BASE_IF="${AP_BASE_IF:-wlp58s0}"          # existing AP-side interface OR base iface on AP PHY
AP_VIF="${AP_VIF:-ap0}"                      # AP virtual interface to create
NS_STA="${NS_STA:-ns_sta}"
NS_AP="${NS_AP:-ns_ap}"

HOSTAPD_BIN="${HOSTAPD_BIN:-$HOME/dev/hostap/hostapd/hostapd}"
WPA_SUP_BIN="${WPA_SUP_BIN:-$HOME/dev/hostap/wpa_supplicant/wpa_supplicant}"
WPA_CLI_BIN="${WPA_CLI_BIN:-$HOME/dev/hostap/wpa_supplicant/wpa_cli}"
IPERF3_BIN="${IPERF3_BIN:-iperf3}"

HOSTAPD_CONF_MAIN="${HOSTAPD_CONF_MAIN:-$HOME/dev/mt76_test/hostapd_wpa3_5g_ht20_ch36_basic.conf}"
# Optional second AP config. Leave empty to skip.
HOSTAPD_CONF_SECOND="${HOSTAPD_CONF_SECOND:-}"
WPA_CONF="${WPA_CONF:-$HOME/dev/mt76_test/wpa_wpa3_5g_ht20_ch36_basic.conf}"

AP_IP="${AP_IP:-192.168.50.1/24}"
STA_IP="${STA_IP:-192.168.50.2/24}"
PING_TARGET="${PING_TARGET:-192.168.50.1}"

AUTO_CREATE_AP_VIF="${AUTO_CREATE_AP_VIF:-yes}"   # yes/no
AUTO_CLEAN_NS="${AUTO_CLEAN_NS:-yes}"             # yes/no
PAUSE_BEFORE_RUN="${PAUSE_BEFORE_RUN:-yes}"       # yes/no

VERBOSE="${VERBOSE:-no}"                          # yes/no
DEBUG_80211="${DEBUG_80211:-no}"                  # yes/no, enable hostapd/wpa_supplicant -ddd
LOG_DIR="${LOG_DIR:-./logs}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
HOSTAPD_LOG="$LOG_DIR/hostapd_$RUN_ID.log"
WPA_LOG="$LOG_DIR/wpa_$RUN_ID.log"
IPERF_LOG="$LOG_DIR/iperf_$RUN_ID.log"

###############################################################################
# Helpers
###############################################################################
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERR ] $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

run() {
    [[ "$VERBOSE" == "yes" ]] && echo "+ $*"
    "$@"
}

ns_run() {
    local ns="$1"
    shift
    [[ "$VERBOSE" == "yes" ]] && echo "+ ip netns exec $ns $*"
    ip netns exec "$ns" "$@"
}

cleanup() {
    set +e
    log "Cleaning up background processes"

    [[ -n "${HOSTAPD_PID:-}" ]] && kill "$HOSTAPD_PID" 2>/dev/null
    [[ -n "${HOSTAPD2_PID:-}" ]] && kill "$HOSTAPD2_PID" 2>/dev/null
    [[ -n "${WPA_PID:-}" ]] && kill "$WPA_PID" 2>/dev/null

    sudo pkill -f "iperf3 -s" 2>/dev/null || true
    sudo ip netns exec "$NS_AP" iw dev "$AP_VIF" del 2>/dev/null || \
        sudo iw dev "$AP_VIF" del 2>/dev/null || true

    if [[ "$VERBOSE" == "yes" ]]; then
        log "Interfaces after cleanup:"
        iw dev || true
        ip link show || true
    fi
}
trap cleanup EXIT

netns_exists() {
    ip netns list | awk '{print $1}' | grep -qx "$1"
}

if_exists_root() {
    ip link show "$1" >/dev/null 2>&1
}

if_exists_ns() {
    local ns="$1"
    local ifname="$2"
    ip netns exec "$ns" ip link show "$ifname" >/dev/null 2>&1
}

get_phy_for_if() {
    local ifname="$1"
    iw dev "$ifname" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}' && return 0
    ip netns exec "$NS_STA" iw dev "$ifname" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}' && return 0
    ip netns exec "$NS_AP"  iw dev "$ifname" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}'
}

show_hw_id() {
    local ifname="$1"
    local dev
    dev="$(readlink -f "/sys/class/net/$ifname/device")" || return 1
    while [[ "$dev" != "/" ]]; do
        if [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]]; then
            echo "VID:PID $(cat "$dev/idVendor"):$(cat "$dev/idProduct")"
            return 0
        fi
        if [[ -f "$dev/vendor" && -f "$dev/device" ]]; then
            echo "PCI VID:DID $(cat "$dev/vendor"):$(cat "$dev/device")"
            return 0
        fi
        dev="$(dirname "$dev")"
    done
    echo "Unknown"
}

wait_for_ping() {
    local ns="$1"
    local target="$2"
    local tries="${3:-10}"
    local i
    for ((i=1; i<=tries; i++)); do
        if ip netns exec "$ns" ping -c 1 -W 1 "$target" >/dev/null 2>&1; then
            log "Ping to $target succeeded"
            return 0
        fi
        sleep 1
    done
    return 1
}

###############################################################################
# Pre-check
###############################################################################
need_cmd sudo
need_cmd iw
need_cmd ip
need_cmd nmcli
need_cmd iperf3

if [[ "$VERBOSE" == "yes" ]]; then
    log "Current interfaces before validation:"
    iw dev || true
    ip link show || true
fi

[[ -x "$HOSTAPD_BIN" ]] || die "hostapd not executable: $HOSTAPD_BIN"
[[ -x "$WPA_SUP_BIN" ]] || die "wpa_supplicant not executable: $WPA_SUP_BIN"
[[ -x "$WPA_CLI_BIN" ]] || die "wpa_cli not executable: $WPA_CLI_BIN"
[[ -f "$HOSTAPD_CONF_MAIN" ]] || die "Missing hostapd conf: $HOSTAPD_CONF_MAIN"
[[ -f "$WPA_CONF" ]] || die "Missing wpa_supplicant conf: $WPA_CONF"

mkdir -p "$LOG_DIR"

if ! if_exists_root "$STA_IF" && ! if_exists_ns "$NS_STA" "$STA_IF"; then
    die "STA interface not found: $STA_IF"
fi

if ! if_exists_root "$AP_BASE_IF" && ! if_exists_ns "$NS_AP" "$AP_BASE_IF"; then
    die "AP base interface not found: $AP_BASE_IF"
fi

STA_PHY="$(get_phy_for_if "$STA_IF")"
AP_PHY="$(get_phy_for_if "$AP_BASE_IF")"

[[ -n "$STA_PHY" ]] || die "Failed to get phy for $STA_IF"
[[ -n "$AP_PHY" ]] || die "Failed to get phy for $AP_BASE_IF"

###############################################################################
# Stage 1: inspect / prepare
###############################################################################
if [[ "$VERBOSE" == "yes" ]]; then
    log "Current interfaces:"
    run iw dev
fi

echo
log "Selected roles:"
echo "  STA_IF    = $STA_IF   ($STA_PHY)   $(show_hw_id "$STA_IF")"
echo "  AP_BASE_IF= $AP_BASE_IF   ($AP_PHY)   $(show_hw_id "$AP_BASE_IF")"
echo "  AP_VIF    = $AP_VIF"
echo

log "Set NetworkManager ownership"
if if_exists_root "$STA_IF"; then
    run nmcli device set "$STA_IF" managed no
else
    log "$STA_IF not in root namespace, skip nmcli"
fi

if if_exists_root "$AP_BASE_IF"; then
    run nmcli device set "$AP_BASE_IF" managed no || true
else
    log "$AP_BASE_IF not in root namespace, skip nmcli"
fi

AP_RUN_IF="$AP_BASE_IF"

if [[ "$AUTO_CREATE_AP_VIF" == "yes" ]]; then
    AP_RUN_IF="$AP_VIF"
fi


log "AP runtime interface: $AP_RUN_IF"
if [[ "$VERBOSE" == "yes" ]]; then
    echo
    log "Interfaces after prepare:"
    run iw dev
fi
echo

if [[ "$PAUSE_BEFORE_RUN" == "yes" ]]; then
    read -r -p "Check interface roles above. Press Enter to continue, or Ctrl-C to stop... " _
fi

###############################################################################
# Stage 2: namespaces and bring-up
###############################################################################
if ! netns_exists "$NS_AP"; then
    run sudo ip netns add "$NS_AP"
fi

if ! if_exists_ns "$NS_AP" "$AP_BASE_IF"; then
    log "Move AP PHY into test namespace"
    run sudo iw phy "$AP_PHY" set netns name "$NS_AP"
else
    log "$AP_BASE_IF already in $NS_AP"
fi

if ! netns_exists "$NS_STA"; then
    run sudo ip netns add "$NS_STA"
fi

if ! if_exists_ns "$NS_STA" "$STA_IF"; then
    log "Move STA PHY into test namespace"
    run sudo iw phy "$STA_PHY" set netns name "$NS_STA"
else
    log "$STA_IF already in $NS_STA"
fi

AP_PHY="$(ip netns exec "$NS_AP" iw dev "$AP_BASE_IF" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}')"
STA_PHY="$(ip netns exec "$NS_STA" iw dev "$STA_IF" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}')"


log "Bring loopback up"
ns_run "$NS_AP" ip link set lo up
ns_run "$NS_STA" ip link set lo up

if [[ "$AUTO_CREATE_AP_VIF" == "yes" ]]; then
    sudo ip netns exec "$NS_AP" iw dev "$AP_VIF" del 2>/dev/null || true
    log "Creating AP VIF $AP_VIF on $AP_PHY in $NS_AP"
    ns_run "$NS_AP" iw phy "$AP_PHY" interface add "$AP_VIF" type __ap
fi

log "Debug namespace interfaces"
ns_run "$NS_AP" iw dev
ns_run "$NS_STA" iw dev

log "Bring interfaces up"
# AP side
if ! if_exists_ns "$NS_AP" "$AP_RUN_IF"; then
    die "AP runtime interface not found in $NS_AP: $AP_RUN_IF"
fi
ns_run "$NS_AP" ip link set "$AP_RUN_IF" up

# STA side
ns_run "$NS_STA" ip link set "$STA_IF" up

log "Assign IP addresses"
ns_run "$NS_AP" ip addr flush dev "$AP_RUN_IF" || true
ns_run "$NS_STA" ip addr flush dev "$STA_IF" || true

ns_run "$NS_AP" ip addr add "$AP_IP" dev "$AP_RUN_IF"
ns_run "$NS_STA" ip addr add "$STA_IP" dev "$STA_IF"

###############################################################################
# Start hostapd / wpa_supplicant
###############################################################################
log "Create runtime dirs"
ns_run "$NS_AP" mkdir -p /var/run/hostapd
ns_run "$NS_STA" mkdir -p /var/run/wpa_supplicant

HOSTAPD_DBG_OPT=""
WPA_DBG_OPT=""
if [[ "$DEBUG_80211" == "yes" ]]; then
    HOSTAPD_DBG_OPT="-ddd"
    WPA_DBG_OPT="-ddd"
fi

log "Start hostapd on $AP_RUN_IF"
sudo ip netns exec "$NS_AP" "$HOSTAPD_BIN" $HOSTAPD_DBG_OPT -i "$AP_RUN_IF" "$HOSTAPD_CONF_MAIN" &
HOSTAPD_PID=$!
sleep 2

if [[ -n "$HOSTAPD_CONF_SECOND" ]]; then
    log "Start second hostapd on $AP_VIF"
    sudo ip netns exec "$NS_AP" "$HOSTAPD_BIN" $HOSTAPD_DBG_OPT -i "$AP_VIF" "$HOSTAPD_CONF_SECOND" &
    HOSTAPD2_PID=$!
    sleep 2
fi

log "Start wpa_supplicant on $STA_IF"
sudo ip netns exec "$NS_STA" "$WPA_SUP_BIN" -D nl80211 -i "$STA_IF" -c "$WPA_CONF" $WPA_DBG_OPT &
WPA_PID=$!
sleep 10

log "Check STA status"
ns_run "$NS_STA" "$WPA_CLI_BIN" -i "$STA_IF" status || true
ns_run "$NS_STA" iw dev "$STA_IF" link || true

###############################################################################
# Connectivity test
###############################################################################
log "Routes"
ns_run "$NS_AP" ip route show table local || true
ns_run "$NS_STA" ip route show table local || true

log "Ping test"
if wait_for_ping "$NS_STA" "$PING_TARGET" 10; then
    ns_run "$NS_STA" ping -c 3 "$PING_TARGET"
else
    warn "Ping did not succeed within timeout"
    ns_run "$NS_STA" ip neigh show || true
fi

log "Start iperf3 server in $NS_AP"
sudo ip netns exec "$NS_AP" "$IPERF3_BIN" -s -D

sleep 1

log "Run iperf3 client in $NS_STA"
ns_run "$NS_STA" "$IPERF3_BIN" -c "$PING_TARGET"

log "Test done"
