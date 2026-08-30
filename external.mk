# Entry point for custom packages. Empty glob today: no custom packages yet.
include $(sort $(wildcard $(BR2_EXTERNAL_RELICOS_PATH)/package/*/*.mk))
