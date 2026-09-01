################################################################################
#
# sdl2-diag
#
################################################################################
# The M10 observation rung between the M9 stack and the EmulationStation:
# proves SDL2's KMSDRM video and its udev-less joystick enumeration on the
# serial console, independently of the ES. In-tree source, small enough to be
# reviewed whole. SITE_METHOD=local rsyncs src/ on each build, but after
# editing the .c still run `make -C output sdl2-diag-rebuild` to be sure.

SDL2_DIAG_SITE = $(BR2_EXTERNAL_RELICOS_PATH)/package/sdl2-diag/src
SDL2_DIAG_SITE_METHOD = local
SDL2_DIAG_LICENSE = MIT
SDL2_DIAG_DEPENDENCIES = sdl2

define SDL2_DIAG_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $(@D)/sdl2-diag.c \
		`$(STAGING_DIR)/usr/bin/sdl2-config --cflags --libs` \
		-o $(@D)/sdl2-diag
endef

define SDL2_DIAG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/sdl2-diag $(TARGET_DIR)/usr/bin/sdl2-diag
endef

$(eval $(generic-package))
