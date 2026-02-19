/*
 * Wi-Fi Aware - NAN module
 * Copyright (C) 2025 Intel Corporation
 *
 * This software may be distributed under the terms of the BSD license.
 * See README for more details.
 */

#ifndef NAN_H
#define NAN_H

#include "common/nan_defs.h"

struct nan_cluster_config;
enum nan_reason;

/*
 * struct nan_device_capabilities - NAN device capabilities.
 *
 * @cdw_info: Committed DW information
 * @supported_bands: Supported bands
 * @op_mode: Operation mode
 * @n_antennas: Number of antennas
 * @channel_switch_time: Maximal channel switch time
 * @capa: Device capabilities
 */
struct nan_device_capabilities {
	u16 cdw_info;
	u8 supported_bands;
	u8 op_mode;
	u8 n_antennas;
	u16 channel_switch_time;
	u8 capa;
};

/**
 * struct nan_qos - NAN QoS requirements
 *
 * @min_slots: Minimal number of slots.
 * @max_latency: Maximum allowed NAN slots between every two non-contiguous
 *     NAN Data Link (NDL) Common Resource Blocks (CRB)
 */
struct nan_qos {
	u8 min_slots;
	u16 max_latency;
};

/*
 * enum nan_ndp_action - NDP action
 *
 * @NAN_NDP_ACTION_REQ: Request NDP establishment.
 * @NAN_NDP_ACTION_RESP: Response to NDP establishment request.
 * @NAN_NDP_ACTION_CONF: Confirm NDP establishment.
 * @NAN_NDP_ACTION_TERM: Request NDP termination.
 */
enum nan_ndp_action {
	NAN_NDP_ACTION_REQ = 0,
	NAN_NDP_ACTION_RESP,
	NAN_NDP_ACTION_CONF,
	NAN_NDP_ACTION_TERM,
};

/**
 * struct nan_ndp_id - Unique identifier of an NDP
 *
 * @peer_nmi: peer NAN Management Interface (NMI)
 * @init_ndi: initiator NAN Data Interface (NDI)
 * @id: NDP identifier
 */
struct nan_ndp_id {
	u8 peer_nmi[ETH_ALEN];
	u8 init_ndi[ETH_ALEN];
	u8 id;
};

/*
 * struct nan_ndp_params - Holds the ndp parameters for setting up or
 * terminating an NDP.
 *
 * @type: The request type. See &enum nan_ndp_action
 * @ndp_id: The NDP identifier
 * @qos: The NDP QoS parameters. In case there is no requirement for
 *     max_latency, max_latency should be set to NAN_QOS_MAX_LATENCY_NO_PREF.
 *     Should be set only with NAN_NDP_ACTION_REQ and NAN_NDP_ACTION_RESP.
 *     Ignored for other types.
 * @ssi: Service specific information. Should be set only with
 *     NAN_NDP_ACTION_REQ and NAN_NDP_ACTION_RESP. Ignored for other types.
 * @ssi_len: Service specific information length
 * @publish_inst_id: Identifier for the instance of the Publisher function
 *     associated with the data path setup request.
 * @service_id: Service identifier of the service associated with the data path
 *     setup request.
 * @resp_ndi: In case of successful response, the responder's NDI. In case of
 *     response to a counter proposal, the initiator's NDI (the one used with
 *     NAN_NDP_ACTION_REQ).
 * @status: Response status.
 * @reason_code: In case of rejected response, the rejection reason.
 */
struct nan_ndp_params {
	enum nan_ndp_action type;

	struct nan_ndp_id ndp_id;
	struct nan_qos qos;
	const u8 *ssi;
	u16 ssi_len;

	union {
		struct nan_ndp_setup_req {
			u8 publish_inst_id;
			u8 service_id[NAN_SERVICE_ID_LEN];
		} req;

		/*
		 * Used with both NAN_NDP_ACTION_RESP (as a response to an NDP
		 * request) and NAN_NDP_ACTION_CONF (as a response to an NDP
		 * response with a counter).
		 * */
		struct nan_ndp_setup_resp {
			u8 resp_ndi[ETH_ALEN];
			u8 status;
			u8 reason_code;
		} resp;
	} u;
};

