/*
 * NAN (Wi-Fi Aware) definitions
 * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 * Copyright (c) 2026, Intel Corporation
 *
 * This software may be distributed under the terms of the BSD license.
 * See README for more details.
 */

#ifndef NAN_DEFS_H
#define NAN_DEFS_H

#define NAN_TYPE_SDF 0x13
#define NAN_TYPE_NAF 0x18

/* See Section 9.4.1 */
enum nan_subtype {
	NAN_SUBTYPE_INVALID		        = 0,
	NAN_SUBTYPE_RANGING_REQUEST		= 1,
	NAN_SUBTYPE_RANGING_RESPONSE		= 2,
	NAN_SUBTYPE_RANGING_TERMINATION		= 3,
	NAN_SUBTYPE_RANGING_REPORT		= 4,
	NAN_SUBTYPE_DATA_PATH_REQUEST		= 5,
	NAN_SUBTYPE_DATA_PATH_RESPONSE		= 6,
	NAN_SUBTYPE_DATA_PATH_CONFIRM		= 7,
	NAN_SUBTYPE_DATA_PATH_KEY_INSTALL	= 8,
	NAN_SUBTYPE_DATA_PATH_TERMINATION	= 9,
	NAN_SUBTYPE_SCHEDULE_REQUEST		= 10,
	NAN_SUBTYPE_SCHEDULE_RESPONSE		= 11,
	NAN_SUBTYPE_SCHEDULE_CONFIRM		= 12,
	NAN_SUBTYPE_SCHEDULE_UPDATE_NOTIF	= 13,
};

enum nan_attr_id {
	NAN_ATTR_MASTER_INDICATION = 0x00,
	NAN_ATTR_CLUSTER = 0x01,
	NAN_ATTR_NAN_ATTR_SERVICE_ID_LIST = 0x02,
	NAN_ATTR_SDA = 0x03, /* Service Descriptor attribute */
	NAN_ATTR_CONN_CAPA = 0x04,
	NAN_ATTR_WLAN_INFRA = 0x05,
	NAN_ATTR_P2P_OPER = 0x06,
	NAN_ATTR_IBSS = 0x07,
	NAN_ATTR_MESH = 0x08,
	NAN_ATTR_FURTHER_NAN_SD = 0x09,
	NAN_ATTR_FURTHER_AVAIL_MAP = 0x0A,
	NAN_ATTR_COUNTRY_CODE = 0x0B,
	NAN_ATTR_RANGING = 0x0C,
	NAN_ATTR_CLUSTER_DISCOVERY = 0x0D,
	NAN_ATTR_SDEA = 0x0E, /* Service Descriptor Extension attribute */
	NAN_ATTR_DEVICE_CAPABILITY = 0x0F,
	NAN_ATTR_NDP = 0x10,
	NAN_ATTR_NAN_AVAILABILITY = 0x12,
	NAN_ATTR_NDC = 0x13,
	NAN_ATTR_NDL = 0x14,
	NAN_ATTR_NDL_QOS = 0x15,
	NAN_ATTR_UNALIGNED_SCHEDULE = 0x17,
	NAN_ATTR_RANGING_INFO = 0x1A,
	NAN_ATTR_RANGING_SETUP = 0x1B,
	NAN_ATTR_FTM_RANGING_REPORT = 0x1C,
	NAN_ATTR_ELEM_CONTAINER = 0x1D,
	NAN_ATTR_EXT_WLAN_INFRA = 0x1E,
	NAN_ATTR_EXT_P2P_OPER = 0x1F,
	NAN_ATTR_EXT_IBSS = 0x20,
	NAN_ATTR_EXT_MESH = 0x21,
	NAN_ATTR_CSIA = 0x22, /* Cipher Suite Info attribute */
	NAN_ATTR_SCIA = 0x23, /* Security Context Info attribute */
	NAN_ATTR_SHARED_KEY_DESCR = 0x24,
	NAN_ATTR_PUBLIC_AVAILABILITY = 0x27,
	NAN_ATTR_SUBSC_SERVICE_ID_LIST = 0x28,
	NAN_ATTR_NDP_EXT = 0x29,
	NAN_ATTR_DCEA = 0x2A, /* Device Capability Extension attribute */
	NAN_ATTR_NIRA = 0x2B, /* NAN Identity Resolution attribute */
	NAN_ATTR_BPBA = 0x2C, /* NAN Pairing Bootstrapping attribute */
	NAN_ATTR_S3 = 0x2D,
	NAN_ATTR_TPEA = 0x2E, /* Transmit Power Envelope attribute */
	NAN_ATTR_VENDOR_SPECIFIC = 0xDD,
};

