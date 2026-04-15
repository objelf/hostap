#!/usr/bin/env bash
set -u

NS_AP="${NS_AP:-ns_ap}"
NS_STA="${NS_STA:-ns_sta}"
AP_VIF="${AP_VIF:-ap0}"

echo "[INFO] kill old processes"
sudo pkill -f hostapd || true
sudo pkill -f wpa_supplicant || true
sudo pkill -f "iperf3 -s" || true

echo "[INFO] delete old namespaces"
sudo ip netns del "$NS_AP" 2>/dev/null || true
sudo ip netns del "$NS_STA" 2>/dev/null || true

echo "[INFO] delete old AP interface"
sudo iw dev "$AP_VIF" del 2>/dev/null || true

echo "[INFO] current iw dev"
iw dev || true

echo "[INFO] current ip link show"
ip link show || true
