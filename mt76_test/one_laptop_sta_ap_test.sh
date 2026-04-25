#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# User config
###############################################################################
TEST_MODE="${TEST_MODE:-local_ns}"            # local_ns / two_host
REMOTE_HOST="${REMOTE_HOST:-}"                  # ssh target for two_host mode
REMOTE_ROLE="${REMOTE_ROLE:-ap}"                # ap: remote AP, sta: remote STA
REMOTE_MGMT_IF="${REMOTE_MGMT_IF:-}"            # remote management iface; never modify it
REMOTE_SSH_KEY="${REMOTE_SSH_KEY:-${SUDO_USER:+/home/$SUDO_USER/.ssh/sta_ap_test_ed25519}}"
REMOTE_SSH_KEY="${REMOTE_SSH_KEY:-$HOME/.ssh/sta_ap_test_ed25519}"
REMOTE_SSH="${REMOTE_SSH:-ssh -i $REMOTE_SSH_KEY -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new}"
REMOTE_SUDO="${REMOTE_SUDO:-sudo -n}"           # requires NOPASSWD on remote host
REMOTE_LOG_DIR="${REMOTE_LOG_DIR:-/tmp/sta_ap_test_logs}"
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
REMOTE_HOSTAPD_LOG="$REMOTE_LOG_DIR/hostapd_$RUN_ID.log"
REMOTE_WPA_LOG="$REMOTE_LOG_DIR/wpa_$RUN_ID.log"
REMOTE_IPERF_LOG="$REMOTE_LOG_DIR/iperf_$RUN_ID.log"

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

remote_run()
{
    [[ -n "$REMOTE_HOST" ]] || die "REMOTE_HOST is required for TEST_MODE=two_host"

    [[ "$VERBOSE" == "yes" ]] && echo "+ $REMOTE_SSH $REMOTE_HOST $*"
    $REMOTE_SSH "$REMOTE_HOST" "$@"
}

