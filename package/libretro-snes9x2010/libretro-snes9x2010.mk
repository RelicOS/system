################################################################################
#
# libretro-snes9x2010
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-snes9x-next/, 2026-09-07),
# same version pin, in the M14 mould of libretro-gambatte: the core's own
# Makefile with platform="unix", which only adds -fPIC/-shared -- the CPU
# flags (-mcpu=cortex-a35) keep coming from TARGET_CFLAGS through
# TARGET_CONFIGURE_OPTS. GIT_VERSION is passed because the tarball has no
# .git for the Makefile to ask. Depends on retroarch for ordering and
# coherence only: a core links nothing but the libc/libstdc++.
#
# The .so keeps its UPSTREAM name (batocera renames some of theirs for
# their configgen). That is the M20 rule: the <core> word in
# es_systems.cfg is always the prefix of the file on the target, so
# relicos-launch can stay ${core}_libretro.so with no translation table.
#
# snes9x2010 is the 2010 fork of Snes9x kept for weak CPUs: the frontend
# calls it snes9x_next, upstream calls the file snes9x2010, and we keep
# the file's name. Current snes9x is the accuracy option and the known
# A/B for this system -- it is NOT a second core in this milestone (one
# core per console, M20), it is the seed if a game misbehaves.

LIBRETRO_SNES9X2010_VERSION = 7db129b1ecdccb38cb4d7184bcbed39beed79656
LIBRETRO_SNES9X2010_SITE = $(call github,libretro,snes9x2010,$(LIBRETRO_SNES9X2010_VERSION))
LIBRETRO_SNES9X2010_LICENSE = Non-commercial
LIBRETRO_SNES9X2010_LICENSE_FILES = LICENSE.txt
LIBRETRO_SNES9X2010_DEPENDENCIES = retroarch

define LIBRETRO_SNES9X2010_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile.libretro platform="unix" \
		GIT_VERSION="-$(shell echo $(LIBRETRO_SNES9X2010_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_SNES9X2010_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/snes9x2010_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/snes9x2010_libretro.so
endef

$(eval $(generic-package))
