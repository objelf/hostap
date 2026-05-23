#!/bin/bash
set -euo pipefail

DUT=${DUT:-wlx000c43baabd4}
PEER=${PEER:-wlx06ea2b7bab9b}

DUT_P2P_ADDR=${DUT_P2P_ADDR:-02:0c:43:ba:ab:d4}
PEER_P2P_ADDR=${PEER_P2P_ADDR:-02:ea:2b:7b:ab:9b}

HOSTAP_DIR=${HOSTAP_DIR:-$HOME/dev/hostap/wpa_supplicant}

DUT_CTRL=/tmp/wpa-p2p-dut
PEER_CTRL=/tmp/wpa-p2p-peer

DUT_CONF=/tmp/p2p_dut.conf
PEER_CONF=/tmp/p2p_peer.conf

DUT_LOG=/tmp/wpa_dut_p2p_auto.log
PEER_LOG=/tmp/wpa_peer_p2p_auto.log

DUT_NAME=mt7927u-dut
PEER_NAME=mt7902u-peer

SOCIAL_FIND_TIME=8
LISTEN_TIME=30
CONNECT_WAIT=25
DISCOVERY_ROUNDS=${DISCOVERY_ROUNDS:-10}
DISCOVERY_WAIT=${DISCOVERY_WAIT:-5}

echo "============================================================"
echo "[INFO] P2P auto test"
echo "[INFO] DUT=$DUT"
echo "[INFO] PEER=$PEER"
echo "[INFO] HOSTAP_DIR=$HOSTAP_DIR"
echo "============================================================"

if [ ! -x "$HOSTAP_DIR/wpa_supplicant" ] || [ ! -x "$HOSTAP_DIR/wpa_cli" ]; then
    echo "[ERROR] Cannot find wpa_supplicant/wpa_cli under $HOSTAP_DIR"
    exit 1
fi

WPA_SUPP="$HOSTAP_DIR/wpa_supplicant"
WPA_CLI="$HOSTAP_DIR/wpa_cli"