cleanup() {
    set +e
    log "Cleaning up background processes"

    [[ -n "${HOSTAPD_PID:-}" ]] && kill "$HOSTAPD_PID" 2>/dev/null
    [[ -n "${HOSTAPD2_PID:-}" ]] && kill "$HOSTAPD2_PID" 2>/dev/null
    [[ -n "${WPA_PID:-}" ]] && kill "$WPA_PID" 2>/dev/null

    sudo pkill -f "[i]perf3 -s" 2>/dev/null || true
    sudo ip netns exec "$NS_AP" iw dev "$AP_VIF" del 2>/dev/null || \
        sudo iw dev "$AP_VIF" del 2>/dev/null || true

    if [[ "$TEST_MODE" == "two_host" && -n "$REMOTE_HOST" ]]; then
        remote_cleanup
    fi

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

precheck_common()
{
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

    mkdir -p "$LOG_DIR"
}

show_log_paths()
{
    log "Local logs:"
    echo "  HOSTAPD_LOG = $HOSTAPD_LOG"
    echo "  WPA_LOG     = $WPA_LOG"
    echo "  IPERF_LOG   = $IPERF_LOG"

    if [[ "$TEST_MODE" == "two_host" ]]; then
        log "Remote control:"
        echo "  REMOTE_HOST    = $REMOTE_HOST"
        echo "  REMOTE_SSH_KEY = $REMOTE_SSH_KEY"
        echo "  REMOTE_SUDO    = $REMOTE_SUDO"
        log "Remote logs on $REMOTE_HOST:"
        echo "  REMOTE_HOSTAPD_LOG = $REMOTE_HOSTAPD_LOG"
        echo "  REMOTE_WPA_LOG     = $REMOTE_WPA_LOG"
        echo "  REMOTE_IPERF_LOG   = $REMOTE_IPERF_LOG"
    fi
}

setup_debug_opts()
{
    HOSTAPD_DBG_OPT=""
    WPA_DBG_OPT=""

    if [[ "$DEBUG_80211" == "yes" ]]; then
        HOSTAPD_DBG_OPT="-ddd"
        WPA_DBG_OPT="-ddd"
    fi
}

check_local_hostapd()
{
    [[ -x "$HOSTAPD_BIN" ]] || die "hostapd not executable: $HOSTAPD_BIN"
    [[ -f "$HOSTAPD_CONF_MAIN" ]] || die "Missing hostapd conf: $HOSTAPD_CONF_MAIN"
}

check_local_wpa()
{
    [[ -x "$WPA_SUP_BIN" ]] || die "wpa_supplicant not executable: $WPA_SUP_BIN"
    [[ -x "$WPA_CLI_BIN" ]] || die "wpa_cli not executable: $WPA_CLI_BIN"
    [[ -f "$WPA_CONF" ]] || die "Missing wpa_supplicant conf: $WPA_CONF"
}

local_ns_validate_ifaces()
{
    check_local_hostapd
    check_local_wpa

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
}

local_ns_prepare_roles()
{
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
}

local_ns_setup_namespaces()
{
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
}

local_ns_bringup_links()
{
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
    if ! if_exists_ns "$NS_AP" "$AP_RUN_IF"; then
        die "AP runtime interface not found in $NS_AP: $AP_RUN_IF"
    fi

    ns_run "$NS_AP" ip link set "$AP_RUN_IF" up
    ns_run "$NS_STA" ip link set "$STA_IF" up

    log "Assign IP addresses"
    ns_run "$NS_AP" ip addr flush dev "$AP_RUN_IF" || true
    ns_run "$NS_STA" ip addr flush dev "$STA_IF" || true

    ns_run "$NS_AP" ip addr add "$AP_IP" dev "$AP_RUN_IF"
    ns_run "$NS_STA" ip addr add "$STA_IP" dev "$STA_IF"
}

local_ns_start_hostapd()
{
    log "Create AP runtime dir"
    ns_run "$NS_AP" mkdir -p /var/run/hostapd

    log "Start hostapd on $AP_RUN_IF"
    sudo ip netns exec "$NS_AP" "$HOSTAPD_BIN" $HOSTAPD_DBG_OPT -i "$AP_RUN_IF" "$HOSTAPD_CONF_MAIN" \
        > >(tee "$HOSTAPD_LOG") 2>&1 &
    HOSTAPD_PID=$!
    sleep 2

    if [[ -n "$HOSTAPD_CONF_SECOND" ]]; then
        log "Start second hostapd on $AP_VIF"
        sudo ip netns exec "$NS_AP" "$HOSTAPD_BIN" $HOSTAPD_DBG_OPT -i "$AP_VIF" "$HOSTAPD_CONF_SECOND" \
            > >(tee -a "$HOSTAPD_LOG") 2>&1 &
        HOSTAPD2_PID=$!
        sleep 2
    fi
}

local_ns_start_wpa()
{
    log "Create STA runtime dir"
    ns_run "$NS_STA" mkdir -p /var/run/wpa_supplicant

    log "Start wpa_supplicant on $STA_IF"
    sudo ip netns exec "$NS_STA" "$WPA_SUP_BIN" -D nl80211 -i "$STA_IF" -c "$WPA_CONF" $WPA_DBG_OPT \
        > >(tee "$WPA_LOG") 2>&1 &
    WPA_PID=$!
    sleep 10

    log "Check STA status"
    ns_run "$NS_STA" "$WPA_CLI_BIN" -i "$STA_IF" status || true
    ns_run "$NS_STA" iw dev "$STA_IF" link || true
}

local_ns_connectivity_test()
{
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
    sudo ip netns exec "$NS_AP" "$IPERF3_BIN" -s > >(tee "$IPERF_LOG") 2>&1 &

    sleep 1

    log "Run iperf3 client in $NS_STA"
    ns_run "$NS_STA" "$IPERF3_BIN" -c "$PING_TARGET" 2>&1 | tee -a "$IPERF_LOG"

    log "Test done"
}

remote_cleanup()
{
    remote_run "$REMOTE_SUDO pkill -f '[h]ostapd.*$AP_BASE_IF' || true" || true
    remote_run "$REMOTE_SUDO pkill -f '[w]pa_supplicant.*$STA_IF' || true" || true
    remote_run "$REMOTE_SUDO pkill -f '[i]perf3 -s' || true" || true
}

two_host_precheck_remote()
{
    if [[ "$(id -u)" -eq 0 ]]; then
        die "Do not run TEST_MODE=two_host with sudo. Run as $USER and let the script use sudo internally."
    fi

    [[ -n "$REMOTE_HOST" ]] || die "REMOTE_HOST is required for TEST_MODE=two_host"
    [[ -f "$REMOTE_SSH_KEY" ]] || die "Missing SSH key: $REMOTE_SSH_KEY. Run: ./setup_two_host_remote.sh first"

    remote_run "true" || die "Cannot reach REMOTE_HOST=$REMOTE_HOST with SSH key $REMOTE_SSH_KEY"
    remote_run "$REMOTE_SUDO /usr/sbin/ip link show >/dev/null" || die "Remote sudo NOPASSWD is required. Run: ./setup_two_host_remote.sh first"

    remote_detect_mgmt_if

    remote_run "command -v ip >/dev/null"
    remote_run "command -v nmcli >/dev/null"
    remote_run "command -v iperf3 >/dev/null"

    case "$REMOTE_ROLE" in
    ap)
        remote_run "test -x '$HOSTAPD_BIN'" || die "Remote hostapd not executable: $HOSTAPD_BIN"
        remote_run "test -f '$HOSTAPD_CONF_MAIN'" || die "Remote hostapd conf missing: $HOSTAPD_CONF_MAIN"
        ;;
    sta)
        remote_run "test -x '$WPA_SUP_BIN'" || die "Remote wpa_supplicant not executable: $WPA_SUP_BIN"
        remote_run "test -x '$WPA_CLI_BIN'" || die "Remote wpa_cli not executable: $WPA_CLI_BIN"
        remote_run "test -f '$WPA_CONF'" || die "Remote wpa_supplicant conf missing: $WPA_CONF"
        ;;
    *)
        die "Unknown REMOTE_ROLE=$REMOTE_ROLE"
        ;;
    esac
}