/* See Table 43 */
enum nan_reason {
	NAN_REASON_RESERVED                 = 0,
	NAN_REASON_UNSPECIFIED_REASON       = 1,
	NAN_REASON_RESOURCE_LIMITATION      = 2,
	NAN_REASON_INVALID_PARAMETERS       = 3,
	NAN_REASON_FTM_PARAMETERS_INCAPABLE = 4,
	NAN_REASON_NO_MOVEMENT              = 5,
	NAN_REASON_INVALID_AVAILABILITY     = 6,
	NAN_REASON_IMMUTABLE_UNACCEPTABLE   = 7,
	NAN_REASON_SECURITY_POLICY          = 8,
	NAN_REASON_QOS_UNACCEPTABLE         = 9,
	NAN_REASON_NDP_REJECTED             = 10,
	NAN_REASON_NDL_UNACCEPTABLE         = 11,
	NAN_REASON_RANGING_SCHED_NOT_ACCEPT = 12,
	NAN_REASON_PAIR_BOOTSTRAP_REJECTED  = 13,
};

/* Service Descriptor attribute (SDA) */

/* Service Control field */
#define NAN_SRV_CTRL_TYPE_MASK                (BIT(0) | BIT(1))
#define NAN_SRV_CTRL_MATCHING_FILTER          BIT(2)
#define NAN_SRV_CTRL_RESP_FILTER              BIT(3)
#define NAN_SRV_CTRL_SRV_INFO                 BIT(4)
#define NAN_SRV_CTRL_DISCOVERY_RANGE_LIMITED  BIT(5)
#define NAN_SRV_CTRL_BINDING_BITMAP           BIT(6)

enum nan_service_control_type {
	NAN_SRV_CTRL_PUBLISH = 0,
	NAN_SRV_CTRL_SUBSCRIBE = 1,
	NAN_SRV_CTRL_FOLLOW_UP = 2,
};

/* Service Descriptor Extension attribute (SDEA) */

/* SDEA Control field */
#define NAN_SDEA_CTRL_FSD_REQ        BIT(0)
#define NAN_SDEA_CTRL_FSD_GAS        BIT(1)
#define NAN_SDEA_CTRL_DATA_PATH_REQ  BIT(2)
#define NAN_SDEA_CTRL_DATA_PATH_TYPE BIT(3)
#define NAN_SDEA_CTRL_QOS_REQ        BIT(5)
#define NAN_SDEA_CTRL_SECURITY_REQ   BIT(6)
#define NAN_SDEA_CTRL_RANGING_REQ    BIT(7)
#define NAN_SDEA_CTRL_RANGE_LIMIT    BIT(8)
#define NAN_SDEA_CTRL_SRV_UPD_INDIC  BIT(9)
#define NAN_SDEA_CTRL_GTK_REQ        BIT(10)

enum nan_service_protocol_type {
	NAN_SRV_PROTO_BONJOUR = 1,
	NAN_SRV_PROTO_GENERIC = 2,
	NAN_SRV_PROTO_CSA_MATTER = 3,
};

/* SRF Control field */
/* bit 0 = 0: Address Set is a sequence of MAC Addresses
 * bit 0 = 1: Address Set is a Bloom filter */
#define NAN_SRF_CTRL_BF 	BIT(0)
#define NAN_SRF_CTRL_INCLUDE 	BIT(1)

/* bit 2-3: Bloom Filter Index */
#define NAN_SRF_CTRL_BF_IDX_MSK (BIT(0) | BIT(1))
#define NAN_SRF_CTRL_BF_IDX_POS 2

#define NAN_ATTR_HDR_LEN 3
#define NAN_SERVICE_ID_LEN 6

#define NAN_USD_DEFAULT_FREQ 2437

/* MAP ID: See Table 79 (Device Capability) */
#define NAN_DEV_CAPA_MAP_ID_DONT_APPLY_ALL BIT(0)
#define NAN_DEV_CAPA_MAP_ID_POS            1
#define NAN_DEV_CAPA_MAP_ID_MASK          (BIT(1) | BIT(2) | BIT(3) \
					   BIT(4))

