################################################################################
#
# libretro-picodrive
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-picodrive/,
# 2026-09-07), same version pin. The only core of M20 fetched from git
# rather than a tarball: PicoDrive keeps parts of itself in submodules
# (platform/libpicofe among them), and a GitHub archive of the commit
# would arrive without them. GIT_SUBMODULES=YES is what makes the
# download complete, and why this package has no .hash file -- a tarball
# Buildroot assembles from a git tree is not the byte-identical artifact
# a hash is meant to pin. The commit id is the pin.
#
# platform="aarch64" (not "unix"): the Makefile has an explicit aarch64
# branch, and picking it is what keeps the ARM32-only assembly out of the
# build. That also answers the step batocera runs before the core --
# `make -C cpu/cyclone` -- which we do NOT run: Cyclone is a 68000
# recompiler written in 32-bit ARM assembly, and the Makefile's own
# use_cyclone is 0 for anything that is not ARCH=arm. If a link ever
# asks for a Cyclone object, that decision is what to revisit.
#
# -j1 is batocera's, kept: the generated-source steps in this Makefile
# are not parallel-safe. The -Wno-error is theirs too, for a core that
# still writes 1990s-style pointer casts.

LIBRETRO_PICODRIVE_VERSION = 733c711a477a642fd2006d5a7a581b2790ec36b4
LIBRETRO_PICODRIVE_SITE = https://github.com/libretro/picodrive.git
LIBRETRO_PICODRIVE_SITE_METHOD = git
LIBRETRO_PICODRIVE_GIT_SUBMODULES = YES
LIBRETRO_PICODRIVE_LICENSE = MAME
LIBRETRO_PICODRIVE_LICENSE_FILES = COPYING
LIBRETRO_PICODRIVE_DEPENDENCIES = retroarch

LIBRETRO_PICODRIVE_CFLAGS = $(TARGET_CFLAGS) \
	-Wno-error=incompatible-pointer-types

define LIBRETRO_PICODRIVE_BUILD_CMDS
	cd $(@D) && $(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(LIBRETRO_PICODRIVE_CFLAGS)" \
		$(MAKE) -j1 CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		-C $(@D) -f Makefile.libretro platform="aarch64" \
		GIT_VERSION="$(shell echo $(LIBRETRO_PICODRIVE_VERSION) | cut -c 1-7)"
endef

define LIBRETRO_PICODRIVE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/picodrive_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/picodrive_libretro.so
endef

$(eval $(generic-package))