two_host_validate_local()
{
    case "$REMOTE_ROLE" in
    ap)
        check_local_wpa
        if_exists_root "$STA_IF" || die "Local STA interface not found: $STA_IF"
        ;;
    sta)
        check_local_hostapd
        if_exists_root "$AP_BASE_IF" || die "Local AP interface not found: $AP_BASE_IF"
        ;;
    *)
        die "Unknown REMOTE_ROLE=$REMOTE_ROLE"
        ;;
    esac
}


remote_host_ip()
{
    local host="$REMOTE_HOST"

    host="${host#*@}"
    host="${host%%:*}"

    echo "$host"
}

remote_detect_mgmt_if()
{
    local host_ip

    [[ -n "$REMOTE_MGMT_IF" ]] && {
        log "Use configured remote management interface: $REMOTE_MGMT_IF"
        return 0
    }

    host_ip="$(remote_host_ip)"
    [[ -n "$host_ip" ]] || return 0

    REMOTE_MGMT_IF="$(remote_run "ip -o addr show | awk -v ip='$host_ip' '\$4 ~ \"^\" ip \"/\" {print \$2; exit}'" | tail -n1)"

    if [[ -n "$REMOTE_MGMT_IF" ]]; then
        log "Detected remote management interface: $REMOTE_MGMT_IF for $host_ip"
    else
        warn "Failed to detect remote management interface for $host_ip"
    fi
}