/* Supported bands: See Table 79 (Device Capability) */
#define NAN_DEV_CAPA_SBAND_SUB_1G BIT(1)
#define NAN_DEV_CAPA_SBAND_2G     BIT(2)
#define NAN_DEV_CAPA_SBAND_5G     BIT(4)
#define NAN_DEV_CAPA_SBAND_6G     BIT(7)

/* See Table 80 (Committed Discovery Window Information Field) */
#define NAN_CDW_INFO_2G_POS            0
#define NAN_CDW_INFO_2G_MASK           (BIT(0) | BIT(1) | BIT(2))
#define NAN_CDW_INFO_5G_POS            3
#define NAN_CDW_INFO_5G_MASK           (BIT(3) | BIT(4) | BIT(5))
#define NAN_CDW_INFO_2G_OVERRIDE_POS   6
#define NAN_CDW_INFO_2G_OVERRIDE_MASK  (BIT(6) | BIT(7) | BIT(8) | BIT(9))
#define NAN_CDW_INFO_5G_OVERRIDE_POS   10
#define NAN_CDW_INFO_5G_OVERRIDE_MASK  (BIT(10) | BIT(11) | BIT(12) | BIT(13))

/* See Table 81 (Operation Mode Field) */
#define NAN_DEV_CAPA_OP_MODE_PHY_MODE     (BIT(0) | BIT(4))
#define NAN_DEV_CAPA_OP_MODE_PHY_MODE_VHT BIT(0)
#define NAN_DEV_CAPA_OP_MODE_PHY_MODE_HE  BIT(4)
#define NAN_DEV_CAPA_OP_MODE_HE_VHT_80P80 BIT(1)
#define NAN_DEV_CAPA_OP_MODE_HE_VHT_160   BIT(2)

/* Antennas: See Table 79 (Device Capability) */
#define NAN_DEV_CAPA_TX_ANT_POS   0
#define NAN_DEV_CAPA_TX_ANT_MASK  0x0f
#define NAN_DEV_CAPA_RX_ANT_POS   4
#define NAN_DEV_CAPA_RX_ANT_MASK  0xf0

/* Capabilities: See Table 79 (Device Capability) */
#define NAN_DEV_CAPA_DFS_MASTER     BIT(0)
#define NAN_DEV_CAPA_EXT_KEY_ID     BIT(1)
#define NAN_DEV_CAPA_SIM_NDP_RX     BIT(2)
#define NAN_DEV_CAPA_NDPE_ATTR_SUPP BIT(3)
#define NAN_DEV_CAPA_S3             BIT(4)

/* Device Capability Attribute: See Table 79 (Device Capability) */
struct nan_device_capa {
	u8 map_id;
	le16 cdw_info;
	u8 supported_bands;
	u8 op_mode;
	u8 ant;
	le16 channel_switch_time;
	u8 capa;
} STRUCT_PACKED;

#define NAN_NDP_TYPE_POS    0
#define NAN_NDP_TYPE_MASK   (BIT(0) | BIT(1) | BIT(2) | BIT(3))
#define NAN_NDP_STATUS_POS  4
#define NAN_NDP_STATUS_MASK (BIT(4) | BIT(5) | BIT(6) | BIT(7))

/* NDP type: See Table 82 (NDP attribute format) */
enum nan_ndp_type {
	NAN_NDP_TYPE_REQUEST		= 0,
	NAN_NDP_TYPE_RESPONSE		= 1,
	NAN_NDP_TYPE_CONFIRM		= 2,
	NAN_NDP_TYPE_SECURITY_INSTALL	= 3,
	NAN_NDP_TYPE_TERMINATE		= 4,
};

/* NDP status: See Table 82 (NDP attribute format) */
enum nan_ndp_status {
	NAN_NDP_STATUS_CONTINUED = 0,
	NAN_NDP_STATUS_ACCEPTED  = 1,
	NAN_NDP_STATUS_REJECTED  = 2,
};

/* See Table 84 (NDP Control field) */
#define NAN_NDP_CTRL_CONFIRM_REQUIRED       BIT(0)
/* Bit position 1 is reserved in the spec */
#define NAN_NDP_CTRL_SECURITY_PRESENT       BIT(2)
#define NAN_NDP_CTRL_PUBLISH_ID_PRESENT     BIT(3)
#define NAN_NDP_CTRL_RESPONDER_NDI_PRESENT  BIT(4)
#define NAN_NDP_CTRL_SPEC_INFO_PRESENT      BIT(5)

/* NDP type: See Table 82 (NDP attribute format)
 * Note: the structure does not include the id and length.
 */
