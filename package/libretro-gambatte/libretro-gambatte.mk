################################################################################
#
# libretro-gambatte
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-gambatte/,
# 2026-09-03), same version pin. The mould for every libretro core that
# builds with a plain Makefile: `make -f Makefile platform=unix`, which in
# the core's Makefile.libretro only adds -fPIC/-shared -- the CPU flags
# (-mcpu=cortex-a35) come from TARGET_CFLAGS through TARGET_CONFIGURE_OPTS.
# (The libretro Makefiles also know a `classic_armv8_a35` platform: that is
# the 32-bit vendor-kernel RK3326 build, -marm; not ours.)
# GIT_VERSION is passed because the tarball has no .git for the Makefile
# to ask. Depends on retroarch for ordering and coherence only: a core
# links nothing but the libc/libstdc++.

LIBRETRO_GAMBATTE_VERSION = d9d6cd06382d1ced30de34d56d3609452323dab1
LIBRETRO_GAMBATTE_SITE = $(call github,libretro,gambatte-libretro,$(LIBRETRO_GAMBATTE_VERSION))
LIBRETRO_GAMBATTE_LICENSE = GPL-2.0
LIBRETRO_GAMBATTE_LICENSE_FILES = COPYING
LIBRETRO_GAMBATTE_DEPENDENCIES = retroarch

define LIBRETRO_GAMBATTE_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile platform="unix" \
		GIT_VERSION="-$(shell echo $(LIBRETRO_GAMBATTE_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_GAMBATTE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/gambatte_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/gambatte_libretro.so
endef

$(eval $(generic-package))
