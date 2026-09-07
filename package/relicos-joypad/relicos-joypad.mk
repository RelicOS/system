################################################################################
#
# relicos-joypad
#
################################################################################
# The M14 input fusion daemon: reads gpio-keys and adc-joystick, emits one
# uinput gamepad (see src/relicos-joypad.c for the contract, and ADR 0012
# for why a userspace fuser instead of an out-of-tree joypad driver).
# In-tree source, small enough to be reviewed whole -- the sdl2-diag mould.
# SITE_METHOD=local rsyncs src/ on each build, but it does NOT notice an
# edited .c on its own (M13 paid this: build 4 shipped a stale daemon):
# after editing, run `make -C output relicos-joypad-rebuild`.

RELICOS_JOYPAD_SITE = $(BR2_EXTERNAL_RELICOS_PATH)/package/relicos-joypad/src
RELICOS_JOYPAD_SITE_METHOD = local
RELICOS_JOYPAD_LICENSE = MIT
# alsa-lib: the volume keys drive the codec's "Master" control (M17).
RELICOS_JOYPAD_DEPENDENCIES = alsa-lib

define RELICOS_JOYPAD_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -Wall -Wextra \
		$(@D)/relicos-joypad.c -o $(@D)/relicos-joypad -lasound
endef

define RELICOS_JOYPAD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/relicos-joypad \
		$(TARGET_DIR)/usr/bin/relicos-joypad
endef

$(eval $(generic-package))