struct ieee80211_ndp {
	u8 dialog_token;
	u8 type_and_status;
	u8 reason_code;
	u8 initiator_ndi[ETH_ALEN];
	u8 ndp_id;
	u8 ndp_ctrl;

	/* followed by optional fields based on ndp_ctrl */
	u8 optional[0];
} STRUCT_PACKED;

/* See Table 97 (Time Bitmap Control field format) */
#define NAN_TIME_BM_CTRL_BIT_DURATION_POS  0
#define NAN_TIME_BM_CTRL_BIT_DURATION_MASK (BIT(0) | BIT(1) | BIT(2))
#define NAN_TIME_BM_CTRL_BIT_DURATION_16_TU   0
#define NAN_TIME_BM_CTRL_BIT_DURATION_32_TU   1
#define NAN_TIME_BM_CTRL_BIT_DURATION_64_TU   2
#define NAN_TIME_BM_CTRL_BIT_DURATION_128_TU  3

#define NAN_TIME_BM_CTRL_PERIOD_POS        3
#define NAN_TIME_BM_CTRL_PERIOD_MASK       (BIT(3) | BIT(4) | BIT(5))
#define NAN_TIME_BM_CTRL_PERIOD_NONE    0

#define NAN_TIME_BM_CTRL_START_OFFSET_POS  6
#define NAN_TIME_BM_CTRL_START_OFFSET_MASK (BIT(6) | BIT(7) | BIT(8) |  \
					    BIT(9) | BIT(10) | BIT(11) | \
					    BIT(12) | BIT(13) | BIT(14))

/* See Table 96 (Entry Control Filed for NAN Availability attribute) */
#define NAN_AVAIL_ENTRY_CTRL_TYPE_COMMITTED   BIT(0)
#define NAN_AVAIL_ENTRY_CTRL_TYPE_POTENTIAL   BIT(1)
#define NAN_AVAIL_ENTRY_CTRL_TYPE_COND        BIT(2)
#define NAN_AVAIL_ENTRY_CTRL_TYPE_MASK          \
	(NAN_AVAIL_ENTRY_CTRL_TYPE_COMMITTED  | \
	 NAN_AVAIL_ENTRY_CTRL_TYPE_POTENTIAL  | \
	 NAN_AVAIL_ENTRY_CTRL_TYPE_COND)

#define NAN_AVAIL_ENTRY_CTRL_USAGE_PREF_POS   3
#define NAN_AVAIL_ENTRY_CTRL_USAGE_PREF_MASK  (BIT(3) | BIT(4))
#define NAN_AVAIL_ENTRY_CTRL_UTIL_UNKNOWN     7
#define NAN_AVAIL_ENTRY_CTRL_UTIL_MAX         5
#define NAN_AVAIL_ENTRY_CTRL_UTIL_POS         5
#define NAN_AVAIL_ENTRY_CTRL_UTIL_MASK        (BIT(5) | BIT(6) | BIT(7))
#define NAN_AVAIL_ENTRY_CTRL_RX_NSS_POS       8
#define NAN_AVAIL_ENTRY_CTRL_RX_NSS_MASK      (BIT(8) | BIT(9) | BIT(10) | \
					       BIT(11))
#define NAN_AVAIL_ENTRY_CTRL_TBM_PRESENT      BIT(12)

/* See Table 99 (List of Band Entries) */
enum nan_band_entry {
	NAN_BAND_ENTRY_SUB_1G       = 1,
	NAN_BAND_ENTRY_2G           = 2,
	NAN_BAND_ENTRY_5G           = 4,
	NAN_BAND_ENTRY_6G           = 7,
};

/* See Table 100 (Channel Entry format for the NAN Availability attribute) */
struct nan_chan_entry {
	u8 op_class;
	le16 chan_bitmap;
	u8 pri_chan_bitmap;

	/* This field is optional. It is present only if
	 * NAN_BAND_CHAN_CTRL_NON_CONT_BW is set
	 */
	le16 aux_chan_bitmap;
} STRUCT_PACKED;

/*
 * Channel entry only contains the aux_chan_btm field for 80+80MHz operating
 * class. See Table 100.
 */
#define NAN_CHAN_ENRTY_MIN_LEN   4
#define NAN_CHAN_ENRTY_80P80_LEN 6

/*
 * See Table 98 (Band/Channel Entries List field format for the NAN Availability
 * attribute)
 */
