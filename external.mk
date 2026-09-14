# Entry point for custom packages: every package/<name>/<name>.mk in this tree.
include $(sort $(wildcard $(BR2_EXTERNAL_RELICOS_PATH)/package/*/*.mk))

# Build-time secrets that never enter git (M22): the ScreenScraper developer
# login the ES's scraper needs (CMake -DSCREENSCRAPER_DEV_LOGIN; see
# package/emulationstation/emulationstation.mk and secrets.mk.example).
# Absent file, absent secrets: the image builds the same, the scraper just
# has no credentials to offer.
-include $(BR2_EXTERNAL_RELICOS_PATH)/secrets.mk