cleanup()
{
    echo
    echo "[CLEANUP] stopping only test supplicants"
    sudo "$WPA_CLI" -p "$DUT_CTRL" -i "$DUT" p2p_stop_find >/dev/null 2>&1 || true
    sudo "$WPA_CLI" -p "$PEER_CTRL" -i "$PEER" p2p_stop_find >/dev/null 2>&1 || true

    if [ -n "${DUT_SUPP_PID:-}" ]; then
        sudo kill "$DUT_SUPP_PID" >/dev/null 2>&1 || true
    fi

    if [ -n "${PEER_SUPP_PID:-}" ]; then
        sudo kill "$PEER_SUPP_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

run_cli()
{
    local ctrl="$1"
    local ifname="$2"
    shift 2

    sudo "$WPA_CLI" -p "$ctrl" -i "$ifname" "$@"
}

wait_ctrl()
{
    local ctrl="$1"
    local ifname="$2"
    local name="$3"

    echo "[INFO] waiting for $name ctrl interface..."

    for i in $(seq 1 40); do
        if sudo "$WPA_CLI" -p "$ctrl" -i "$ifname" ping 2>/dev/null | grep -q PONG; then
            echo "[OK] $name ctrl ready"
            return 0
        fi
        sleep 0.25
    done

    echo "[ERROR] $name ctrl not ready"
    return 1
}

get_target_peer()
{
    local ctrl="$1"
    local ifname="$2"
    local target="$3"

    sudo "$WPA_CLI" -p "$ctrl" -i "$ifname" p2p_peers 2>/dev/null | \
        awk -v t="$target" 'tolower($1) == tolower(t) { print $1; exit }'
}

print_peer_detail()
{
    local ctrl="$1"
    local ifname="$2"
    local peer="$3"
    local label="$4"

    echo
    echo "==================== [$label] peer detail: $peer ===================="
    sudo "$WPA_CLI" -p "$ctrl" -i "$ifname" p2p_peer "$peer" || true
}

wait_peer()
{
    local ctrl="$1"
    local ifname="$2"
    local label="$3"
    local timeout="$4"
    local target="$5"

    echo "[INFO] waiting for target peer $target on $label for ${timeout}s..."

    for i in $(seq 1 "$timeout"); do
        peer=$(get_target_peer "$ctrl" "$ifname" "$target" || true)
        if [ -n "$peer" ]; then
            echo "[OK] $label found target peer: $peer"
            echo "$peer"
            return 0
        fi

        echo "[DEBUG] $label current peers:"
        sudo "$WPA_CLI" -p "$ctrl" -i "$ifname" p2p_peers 2>/dev/null || true
        sleep 1
    done

    echo "[WARN] $label did not find target peer $target"
    return 1
}

wait_group_started()
{
    local logfile="$1"
    local label="$2"
    local timeout="$3"

    echo "[INFO] waiting for P2P-GROUP-STARTED on $label..."

    for i in $(seq 1 "$timeout"); do
        if grep -q "P2P-GROUP-STARTED" "$logfile" 2>/dev/null; then
            echo "[OK] $label group started"
            grep "P2P-GROUP-STARTED" "$logfile" | tail -5
            return 0
        fi

        if grep -q "P2P-GO-NEG-FAILURE\|P2P-GROUP-FORMATION-FAILURE" "$logfile" 2>/dev/null; then
            echo "[WARN] $label saw P2P failure"
            grep -E "P2P-GO-NEG-FAILURE|P2P-GROUP-FORMATION-FAILURE" "$logfile" | tail -10
            return 1
        fi

        sleep 1
    done

    echo "[WARN] no P2P-GROUP-STARTED on $label"
    return 1
}

echo
echo "[STEP 0] detach test interfaces from NetworkManager"
sudo nmcli dev disconnect "$DUT" 2>/dev/null || true
sudo nmcli dev disconnect "$PEER" 2>/dev/null || true
sudo nmcli dev set "$DUT" managed no 2>/dev/null || true
sudo nmcli dev set "$PEER" managed no 2>/dev/null || true

sudo ip link set "$DUT" down || true
sudo ip link set "$PEER" down || true
sudo ip link set "$DUT" up
sudo ip link set "$PEER" up

echo
echo "[STEP 1] show PHY and P2P capability"
for IF in "$DUT" "$PEER"; do
    PHY=$(iw dev "$IF" info | awk '/wiphy/ {print "phy"$2}')
    echo
    echo "===== $IF / $PHY ====="
    iw phy "$PHY" info | sed -n '/Supported interface modes:/,/Band /p' | head -40
done

echo
echo "[STEP 2] prepare ctrl dirs and configs"
sudo rm -rf "$DUT_CTRL" "$PEER_CTRL"
sudo mkdir -p "$DUT_CTRL" "$PEER_CTRL"
sudo chmod 777 "$DUT_CTRL" "$PEER_CTRL"

sudo tee "$DUT_CONF" >/dev/null <<EOF
ctrl_interface=$DUT_CTRL
update_config=1
device_name=$DUT_NAME
manufacturer=MediaTek
model_name=mt7927u
model_number=1
serial_number=1
device_type=1-0050F204-1
config_methods=virtual_push_button
p2p_disabled=0
EOF

sudo tee "$PEER_CONF" >/dev/null <<EOF
ctrl_interface=$PEER_CTRL
update_config=1
device_name=$PEER_NAME
manufacturer=MediaTek
model_name=mt7902u
model_number=1
serial_number=1
device_type=1-0050F204-1
config_methods=virtual_push_button
p2p_disabled=0
EOF

sudo rm -f "$DUT_LOG" "$PEER_LOG"

echo
echo "[STEP 3] start DUT supplicant"
sudo "$WPA_SUPP" \
    -i "$DUT" \
    -c "$DUT_CONF" \
    -D nl80211 \
    -ddd -t >"$DUT_LOG" 2>&1 &
DUT_SUPP_PID=$!

echo "[INFO] DUT supplicant pid=$DUT_SUPP_PID log=$DUT_LOG"

echo
echo "[STEP 4] start PEER supplicant"
sudo "$WPA_SUPP" \
    -i "$PEER" \
    -c "$PEER_CONF" \
    -D nl80211 \
    -ddd -t >"$PEER_LOG" 2>&1 &
PEER_SUPP_PID=$!

echo "[INFO] PEER supplicant pid=$PEER_SUPP_PID log=$PEER_LOG"

wait_ctrl "$DUT_CTRL" "$DUT" "DUT"
wait_ctrl "$PEER_CTRL" "$PEER" "PEER"

echo
echo "[STEP 5] show status and flags"
echo "=== DUT status ==="
run_cli "$DUT_CTRL" "$DUT" status || true
echo "=== DUT driver_flags ==="
run_cli "$DUT_CTRL" "$DUT" driver_flags | grep -E 'P2P|OFFCHANNEL|DEDICATED|ROC' || true

echo "=== PEER status ==="
run_cli "$PEER_CTRL" "$PEER" status || true
echo "=== PEER driver_flags ==="
run_cli "$PEER_CTRL" "$PEER" driver_flags | grep -E 'P2P|OFFCHANNEL|DEDICATED|ROC' || true

echo
echo "[STEP 6] set config_methods at runtime"
run_cli "$DUT_CTRL" "$DUT" set config_methods virtual_push_button || true
run_cli "$PEER_CTRL" "$PEER" set config_methods virtual_push_button || true

echo
echo "[STEP 7] flush old P2P state"
run_cli "$DUT_CTRL" "$DUT" p2p_stop_find >/dev/null 2>&1 || true
run_cli "$PEER_CTRL" "$PEER" p2p_stop_find >/dev/null 2>&1 || true
run_cli "$DUT_CTRL" "$DUT" p2p_flush >/dev/null 2>&1 || true
run_cli "$PEER_CTRL" "$PEER" p2p_flush >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "[DISCOVERY LOOP] alternate listen/find until both peers are visible"
echo "============================================================"

DUT_SEES_PEER=""
PEER_SEES_DUT=""

for round in $(seq 1 "$DISCOVERY_ROUNDS"); do
    echo
    echo "------------------------------------------------------------"
    echo "[ROUND $round/$DISCOVERY_ROUNDS] PEER listen, DUT find"
    echo "------------------------------------------------------------"

    run_cli "$DUT_CTRL" "$DUT" p2p_stop_find >/dev/null 2>&1 || true
    run_cli "$PEER_CTRL" "$PEER" p2p_stop_find >/dev/null 2>&1 || true

    run_cli "$DUT_CTRL" "$DUT" p2p_flush >/dev/null 2>&1 || true
    run_cli "$PEER_CTRL" "$PEER" p2p_flush >/dev/null 2>&1 || true

    echo "[PEER] p2p_listen $LISTEN_TIME"
    run_cli "$PEER_CTRL" "$PEER" p2p_listen "$LISTEN_TIME" || true
    sleep 1

    echo "[DUT] p2p_find type=social"
    if ! run_cli "$DUT_CTRL" "$DUT" p2p_find type=social; then
        echo "[WARN] DUT p2p_find type=social failed, try plain p2p_find"
        run_cli "$DUT_CTRL" "$DUT" p2p_find || true
    fi

    for i in $(seq 1 "$DISCOVERY_WAIT"); do
        DUT_SEES_PEER=$(get_target_peer "$DUT_CTRL" "$DUT" "$PEER_P2P_ADDR" || true)
        if [ -n "$DUT_SEES_PEER" ]; then
            echo "[OK] DUT sees target PEER: $DUT_SEES_PEER"
            print_peer_detail "$DUT_CTRL" "$DUT" "$DUT_SEES_PEER" "DUT sees PEER"
            break
        fi
        echo "[DEBUG] DUT peers:"
        run_cli "$DUT_CTRL" "$DUT" p2p_peers || true
        sleep 1
    done

    echo
    echo "------------------------------------------------------------"
    echo "[ROUND $round/$DISCOVERY_ROUNDS] DUT listen, PEER find"
    echo "------------------------------------------------------------"

    run_cli "$DUT_CTRL" "$DUT" p2p_stop_find >/dev/null 2>&1 || true
    run_cli "$PEER_CTRL" "$PEER" p2p_stop_find >/dev/null 2>&1 || true

    echo "[DUT] p2p_listen $LISTEN_TIME"
    run_cli "$DUT_CTRL" "$DUT" p2p_listen "$LISTEN_TIME" || true
    sleep 1

    echo "[PEER] p2p_find type=social"
    if ! run_cli "$PEER_CTRL" "$PEER" p2p_find type=social; then
        echo "[WARN] PEER p2p_find type=social failed, try plain p2p_find"
        run_cli "$PEER_CTRL" "$PEER" p2p_find || true
    fi

    for i in $(seq 1 "$DISCOVERY_WAIT"); do
        PEER_SEES_DUT=$(get_target_peer "$PEER_CTRL" "$PEER" "$DUT_P2P_ADDR" || true)
        if [ -n "$PEER_SEES_DUT" ]; then
            echo "[OK] PEER sees target DUT: $PEER_SEES_DUT"
            print_peer_detail "$PEER_CTRL" "$PEER" "$PEER_SEES_DUT" "PEER sees DUT"
            break
        fi
        echo "[DEBUG] PEER peers:"
        run_cli "$PEER_CTRL" "$PEER" p2p_peers || true
        sleep 1
    done

    if [ -n "$DUT_SEES_PEER" ] && [ -n "$PEER_SEES_DUT" ]; then
        echo
        echo "[OK] Bidirectional discovery complete"
        break
    fi

    echo
    echo "[INFO] target not ready yet:"
    echo "       DUT_SEES_PEER=${DUT_SEES_PEER:-no}"
    echo "       PEER_SEES_DUT=${PEER_SEES_DUT:-no}"
done

if [ -z "$DUT_SEES_PEER" ] || [ -z "$PEER_SEES_DUT" ]; then
    echo
    echo "[WARN] Bidirectional discovery not complete after $DISCOVERY_ROUNDS rounds"
    echo "[WARN] Skip connect to avoid connecting to unrelated P2P devices"
fi

echo
echo "============================================================"
echo "[CONNECT] Try PBC GO negotiation"
echo "============================================================"

# Prefer DUT as GO if it saw peer.
if [ -n "${DUT_SEES_PEER:-}" ] && [[ "$DUT_SEES_PEER" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    TARGET="$DUT_SEES_PEER"
    echo "[INFO] DUT will connect to PEER=$TARGET with go_intent=15"

    run_cli "$DUT_CTRL" "$DUT" p2p_stop_find >/dev/null 2>&1 || true
    run_cli "$PEER_CTRL" "$PEER" p2p_stop_find >/dev/null 2>&1 || true

    run_cli "$DUT_CTRL" "$DUT" p2p_connect "$TARGET" pbc go_intent=15 || true

    sleep 2

    # If peer saw DUT, also authorize/connect from peer side.
    if [ -n "${PEER_SEES_DUT:-}" ] && [[ "$PEER_SEES_DUT" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "[INFO] PEER also connects/authorizes DUT=$PEER_SEES_DUT with go_intent=0"
        run_cli "$PEER_CTRL" "$PEER" p2p_connect "$PEER_SEES_DUT" pbc go_intent=0 || true
    else
        echo "[WARN] PEER did not have DUT peer entry; waiting for request/event only"
    fi
else
    echo "[WARN] DUT has no valid peer MAC, skip p2p_connect"
fi

wait_group_started "$DUT_LOG" "DUT" "$CONNECT_WAIT" || true
wait_group_started "$PEER_LOG" "PEER" "$CONNECT_WAIT" || true

echo
echo "============================================================"
echo "[RESULT] Interfaces"
echo "============================================================"
iw dev

echo
echo "============================================================"
echo "[RESULT] P2P peers"
echo "============================================================"
echo "=== DUT p2p_peers ==="
run_cli "$DUT_CTRL" "$DUT" p2p_peers || true
echo "=== PEER p2p_peers ==="
run_cli "$PEER_CTRL" "$PEER" p2p_peers || true

echo
echo "============================================================"
echo "[RESULT] Important DUT log"
echo "============================================================"
grep -iE 'P2P-|p2p|go-neg|group|listen|find|remain|roc|offchannel|fail|failed|error|busy|not supported|nl80211' \
    "$DUT_LOG" | tail -120 || true

echo
echo "============================================================"
echo "[RESULT] Important PEER log"
echo "============================================================"
grep -iE 'P2P-|p2p|go-neg|group|listen|find|remain|roc|offchannel|fail|failed|error|busy|not supported|nl80211' \
    "$PEER_LOG" | tail -120 || true

echo
echo "[DONE] Logs:"
echo "  DUT : $DUT_LOG"
echo "  PEER: $PEER_LOG"