#define NAN_BAND_CHAN_CTRL_TYPE             BIT(0)
#define NAN_BAND_CHAN_CTRL_NON_CONT_BW      BIT(1)
/* Bit positions 2 and 3 are reserved in the spec */
#define NAN_BAND_CHAN_CTRL_NUM_ENTRIES_POS  4
#define NAN_BAND_CHAN_CTRL_NUM_ENTRIES_MASK (BIT(4) | BIT(5) | BIT(6) | BIT(7))

/*
 * See Table 98 (Band/Channel Entries List field format for the NAN Availability
 * attribute).
 */
struct nan_band_chan_list {
	u8 ctrl;
	u8 entries[0];
} STRUCT_PACKED;

/*
 * See Table 95 (Availability Entry field format for the NAN Availability
 * attribute).
 */
struct nan_avail_ent {
	le16 len;
	le16 ctrl;

	/* followed by optional fields based on ctrl. Note that this also
	 * includes the inclusion of time bitmap control and length
	 */
	u8 optional[0];
} STRUCT_PACKED;

#define MIN_AVAIL_ENTRY_LEN 2

/*
 * See Table 95 (Availability Entry field format for the NAN Availability
 * attribute). This structure represents a time bitmap related fields in the NAN
 * Availability entry.
 */
struct nan_tbm {
	le16 ctrl;
	u8 len;
	u8 bitmap[0];
} STRUCT_PACKED;

/* See Table 94 (Attribute Control field format for the NAN Availability
 * attribute)
 */
#define NAN_AVAIL_CTRL_MAP_ID_POS             0
#define NAN_AVAIL_CTRL_MAP_ID_MASK            0xf
#define NAN_AVAIL_CTRL_COMMITTED_CHANGED      BIT(4)
#define NAN_AVAIL_CTRL_POTENTIAL_CHANGED      BIT(5)
#define NAN_AVAIL_CTRL_PUB_AVAIL_ATTR_CHANGED BIT(6)
#define NAN_AVAIL_CTRL_NDC_ATTR_CHANGED       BIT(7)

/* See Table 93 (NAN Availability attribute format). ID and length not
 * included
 */
struct nan_avail {
	u8 seq_id;
	le16 ctrl;

	/* followed by availability entry list */
	u8 optional[0];
} STRUCT_PACKED;

#define NAN_SCHED_ENTRY_MAP_MASK (BIT(0) | BIT(1) | BIT(2) | BIT(3))

/* See Table 104 (Schedule Entry format for the NDC attribute) */
struct nan_sched_entry {
	u8 map_id;
	le16 control;
	u8 len;
	u8 bm[0];
} STRUCT_PACKED;

/* See Table 103 (Attribute Control field format for the NDC attribute) */
#define NAN_NDC_CTRL_SELECTED BIT(0)

/* See Table 102 (NDC attribute format). ID and length not included */
struct ieee80211_ndc {
	u8 ndc_id[ETH_ALEN];
	u8 ctrl;
	u8 sched_entries[0];
} STRUCT_PACKED;

/* See Table 105 (NDL attribute format) */
#define NAN_NDL_TYPE_POS    0
#define NAN_NDL_TYPE_MASK   (BIT(0) | BIT(1) | BIT(2) | BIT(3))
#define NAN_NDL_STATUS_POS  4
#define NAN_NDL_STATUS_MASK (BIT(4) | BIT(5) | BIT(6) | BIT(7))

enum nan_ndl_type {
	NAN_NDL_TYPE_REQUEST  = 0,
	NAN_NDL_TYPE_RESPONSE = 1,
	NAN_NDL_TYPE_CONFIRM  = 2,
};

enum nan_ndl_status {
	NAN_NDL_STATUS_CONTINUED = 0,
	NAN_NDL_STATUS_ACCEPTED	 = 1,
	NAN_NDL_STATUS_REJECTED	 = 2,
};

/* See Table 107 (NDL Control field format) */
#define NAN_NDL_CTRL_PEER_ID_PRESENT          BIT(0)
#define NAN_NDL_CTRL_IMMUT_SCHED_PRESENT      BIT(1)
#define NAN_NDL_CTRL_NDC_ATTR_PRESENT         BIT(2)
#define NAN_NDL_CTRL_NDL_QOS_ATTR_PRESENT     BIT(3)
#define NAN_NDL_CTRL_MAX_IDLE_PERIOD_PRESENT  BIT(4)
#define NAN_NDL_CTRL_NDL_TYPE                 BIT(5)
#define NAN_NDL_CTRL_NDL_SETUP_REASON_POS     6
#define NAN_NDL_CTRL_NDL_SETUP_REASON_MASK    (BIT(6) | BIT(7))

