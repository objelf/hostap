#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_HOST="${REMOTE_HOST:?REMOTE_HOST is required, e.g. sean@192.168.1.147}"
REMOTE_SSH_KEY="${REMOTE_SSH_KEY:-/home/sean/.ssh/sta_ap_test_ed25519}"

HOSTAPD_BIN="${HOSTAPD_BIN:-/home/sean/dev/hostap/hostapd/hostapd}"
WPA_SUP_BIN="${WPA_SUP_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_supplicant}"
WPA_CLI_BIN="${WPA_CLI_BIN:-/home/sean/dev/hostap/wpa_supplicant/wpa_cli}"

echo "[INFO] Ensure local SSH key exists: $REMOTE_SSH_KEY"
if [[ ! -f "$REMOTE_SSH_KEY" ]]; then
    ssh-keygen -t ed25519 -f "$REMOTE_SSH_KEY" -C "sta-ap-test"
fi

echo "[INFO] Install SSH key to $REMOTE_HOST"
ssh-copy-id \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -i "${REMOTE_SSH_KEY}.pub" \
    "$REMOTE_HOST"

echo "[INFO] Install limited sudoers rule on remote"
ssh -tt "$REMOTE_HOST" "cat <<'SUDOERS' | sudo tee /etc/sudoers.d/sta-ap-test >/dev/null
sean ALL=(root) NOPASSWD: /usr/sbin/ip, /usr/sbin/iw, /usr/bin/nmcli, /usr/bin/pkill, /usr/bin/kill, /usr/bin/iperf3, $HOSTAPD_BIN, $WPA_SUP_BIN, $WPA_CLI_BIN
SUDOERS
sudo chmod 0440 /etc/sudoers.d/sta-ap-test
sudo visudo -cf /etc/sudoers.d/sta-ap-test"

echo "[INFO] Verify SSH key login"
ssh -i "$REMOTE_SSH_KEY" -o BatchMode=yes "$REMOTE_HOST" hostname

echo "[INFO] Verify remote sudo -n"
ssh -i "$REMOTE_SSH_KEY" -o BatchMode=yes "$REMOTE_HOST" "sudo -n /usr/sbin/ip link show >/dev/null && echo sudo-ok"

echo "[INFO] Verify remote test binaries/configs"
ssh -i "$REMOTE_SSH_KEY" -o BatchMode=yes "$REMOTE_HOST" \
    "test -x '$HOSTAPD_BIN' && test -x '$WPA_SUP_BIN' && test -x '$WPA_CLI_BIN' && echo remote-binaries-ok"

echo "[INFO] Remote two-host setup done"
