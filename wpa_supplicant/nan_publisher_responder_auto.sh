#!/usr/bin/env bash
set -euo pipefail

BASE_IF="${BASE_IF:-wlp58s0}"
NAN_IF="${NAN_IF:-nan0}"
NDI_IF="${NDI_IF:-ndi0}"

NAN_MAC="${NAN_MAC:-02:11:22:33:44:55}"
NDI_MAC="${NDI_MAC:-02:11:22:33:44:75}"

HOSTAP_DIR="${HOSTAP_DIR:-$HOME/dev/hostap2/hostap/wpa_supplicant}"
CTRL_DIR="${CTRL_DIR:-/run/wpa_supplicant}"
GLOBAL_CTRL="${GLOBAL_CTRL:-/run/wpa_supplicant-global}"
CONF="${CONF:-/tmp/wpa_nan_dummy.conf}"

WPAS_LOG="${WPAS_LOG:-/tmp/wpas_nan_publisher_responder.log}"
EVENT_LOG="${EVENT_LOG:-/tmp/wpas_nan_publisher_responder_events.log}"

SERVICE_NAME="${SERVICE_NAME:-mt76.nan.test}"
FREQ="${FREQ:-2437}"
CLUSTER_ID="${CLUSTER_ID:-50:6f:9a:01:00:01}"
SCHED_MAP="${SCHED_MAP:-map_id=1 ${FREQ}:ffffffff}"

WPAS="$HOSTAP_DIR/wpa_supplicant"
WPA_CLI="$HOSTAP_DIR/wpa_cli"

WPAS_PID=""

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
	sudo ip link set "$NAN_IF" down 2>/dev/null || true
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

run_cli()
{
	echo "+ sudo $WPA_CLI -g $GLOBAL_CTRL IFNAME=$NAN_IF $*"
	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" "IFNAME=$NAN_IF" "$@"
}

run_global()
{
	echo "+ sudo $WPA_CLI -g $GLOBAL_CTRL $*"
	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" "$@"
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
	tail -120 "$WPAS_LOG" 2>/dev/null || true
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
	# Do not require $CTRL_DIR/$BASE_IF. NAN is created through global ctrl.
}

create_nan_if()
{
	echo "[INFO] creating $NAN_IF mac=$NAN_MAC"

	run_global interface_add "$NAN_IF" "" nl80211 "$CTRL_DIR" "" "" create nan "$NAN_MAC" ||
		die "failed to create $NAN_IF"

	# NAN DEVICE may not appear as a Linux netdev and this hostap build may not
	# create /run/wpa_supplicant/$NAN_IF. Use global ctrl + IFNAME=$NAN_IF.
	sleep 0.5
}

create_ndi_if()
{
	echo "[INFO] creating $NDI_IF mac=$NDI_MAC"

	run_global interface_add "$NDI_IF" "" nl80211 "$CTRL_DIR" "" "" create nan_data "$NDI_MAC" ||
		die "failed to create $NDI_IF"

	wait_for_iface "$NDI_IF"

	# Some hostap versions may not create a separate ctrl socket for NDI.
	# Do not fail here; NDI is used as data interface name in NDP response.
	if [ -S "$CTRL_DIR/$NDI_IF" ]; then
		echo "[OK] $NDI_IF control is ready: $CTRL_DIR/$NDI_IF"
	else
		echo "[INFO] $NDI_IF control socket not present; continue"
	fi
}

configure_nan()
{
	echo "[INFO] starting NAN"

	run_cli nan_start || die "nan_start failed"

	echo "[INFO] setting cluster id: $CLUSTER_ID"
	run_cli nan_set cluster_id "$CLUSTER_ID" ||
		die "nan_set cluster_id failed"

	echo "[INFO] setting schedule map: $SCHED_MAP"
	run_cli nan_sched_config_map $SCHED_MAP ||
		die "nan_sched_config_map failed"

	echo "[INFO] applying NAN config"
	run_cli nan_update_conf ||
		die "nan_update_conf failed"

	echo "[INFO] NAN status"
	run_cli nan_status || true
}

publish_service()
{
	echo "[INFO] publishing service=$SERVICE_NAME freq=$FREQ"

	PUB_RET="$(
		run_cli nan_publish \
			service_name="$SERVICE_NAME" \
			ttl=0 \
			freq="$FREQ" \
			sync=1 \
			data_path=1 || true
	)"

	echo "$PUB_RET"

	PUBLISH_ID="$(echo "$PUB_RET" | awk '/^[0-9]+$/ {print $1; exit}')"

	if [ -n "${PUBLISH_ID:-}" ]; then
		echo "[OK] publish id=$PUBLISH_ID"
	else
		echo "[WARN] cannot parse publish id from output"
		echo "[WARN] will use publish_inst_id from NAN-NDP-REQUEST event"
	fi

	run_cli nan_status || true
}

send_ndp_response()
{
	local peer_nmi="$1"
	local init_ndi="$2"
	local ndp_id="$3"
	local handle="$4"

	echo "[INFO] accept NDP request"
	echo "       peer_nmi=$peer_nmi"
	echo "       init_ndi=$init_ndi"
	echo "       ndp_id=$ndp_id"
	echo "       handle=$handle"
	echo "       ndi=$NDI_IF"

	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" "IFNAME=$NAN_IF" \
		nan_ndp_response accept \
		peer_nmi="$peer_nmi" \
		ndi="$NDI_IF" \
		handle="$handle" \
		init_ndi="$init_ndi" \
		ndp_id="$ndp_id"
}

start_event_responder()
{
	echo "[INFO] event responder started"
	echo "[INFO] waiting for NAN-NDP-REQUEST"
	echo "[INFO] event log=$EVENT_LOG"
	echo "[INFO] press Ctrl+C to stop and cleanup"

	sudo "$WPA_CLI" -g "$GLOBAL_CTRL" | tee "$EVENT_LOG" | \
	while IFS= read -r line; do
		echo "[EVT] $line"

		case "$line" in
		*NAN-NDP-REQUEST*peer_nmi=*)
			peer_nmi="$(echo "$line" | sed -n 's/.*peer_nmi=\([0-9a-fA-F:]*\).*/\1/p')"
			init_ndi="$(echo "$line" | sed -n 's/.*init_ndi=\([0-9a-fA-F:]*\).*/\1/p')"
			ndp_id="$(echo "$line" | sed -n 's/.*ndp_id=\([0-9]*\).*/\1/p')"
			handle="$(echo "$line" | sed -n 's/.*publish_inst_id=\([0-9]*\).*/\1/p')"

			if [ -z "$peer_nmi" ] || [ -z "$init_ndi" ] || [ -z "$ndp_id" ] || [ -z "$handle" ]; then
				echo "[WARN] failed to parse NAN-NDP-REQUEST:"
				echo "       $line"
				continue
			fi

			if send_ndp_response "$peer_nmi" "$init_ndi" "$ndp_id" "$handle"; then
				echo "[OK] nan_ndp_response sent"
			else
				echo "[ERR] nan_ndp_response failed"
				echo "[INFO] tail wpa_supplicant log:"
				tail -120 "$WPAS_LOG" || true
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

	echo "=== NAN publisher + NDP responder auto test ==="
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
	create_ndi_if
	configure_nan
	publish_service
	start_event_responder
}

main "$@"