#define NAN_NDL_CTRL_NDL_SETUP_REASON_NDP     0x0
#define NAN_NDL_CTRL_NDL_SETUP_REASON_FSD_GAS 0x1

/* See Table 105 (NDL attribute format) */
struct ieee80211_ndl {
	u8 dialog_token;
	u8 type_and_status;
	u8 reason_code;
	u8 ctrl;

	/* followed by optional fields based on ndl_ctrl */
	u8 optional[0];
} STRUCT_PACKED;

/* See Table 130 (Element Container attribute format) */
#define NAN_ELEMENT_CONTAINER_MAP_ID_VALID_POS  0
#define NAN_ELEMENT_CONTAINER_MAP_ID_VALID_MASK BIT(0)
#define NAN_ELEMENT_CONTAINER_MAP_ID_POS        1
#define NAN_ELEMENT_CONTAINER_MAP_ID_MASK       (BIT(1) | BIT(2) | BIT(3) |\
					         BIT(4))

struct ieee80211_elemc {
	u8 map_id;
	u8 variable[0];
} STRUCT_PACKED;

/* See Table 108 (NDL QoS attribute format) */
struct ieee80211_nan_qos {
	u8 min_slots;
	le16 max_latency;
} STRUCT_PACKED;

#define NAN_QOS_MIN_SLOTS_NO_PREF   0
#define NAN_QOS_MAX_LATENCY_NO_PREF 0xffff

#define NAN_AUTH_TOKEN_LEN 16
#define NAN_KEY_MIC_LEN    16
#define NAN_KEY_MIC_24_LEN 24

/* See Table 121 (Cipher Suite attribute field format) */
enum nan_cipher_suite_id {
	NAN_CS_NONE         = 0,
	NAN_CS_SK_CCM_128   = 1,
	NAN_CS_SK_GCM_256   = 2,
	NAN_CS_PK_2WDH_128  = 3,
	NAN_CS_PK_2WDH_256  = 4,
	NAN_CS_GTK_CCMP_128 = 5,
	NAN_CS_GTK_GCMP_256 = 6,
	NAN_CS_PK_PASN_128  = 7,
	NAN_CS_PK_PASN_256  = 8,
};

/* See Table 121 (Cipher Suite attribute field format) */
struct nan_cipher_suite {
	u8 csid;
	u8 instance_id;
} STRUCT_PACKED;

/* See Table 122 (Cipher Suite Information attribute field format) */
#define NAN_CS_INFO_CAPA_16_ND_TKSA_REPLAY_COUNTERS BIT(0)
#define NAN_CS_INFO_CAPA_GTK_SUPP_POS               1
#define NAN_CS_INFO_CAPA_GTK_SUPP_MASK              (BIT(1) | BIT(2))
#define NAN_CS_INFO_CAPA_GTK_SUPP_NONE              0
#define NAN_CS_INFO_CAPA_GTK_SUPP_NO_BIGTK          1
#define NAN_CS_INFO_CAPA_GTK_SUPP_ALL               2
#define NAN_CS_INFO_CAPA_16_REPLAY_COUNTERS         BIT(3)
#define NAN_CS_INFO_CAPA_IGTK_USE_NCS_BIP_256       BIT(4)

/* See Table 122 (Cipher Suite Information attribute field format). Id and
 * length not included
 */
struct nan_cipher_suite_info {
	u8 capab;
	u8 cs[0];
} STRUCT_PACKED;

/* See Table 123 (Security Context Identifier field format) */
enum nan_sec_ctx_type {
	NAN_SEC_CTX_TYPE_INVALID = 0,
	NAN_SEC_CTX_TYPE_PMKID = 1,
};

/* See Table 123 (Security Context Identifier field format) */
struct nan_sec_ctxt {
	le16 len;
	u8 scid;
	u8 instance_id;
	u8 ctxt[0];
} STRUCT_PACKED;

/* Only key descriptor type 2 is supported */
#define NAN_KEY_DESC 2

/* See Table 125 (NAN Shared Key Descriptor attribute field format) */
struct nan_shared_key {
	u8 publish_id;

	/*
	 * The format of the key is as defined in the IEEE80211 specification,
	 * starting with the 'descriptor type' field. See struct wpa_eapol_key.
	 */
	u8 key[0];
} STRUCT_PACKED;

#endif /* NAN_DEFS_H */
