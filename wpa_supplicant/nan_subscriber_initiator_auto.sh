#!/usr/bin/env bash
set -euo pipefail

BASE_IF="${BASE_IF:-wlp58s0}"
NAN_IF="${NAN_IF:-nan0}"
NDI_IF="${NDI_IF:-ndi0}"

NAN_MAC="${NAN_MAC:-02:11:22:33:44:66}"
NDI_MAC="${NDI_MAC:-02:11:22:33:44:76}"

HOSTAP_DIR="${HOSTAP_DIR:-$HOME/dev/hostap/wpa_supplicant}"
CTRL_DIR="${CTRL_DIR:-/run/wpa_supplicant}"
GLOBAL_CTRL="${GLOBAL_CTRL:-/run/wpa_supplicant-global}"
CONF="${CONF:-/tmp/wpa_nan_dummy_subscriber.conf}"

WPAS_LOG="${WPAS_LOG:-/tmp/wpas_nan_subscriber_initiator.log}"
EVENT_LOG="${EVENT_LOG:-/tmp/wpas_nan_subscriber_initiator_events.log}"

SERVICE_NAME="${SERVICE_NAME:-mt76.nan.test}"
FREQ="${FREQ:-2437}"
CLUSTER_ID="${CLUSTER_ID:-50:6f:9a:01:00:01}"
SCHED_MAP="${SCHED_MAP:-map_id=1 ${FREQ}:ffffffff}"

WPAS="$HOSTAP_DIR/wpa_supplicant"
WPA_CLI="$HOSTAP_DIR/wpa_cli"

WPAS_PID=""
NDI_CREATED=0

die()
{
	echo "[ERR] $*" >&2
	exit 1
}

cleanup_all()
{
	echo
	echo "[INFO] cleanup all"

	if [ -n "${WPAS_PID:-}" ]; then
		echo "[INFO] stopping wpa_supplicant pid=$WPAS_PID"
		sudo kill "$WPAS_PID" 2>/dev/null || true
		wait "$WPAS_PID" 2>/dev/null || true
	fi

	echo "[INFO] deleting NAN/NDI interfaces if present"
	sudo ip link set "$NDI_IF" down 2>/dev/null || true
	sudo iw dev "$NDI_IF" del 2>/dev/null || true
	sudo iw dev "$NAN_IF" del 2>/dev/null || true

	echo "[INFO] removing control sockets"
	sudo rm -f "$GLOBAL_CTRL" 2>/dev/null || true
	sudo rm -f "$CTRL_DIR/$NAN_IF" 2>/dev/null || true
	sudo rm -f "$CTRL_DIR/$NDI_IF" 2>/dev/null || true
	sudo rm -f "$CTRL_DIR/$BASE_IF" 2>/dev/null || true

	echo "[INFO] restoring $BASE_IF to NetworkManager"
	sudo ip link set "$BASE_IF" up 2>/dev/null || true
	sudo nmcli dev set "$BASE_IF" managed yes 2>/dev/null || true

	echo "[OK] cleanup done"
}

trap cleanup_all EXIT INT TERM

run_global()
{
	echo "+ sudo $WPA_CLI -g $GLOBAL_CTRL $*"
	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" "$@"
}

run_nan()
{
	echo "+ sudo $WPA_CLI -g $GLOBAL_CTRL IFNAME=$NAN_IF $*"
	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" "IFNAME=$NAN_IF" "$@"
}

wait_for_path()
{
	local path="$1"
	local name="$2"
	local i

	for i in $(seq 1 80); do
		if [ -S "$path" ]; then
			echo "[OK] $name is ready: $path"
			return 0
		fi
		sleep 0.1
	done

	echo "[ERR] $name was not ready: $path"
	echo "[INFO] tail wpa_supplicant log:"
	tail -120 "$WPAS_LOG" 2>/dev/null || true
	exit 1
}

wait_for_iface()
{
	local ifname="$1"
	local i

	for i in $(seq 1 80); do
		if ip link show "$ifname" >/dev/null 2>&1; then
			echo "[OK] interface exists: $ifname"
			return 0
		fi
		sleep 0.1
	done

	echo "[ERR] interface was not visible: $ifname"
	echo "[INFO] current interfaces:"
	ip link show || true
	echo "[INFO] tail wpa_supplicant log:"
	tail -160 "$WPAS_LOG" 2>/dev/null || true
	exit 1
}

