################################################################################
#
# libretro-stella
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-stella/, 2026-09-07),
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
# The one difference from the mould: this is the full Stella emulator
# repository, and the libretro port lives in src/os/libretro -- that is
# the directory make runs in, and where the .so lands.

LIBRETRO_STELLA_VERSION = cd292f18b32a2887d1648d14f6d4abe29dd08e43
LIBRETRO_STELLA_SITE = $(call github,stella-emu,stella,$(LIBRETRO_STELLA_VERSION))
LIBRETRO_STELLA_LICENSE = GPL-2.0
LIBRETRO_STELLA_LICENSE_FILES = License.txt
LIBRETRO_STELLA_DEPENDENCIES = retroarch

define LIBRETRO_STELLA_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D)/src/os/libretro -f Makefile platform="unix" \
		GIT_VERSION="-$(shell echo $(LIBRETRO_STELLA_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_STELLA_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/src/os/libretro/stella_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/stella_libretro.so
endef

$(eval $(generic-package))
