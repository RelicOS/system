# Entry point for custom packages: every package/<name>/<name>.mk in this tree.
include $(sort $(wildcard $(BR2_EXTERNAL_RELICOS_PATH)/package/*/*.mk))