pre_cleanup()
{
	echo "[INFO] pre-cleanup old NAN test state"

	sudo pkill -f "wpa_supplicant.*${BASE_IF}" 2>/dev/null || true
	sudo rm -f "$GLOBAL_CTRL" 2>/dev/null || true
	sudo rm -rf "$CTRL_DIR"/* 2>/dev/null || true
	sudo mkdir -p "$CTRL_DIR"

	sudo iw dev "$NDI_IF" del 2>/dev/null || true
	sudo iw dev "$NAN_IF" del 2>/dev/null || true
}

create_conf()
{
	echo "[INFO] writing $CONF"

	sudo tee "$CONF" >/dev/null <<EOF
ctrl_interface=$CTRL_DIR
update_config=1
p2p_disabled=1
ap_scan=0
EOF

	echo "[INFO] config:"
	cat "$CONF"
	ls -l "$CONF"
}

prepare_base_if()
{
	echo "[INFO] disable NetworkManager on $BASE_IF"
	sudo nmcli dev set "$BASE_IF" managed no || true

	echo "[INFO] bring $BASE_IF down"
	sudo ip link set "$BASE_IF" down || true
}

start_wpas()
{
	echo "[INFO] starting wpa_supplicant on $BASE_IF"
	cd "$HOSTAP_DIR"

	sudo "$WPAS" \
		-i "$BASE_IF" \
		-D nl80211 \
		-c "$CONF" \
		-g "$GLOBAL_CTRL" \
		-ddd -t -K >"$WPAS_LOG" 2>&1 &

	WPAS_PID=$!

	echo "[INFO] wpa_supplicant pid=$WPAS_PID"
	echo "[INFO] wpa_supplicant log=$WPAS_LOG"

	wait_for_path "$GLOBAL_CTRL" "global control"
}

create_nan_if()
{
	echo "[INFO] creating $NAN_IF mac=$NAN_MAC"

	run_global interface_add "$NAN_IF" "" nl80211 "$CTRL_DIR" "" "" create nan "$NAN_MAC" ||
		die "failed to create $NAN_IF"

	# NAN DEVICE may not appear as a Linux netdev and may not create
	# /run/wpa_supplicant/$NAN_IF. Use global ctrl + IFNAME=$NAN_IF.
	sleep 0.5
}


wait_for_cluster_join()
{
	local timeout="${1:-30}"
	local start now out cid

	echo "[INFO] waiting for NAN cluster join, timeout=${timeout}s"
	start="$(date +%s)"

	while true; do
		out="$(run_nan nan_status 2>/dev/null || true)"
		echo "$out"

		cid="$(echo "$out" | awk -F= '/^cluster_id=/ {print $2; exit}')"

		if [ -n "$cid" ] && [ "$cid" != "00:00:00:00:00:00" ]; then
			echo "[OK] NAN cluster joined: cluster_id=$cid"
			return 0
		fi

		now="$(date +%s)"
		if [ "$((now - start))" -ge "$timeout" ]; then
			echo "[ERR] NAN cluster did not join within ${timeout}s"
			echo "[INFO] tail wpa_supplicant log:"
			grep -iE "NAN|cluster|nan_start|nan_set|nan_publish|nan_subscribe|failed|FAIL" "$WPAS_LOG" | tail -200 || true
			return 1
		fi

		sleep 0.5
	done
}


configure_nan()
{
	echo "[INFO] setting cluster id before NAN start: $CLUSTER_ID"
	run_nan nan_set cluster_id "$CLUSTER_ID" ||
		die "nan_set cluster_id failed"

	echo "[INFO] starting NAN"
	run_nan nan_start ||
		die "nan_start failed"

	wait_for_cluster_join 30 ||
		die "NAN cluster join failed"

	echo "[INFO] setting schedule map: $SCHED_MAP"
	run_nan nan_sched_config_map $SCHED_MAP ||
		die "nan_sched_config_map failed"

	echo "[INFO] applying NAN config"
	run_nan nan_update_conf ||
		die "nan_update_conf failed"

	echo "[INFO] NAN status"
	run_nan nan_status || true
}


subscribe_service()
{
	echo "[INFO] subscribing service=$SERVICE_NAME freq=$FREQ"

	SUB_RET="$(
		run_nan nan_subscribe \
			service_name="$SERVICE_NAME" \
			active=1 \
			ttl=0 \
			freq="$FREQ" \
			sync=1 \
			data_path=1 || true
	)"

	echo "$SUB_RET"

	SUBSCRIBE_ID="$(echo "$SUB_RET" | awk '/^[0-9]+$/ {print $1; exit}')"

	if [ -n "${SUBSCRIBE_ID:-}" ]; then
		echo "[OK] subscribe id=$SUBSCRIBE_ID"
	else
		echo "[WARN] cannot parse subscribe id from output"
		echo "[WARN] will use subscribe_id from NAN-DISCOVERY-RESULT event"
	fi

	run_nan nan_status || true
}

create_ndi_if()
{
	if ip link show "$NDI_IF" >/dev/null 2>&1; then
		echo "[OK] $NDI_IF already exists"
		NDI_CREATED=1
		return 0
	fi

	echo "[INFO] creating $NDI_IF mac=$NDI_MAC"

	run_global interface_add "$NDI_IF" "" nl80211 "$CTRL_DIR" "" "" create nan_data "$NDI_MAC" ||
		die "failed to create $NDI_IF"

	wait_for_iface "$NDI_IF"
	NDI_CREATED=1

	echo "[INFO] bring $NDI_IF up"
	sudo ip link set "$NDI_IF" up || true
	ip link show "$NDI_IF" || true

	if [ -S "$CTRL_DIR/$NDI_IF" ]; then
		echo "[OK] $NDI_IF control is ready: $CTRL_DIR/$NDI_IF"
	else
		echo "[INFO] $NDI_IF control socket not present; continue"
	fi
}

send_ndp_request()
{
	local subscribe_id="$1"
	local peer_publish_id="$2"
	local peer_nmi="$3"

	echo "[INFO] sending NDP request"
	echo "       handle=$subscribe_id"
	echo "       peer_id=$peer_publish_id"
	echo "       peer_nmi=$peer_nmi"
	echo "       ndi=$NDI_IF"

	run_nan nan_ndp_request \
		handle="$subscribe_id" \
		ndi="$NDI_IF" \
		peer_nmi="$peer_nmi" \
		peer_id="$peer_publish_id"
}

start_event_initiator()
{
	echo "[INFO] event initiator started"
	echo "[INFO] waiting for NAN-DISCOVERY-RESULT"
	echo "[INFO] event log=$EVENT_LOG"
	echo "[INFO] press Ctrl+C to stop and cleanup"

	declare -A requested

	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" | tee "$EVENT_LOG" | \
	while IFS= read -r line; do
		echo "[$(date '+%F %T.%3N')] [EVT] $line"

		case "$line" in
		*NAN-DISCOVERY-RESULT*)
			subscribe_id="$(echo "$line" | sed -n 's/.*subscribe_id=\([0-9]*\).*/\1/p')"
			publish_id="$(echo "$line" | sed -n 's/.*publish_id=\([0-9]*\).*/\1/p')"
			peer_nmi="$(echo "$line" | sed -n 's/.*address=\([0-9a-fA-F:]*\).*/\1/p')"
			data_path="$(echo "$line" | sed -n 's/.*data_path=\([0-9]*\).*/\1/p')"

			if [ -z "$subscribe_id" ] || [ -z "$publish_id" ] || [ -z "$peer_nmi" ]; then
				echo "[WARN] failed to parse NAN-DISCOVERY-RESULT:"
				echo "       $line"
				continue
			fi

			key="${subscribe_id}_${publish_id}_${peer_nmi}"

			if [ "${requested[$key]+yes}" = "yes" ]; then
				continue
			fi

			if [ -n "$data_path" ] && [ "$data_path" != "1" ]; then
				echo "[WARN] discovery result has data_path=$data_path, skip NDP request"
				continue
			fi

			requested[$key]=1

			if send_ndp_request "$subscribe_id" "$publish_id" "$peer_nmi"; then
				echo "[OK] nan_ndp_request sent"
			else
				echo "[ERR] nan_ndp_request failed"
				echo "[INFO] tail wpa_supplicant log:"
				tail -160 "$WPAS_LOG" || true
			fi
			;;

		*NAN-NDP-CONNECTED*)
			echo "[OK] NDP connected"
			ip link show "$NDI_IF" || true
			;;

		*NAN-NDP-DISCONNECTED*)
			echo "[INFO] NDP disconnected"
			;;

		*CTRL-EVENT-TERMINATING*)
			echo "[INFO] wpa_supplicant terminating"
			break
			;;
		esac
	done
}

main()
{
	[ -x "$WPAS" ] || die "missing executable: $WPAS"
	[ -x "$WPA_CLI" ] || die "missing executable: $WPA_CLI"

	echo "=== NAN subscriber + NDP initiator auto test ==="
	echo "BASE_IF=$BASE_IF"
	echo "NAN_IF=$NAN_IF"
	echo "NDI_IF=$NDI_IF"
	echo "NAN_MAC=$NAN_MAC"
	echo "NDI_MAC=$NDI_MAC"
	echo "SERVICE_NAME=$SERVICE_NAME"
	echo "FREQ=$FREQ"
	echo "HOSTAP_DIR=$HOSTAP_DIR"

	create_conf
	pre_cleanup
	prepare_base_if
	start_wpas
	create_nan_if
	configure_nan
	subscribe_service
	create_ndi_if
	start_event_initiator
}

main "$@"
