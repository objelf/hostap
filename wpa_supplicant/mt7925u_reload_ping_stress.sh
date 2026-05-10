#!/bin/bash
set -euo pipefail

IFACE="wlx000c43baabd4"
IP_ADDR="192.168.1.111/24"
AP_IP="192.168.1.254"
MODULE="mt7925u"

TIMEOUT=20
PING_TASKS=50
PING_INTERVAL="0.01"
TEST_ROUNDS=1

log()
{
	echo "[$(date '+%F %T')] $*"
}

die()
{
	echo "[$(date '+%F %T')] ERROR: $*" >&2
	exit 1
}

wait_for_iface()
{
	local t=0

	log "waiting for interface $IFACE"

	while [ "$t" -lt "$TIMEOUT" ]; do
		if ip link show "$IFACE" >/dev/null 2>&1; then
			log "interface $IFACE found"
			return 0
		fi

		sleep 1
		t=$((t + 1))
	done

	die "interface $IFACE not found after ${TIMEOUT}s"
}

wait_for_link_up()
{
	local t=0

	log "waiting for $IFACE link/carrier ready"

	while [ "$t" -lt "$TIMEOUT" ]; do
		if ip link show "$IFACE" | grep -q "UP" &&
		   ! ip link show "$IFACE" | grep -q "NO-CARRIER"; then
			log "$IFACE carrier is ready"
			return 0
		fi

		ip -br link show "$IFACE" || true
		sleep 1
		t=$((t + 1))
	done

	die "$IFACE carrier not ready after ${TIMEOUT}s"
}

reload_module()
{
	log "killing old ping tasks before module reload"
	sudo killall ping 2>/dev/null || true
	sleep 1

	log "unloading module: $MODULE"
	sudo modprobe -r "$MODULE" || die "failed to unload $MODULE"

	sleep 2

	log "loading module: $MODULE"
	sudo modprobe "$MODULE" || die "failed to load $MODULE"

	wait_for_iface
}

setup_iface()
{
	log "configuring $IFACE"

	sudo ip link set "$IFACE" down || true
	sudo ip addr flush dev "$IFACE"
	sudo ip addr add "$IP_ADDR" dev "$IFACE"
	sudo ip link set "$IFACE" up
	sudo ip neigh flush dev "$IFACE" || true

	wait_for_link_up

	log "current interface status:"
	ip addr show dev "$IFACE"
}

check_ping_once()
{
	local t=0

	log "checking AP connectivity with retry: $AP_IP"

	while [ "$t" -lt "$TIMEOUT" ]; do
		if ping -I "$IFACE" -c 3 -W 1 "$AP_IP" >/tmp/ping_check.log 2>&1; then
			log "single ping check OK"
			return 0
		fi

		log "ping not ready yet, retrying..."
		ip -br link show "$IFACE" || true
		ip addr show dev "$IFACE" | grep inet || true
		sleep 1
		t=$((t + 1))
	done

	cat /tmp/ping_check.log
	die "single ping check failed after ${TIMEOUT}s"
}

start_ping_tasks()
{
	log "starting $PING_TASKS ping tasks"

	rm -f /tmp/ping_task_*.log

	for i in $(seq 1 "$PING_TASKS"); do
		ping -I "$IFACE" "$AP_IP" -i "$PING_INTERVAL" \
			>/tmp/ping_task_${i}.log 2>&1 &
	done

	sleep 3

	local running
	running=$(pgrep -c -x ping || true)

	log "running ping tasks: $running"

	if [ "$running" -lt "$PING_TASKS" ]; then
		log "warning: expected $PING_TASKS ping tasks, but only $running running"
	fi
}

check_parallel_ping_ok()
{
	local t=0

	log "checking if parallel ping tasks receive replies"

	while [ "$t" -lt "$TIMEOUT" ]; do
		if grep -q "bytes from $AP_IP" /tmp/ping_task_*.log 2>/dev/null; then
			log "parallel ping check OK"
			return 0
		fi

		sleep 1
		t=$((t + 1))
	done

	log "parallel ping logs:"
	tail -n 20 /tmp/ping_task_*.log 2>/dev/null || true

	die "parallel ping did not receive reply after ${TIMEOUT}s"
}

kill_ping_tasks()
{
	log "killing all ping tasks"

	sudo killall ping 2>/dev/null || true

	sleep 2

	if pgrep -x ping >/dev/null 2>&1; then
		die "some ping tasks still running"
	fi

	log "all ping tasks killed"
}

one_round()
{
	local round="$1"

	log "========== round $round start =========="

	reload_module
	setup_iface
	check_ping_once

	log "starting one foreground-style ping check in background"
	ping -I "$IFACE" "$AP_IP" -i "$PING_INTERVAL" >/tmp/ping_single_bg.log 2>&1 &
	sleep 3

	if grep -q "bytes from $AP_IP" /tmp/ping_single_bg.log; then
		log "background single ping OK"
	else
		cat /tmp/ping_single_bg.log
		die "background single ping failed"
	fi

	kill_ping_tasks

	start_ping_tasks
	check_parallel_ping_ok
	kill_ping_tasks

	log "reload modules again after ping stress"
	reload_module

	log "========== round $round done =========="
}

for round in $(seq 1 "$TEST_ROUNDS"); do
	one_round "$round"
done

log "test completed successfully"
