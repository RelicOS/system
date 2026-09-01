################################################################################
#
# es-theme-carbon
#
################################################################################
# The classic Batocera default theme: light, designed for 4:3/480p -- the
# RG351-generation 640x480 panels, i.e. exactly this glass. Same commit the
# batocera.linux recipe pins (their master, 2026-08-31). Measured working
# tree: ~179 MiB / 2273 files -- the single largest new rootfs item of M10;
# trimming unused-system art is a seed, with this as the baseline.

ES_THEME_CARBON_VERSION = b921e1734d88d6bc7b9e8cb97dd8f8b91ba2058a
ES_THEME_CARBON_SITE = $(call github,fabricecaruso,es-theme-carbon,$(ES_THEME_CARBON_VERSION))
# The repository declares no license file (checked 2026-08-31); the batocera
# recipe ships it without one too. Revisit before any RelicOS release.
ES_THEME_CARBON_LICENSE = unknown (no license file upstream)

define ES_THEME_CARBON_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/emulationstation/themes/es-theme-carbon
	cp -r $(@D)/* $(TARGET_DIR)/usr/share/emulationstation/themes/es-theme-carbon
endef

$(eval $(generic-package))