remote_check_not_ssh_if()
{
    local ifname="$1"

    remote_run "
        client_ip=\${SSH_CONNECTION%% *}
        ssh_if=\$(ip route get \$client_ip 2>/dev/null | awk '{for (i=1; i<=NF; i++) if (\$i == \"dev\") {print \$(i+1); exit}}')
        if [ -n \"\$ssh_if\" ] && [ \"\$ssh_if\" = \"$ifname\" ]; then
            echo \"ERROR: $ifname is the SSH management interface; refusing to modify it\" >&2
            exit 1
        fi
    "
}

remote_check_not_mgmt_if()
{
    local ifname="$1"

    if [[ -n "$REMOTE_MGMT_IF" && "$ifname" == "$REMOTE_MGMT_IF" ]]; then
        die "$ifname is REMOTE_MGMT_IF; refusing to modify the remote management interface"
    fi
}

remote_prepare_ap()
{
    log "Prepare remote AP $AP_BASE_IF on $REMOTE_HOST"
    remote_check_not_mgmt_if "$AP_BASE_IF"
    remote_check_not_ssh_if "$AP_BASE_IF"

    remote_run "mkdir -p '$REMOTE_LOG_DIR'"
    remote_run "$REMOTE_SUDO nmcli device set '$AP_BASE_IF' managed no || true"
    remote_run "$REMOTE_SUDO pkill -f '[h]ostapd.*$AP_BASE_IF' || true"
    remote_run "$REMOTE_SUDO pkill -f '[i]perf3 -s' || true"
    remote_run "$REMOTE_SUDO ip link set '$AP_BASE_IF' down || true"
    remote_run "$REMOTE_SUDO ip addr flush dev '$AP_BASE_IF' || true"
    remote_run "$REMOTE_SUDO ip link set '$AP_BASE_IF' up"
    remote_run "$REMOTE_SUDO ip addr add '$AP_IP' dev '$AP_BASE_IF'"
    remote_run "ip addr show dev '$AP_BASE_IF'"
}

remote_start_hostapd()
{
    log "Start remote hostapd on $AP_BASE_IF"

    remote_run "nohup $REMOTE_SUDO '$HOSTAPD_BIN' $HOSTAPD_DBG_OPT -i '$AP_BASE_IF' '$HOSTAPD_CONF_MAIN' > '$REMOTE_HOSTAPD_LOG' 2>&1 < /dev/null &"
    sleep 3
    remote_run "tail -n 40 '$REMOTE_HOSTAPD_LOG' || true"
}

remote_prepare_sta()
{
    log "Prepare remote STA $STA_IF on $REMOTE_HOST"
    remote_check_not_mgmt_if "$STA_IF"

    remote_run "mkdir -p '$REMOTE_LOG_DIR'"
    remote_run "$REMOTE_SUDO nmcli device set '$STA_IF' managed no || true"
    remote_run "$REMOTE_SUDO pkill -f '[w]pa_supplicant.*$STA_IF' || true"
    remote_run "$REMOTE_SUDO ip link set '$STA_IF' down || true"
    remote_run "$REMOTE_SUDO ip addr flush dev '$STA_IF' || true"
    remote_run "$REMOTE_SUDO ip link set '$STA_IF' up"
    remote_run "$REMOTE_SUDO ip addr add '$STA_IP' dev '$STA_IF'"
    remote_run "ip addr show dev '$STA_IF'"
}

remote_start_wpa()
{
    log "Start remote wpa_supplicant on $STA_IF"

    remote_run "nohup $REMOTE_SUDO '$WPA_SUP_BIN' -D nl80211 -i '$STA_IF' -c '$WPA_CONF' $WPA_DBG_OPT > '$REMOTE_WPA_LOG' 2>&1 < /dev/null &"
    sleep 10
    remote_run "$REMOTE_SUDO '$WPA_CLI_BIN' -i '$STA_IF' status || true"
    remote_run "iw dev '$STA_IF' link || true"
    remote_run "tail -n 80 '$REMOTE_WPA_LOG' || true"
}

local_prepare_ap()
{
    log "Prepare local AP $AP_BASE_IF"

    sudo nmcli device set "$AP_BASE_IF" managed no || true
    sudo pkill -f "[h]ostapd.*$AP_BASE_IF" || true
    sudo pkill -f "[i]perf3 -s" || true
    sudo ip link set "$AP_BASE_IF" down || true
    sudo ip addr flush dev "$AP_BASE_IF" || true
    sudo ip link set "$AP_BASE_IF" up
    sudo ip addr add "$AP_IP" dev "$AP_BASE_IF"
    ip addr show dev "$AP_BASE_IF"
}

local_start_hostapd_root()
{
    log "Start local hostapd on $AP_BASE_IF"

    sudo mkdir -p /var/run/hostapd
    sudo "$HOSTAPD_BIN" $HOSTAPD_DBG_OPT -i "$AP_BASE_IF" "$HOSTAPD_CONF_MAIN" \
        > >(tee "$HOSTAPD_LOG") 2>&1 &
    HOSTAPD_PID=$!
    sleep 3
    tail -n 40 "$HOSTAPD_LOG" || true
}

local_prepare_sta()
{
    log "Prepare local STA $STA_IF"

    sudo nmcli device set "$STA_IF" managed no || true
    sudo pkill -f "[w]pa_supplicant.*$STA_IF" || true
    sudo ip link set "$STA_IF" down || true
    sudo ip addr flush dev "$STA_IF" || true
    sudo ip link set "$STA_IF" up
    sudo ip addr add "$STA_IP" dev "$STA_IF"
    ip addr show dev "$STA_IF"
}

local_start_wpa_root()
{
    log "Start local wpa_supplicant on $STA_IF"

    sudo mkdir -p /var/run/wpa_supplicant
    sudo "$WPA_SUP_BIN" -D nl80211 -i "$STA_IF" -c "$WPA_CONF" $WPA_DBG_OPT \
        > >(tee "$WPA_LOG") 2>&1 &
    WPA_PID=$!
    sleep 10
    sudo "$WPA_CLI_BIN" -i "$STA_IF" status || true
    iw dev "$STA_IF" link || true
}

local_sta_connectivity_test()
{
    log "Ping remote AP from local STA"
    ping -I "$STA_IF" -c 3 "$PING_TARGET"

    log "Start remote iperf3 server"
    remote_run "$REMOTE_SUDO pkill -f '[i]perf3 -s' || true"
    remote_run "nohup iperf3 -s > '$REMOTE_IPERF_LOG' 2>&1 < /dev/null &"
    sleep 1

    log "Run iperf3 local STA -> remote AP"
    "$IPERF3_BIN" -c "$PING_TARGET" 2>&1 | tee -a "$IPERF_LOG"

    log "Run iperf3 remote AP -> local STA"
    "$IPERF3_BIN" -c "$PING_TARGET" -R 2>&1 | tee -a "$IPERF_LOG"
}

remote_sta_connectivity_test()
{
    log "Ping local AP from remote STA"
    remote_run "ping -I '$STA_IF' -c 3 '$PING_TARGET'"

    log "Start local iperf3 server"
    sudo pkill -f "[i]perf3 -s" || true
    "$IPERF3_BIN" -s > >(tee "$IPERF_LOG") 2>&1 &
    sleep 1

    log "Run iperf3 remote STA -> local AP"
    remote_run "'$IPERF3_BIN' -c '$PING_TARGET'" 2>&1 | tee -a "$IPERF_LOG"

    log "Run iperf3 local AP -> remote STA"
    remote_run "'$IPERF3_BIN' -c '$PING_TARGET' -R" 2>&1 | tee -a "$IPERF_LOG"
}

run_two_host_test()
{
    setup_debug_opts
    two_host_validate_local
    two_host_precheck_remote

    case "$REMOTE_ROLE" in
    ap)
        remote_prepare_ap
        remote_start_hostapd
        local_prepare_sta
        local_start_wpa_root
        local_sta_connectivity_test
        ;;
    sta)
        local_prepare_ap
        local_start_hostapd_root
        remote_prepare_sta
        remote_start_wpa
        remote_sta_connectivity_test
        ;;
    *)
        die "Unknown REMOTE_ROLE=$REMOTE_ROLE"
        ;;
    esac

    log "Two-host test done"
}

run_local_ns_test()
{
    local_ns_validate_ifaces
    local_ns_prepare_roles
    local_ns_setup_namespaces
    local_ns_bringup_links
    setup_debug_opts
    local_ns_start_hostapd
    local_ns_start_wpa
    local_ns_connectivity_test
}

main()
{
    precheck_common
    show_log_paths

    case "$TEST_MODE" in
    local_ns)
        run_local_ns_test
        ;;
    two_host)
        run_two_host_test
        ;;
    *)
        die "Unknown TEST_MODE=$TEST_MODE"
        ;;
    esac
}

main "$@"
