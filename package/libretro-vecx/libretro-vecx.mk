################################################################################
#
# libretro-vecx
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-vecx/, 2026-09-07),
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
# Out of the mould in one way: the Vectrex is a vector machine, and this
# core draws its lines on the GPU. GLES=1 + GL_LIB=-lGLESv2 point it at
# the Mesa/Panfrost GLES2 the M9 proved -- the same stack the frontend
# and the menu already render on. Without them the core builds its
# software rasteriser instead (HAS_GPU=0), which is the fallback if the
# device says the GPU path is wrong.

LIBRETRO_VECX_VERSION = 8f671cc9d737f2890c3ce19e177e2984dcae121f
LIBRETRO_VECX_SITE = $(call github,libretro,libretro-vecx,$(LIBRETRO_VECX_VERSION))
LIBRETRO_VECX_LICENSE = GPL-2.0+
LIBRETRO_VECX_LICENSE_FILES = LICENSE.md
LIBRETRO_VECX_DEPENDENCIES = retroarch

define LIBRETRO_VECX_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile.libretro platform="unix" \
		GLES=1 GL_LIB=-lGLESv2 \
		GIT_VERSION="-$(shell echo $(LIBRETRO_VECX_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_VECX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/vecx_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/vecx_libretro.so
endef

$(eval $(generic-package))
