################################################################################
#
# libretro-beetle-wswan
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-beetle-wswan/, 2026-09-07),
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

LIBRETRO_BEETLE_WSWAN_VERSION = 4b01295838ea89e3f1355bbe4cb5cf98aa6108cd
LIBRETRO_BEETLE_WSWAN_SITE = $(call github,libretro,beetle-wswan-libretro,$(LIBRETRO_BEETLE_WSWAN_VERSION))
LIBRETRO_BEETLE_WSWAN_LICENSE = GPL-2.0
LIBRETRO_BEETLE_WSWAN_LICENSE_FILES = COPYING
LIBRETRO_BEETLE_WSWAN_DEPENDENCIES = retroarch

define LIBRETRO_BEETLE_WSWAN_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile platform="unix" \
		GIT_VERSION="-$(shell echo $(LIBRETRO_BEETLE_WSWAN_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_BEETLE_WSWAN_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/mednafen_wswan_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/mednafen_wswan_libretro.so
endef

$(eval $(generic-package))