/*
 * struct nan_ndp_connection_params - Parameters for NDP connection
 *
 * @ndp_id: NDP identifier
 * @peer_ndi: peer NDI MAC address
 * @local_ndi: local NDI MAC address
 * @ssi: service specific information
 * @ssi_len: service specific information length
 */
struct nan_ndp_connection_params {
	struct nan_ndp_id ndp_id;
	const u8 *peer_ndi;
	const u8 *local_ndi;
	const u8 *ssi;
	size_t ssi_len;
};

/*
 * struct nan_ndp_action_notif_params - Parameters for NDP action notification
 *
 * @ndp_id: NDP identifier
 * @is_request: Whether the data is associated with an NDP request frame (true)
 *     or with an NDP response (false).
 * @ndp_status: NDP status
 * @ndl_status: NDL status
 * @publish_inst_id: identifier for the publish instance function
 * @ssi: service specific information
 * @ssi_len: service specific information length
 */
struct nan_ndp_action_notif_params {
	struct nan_ndp_id ndp_id;
	bool is_request;

	enum nan_ndp_status ndp_status;
	enum nan_ndl_status ndl_status;

	u8 publish_inst_id;
	const u8 *ssi;
	size_t ssi_len;
};

struct nan_config {
	void *cb_ctx;

	struct nan_device_capabilities dev_capa;

	/**
	 * start - Start NAN
	 * @ctx: Callback context from cb_ctx
	 * @config: NAN cluster configuration
	 */
	int (*start)(void *ctx, const struct nan_cluster_config *config);

	/**
	 * stop - Stop NAN
	 * @ctx: Callback context from cb_ctx
	 */
	void (*stop)(void *ctx);

	/**
	 * update_config - Update NAN configuration
	 * @ctx: Callback context from cb_ctx
	 * @config: NAN cluster configuration
	 */
	int (*update_config)(void *ctx,
			     const struct nan_cluster_config *config);

	/**
	 * ndp_action_notif - Notify NDP action is required
	 *
	 * @ctx: Callback context from cb_ctx
	 * @params: NDP action notification parameters
	 *
	 * A notification sent when an NDP establishment frame is received, and
	 * upper layer input is required to continue the flow.
	 */
	void (*ndp_action_notif)(void *ctx,
				 struct nan_ndp_action_notif_params *params);

	/**
	 * ndp_connected - Notify that NDP was successfully connected
	 *
	 * @ctx: Callback context from cb_ctx
	 * @params: NDP connection parameters
	 */
	void (*ndp_connected)(void *ctx,
			      struct nan_ndp_connection_params *params);

	/**
	 * ndp_disconnected - Notify that NDP was disconnected.
	 *
	 * @ctx: Callback context from cb_ctx
	 * @ndp_id: NDP identifier
	 * @local_ndi: Local NDI MAC address
	 * @peer_ndi: Peer NDI MAC address
	 * @reason: Disconnection reason
	 *
	 * This callback notifies that an NDP has been disconnected. It can be
	 * called both during NDP establishment (indicating failure) or after
	 * successful establishment (indicating termination).
	 */
	void (*ndp_disconnected)(void *ctx, struct nan_ndp_id *ndp_id,
				 const u8 *local_ndi, const u8 *peer_ndi,
				 enum nan_reason reason);
};

struct nan_data * nan_init(const struct nan_config *cfg);
void nan_deinit(struct nan_data *nan);
int nan_start(struct nan_data *nan, const struct nan_cluster_config *config);
int nan_update_config(struct nan_data *nan,
		      const struct nan_cluster_config *config);
void nan_stop(struct nan_data *nan);
void nan_flush(struct nan_data *nan);

int nan_add_peer(struct nan_data *nan, const u8 *addr,
		 const u8 *device_attrs, size_t device_attrs_len);

bool nan_publish_instance_id_valid(struct nan_data *nan, u8 instance_id,
				   u8 *service_id);

#endif /* NAN_H */
