################################################################################
#
# libretro-genesisplusgx
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-genesisplusgx/, 2026-09-07),
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
# The best weight-to-catalogue ratio of the milestone: this one .so is
# FOUR systems in es_systems.cfg -- megadrive, mastersystem, gamegear and
# sg1000 -- because Genesis Plus GX emulates the whole 8/16-bit Sega line
# in one core. (Sega CD is a fifth, and stays out of M20: it needs a BIOS
# the project cannot ship or verify.)

LIBRETRO_GENESISPLUSGX_VERSION = 27426f00aa68f9f358c86919e8a40985326fa05b
LIBRETRO_GENESISPLUSGX_SITE = $(call github,ekeeke,Genesis-Plus-GX,$(LIBRETRO_GENESISPLUSGX_VERSION))
LIBRETRO_GENESISPLUSGX_LICENSE = Non-commercial
LIBRETRO_GENESISPLUSGX_LICENSE_FILES = LICENSE.txt
LIBRETRO_GENESISPLUSGX_DEPENDENCIES = retroarch

define LIBRETRO_GENESISPLUSGX_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile.libretro platform="unix" \
		GIT_VERSION="-$(shell echo $(LIBRETRO_GENESISPLUSGX_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_GENESISPLUSGX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/genesis_plus_gx_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/genesis_plus_gx_libretro.so
endef

$(eval $(generic-package))
