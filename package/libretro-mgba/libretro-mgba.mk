################################################################################
#
# libretro-mgba
#
################################################################################
# Transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/libretro/libretro-mgba/, 2026-09-07),
# same version pin. The first core of this tree that is NOT the gambatte
# mould: mGBA is a full emulator project built with CMake, and the
# libretro core is one of its targets (BUILD_LIBRETRO=ON, SKIP_LIBRARY=ON
# so nothing but the core is installed).
#
# Everything that is a front end or a service is off: Qt, SDL, the CLI
# debugger, Discord, SQLite (their game database), Lua scripting, ELF and
# FFmpeg. BUILD_GLES2 is left on to match batocera, but it is INERT for
# this target: the libretro core never calls SET_HW_RENDER (grep the
# source), it is a software renderer, and the built .so links only libm,
# libz and libc -- no libGLESv2. Kept, and labelled, rather than removed:
# matching the reference costs nothing, believing the flag does something
# would cost a debugging session (M20 nearly did).
#
# Where we differ from batocera on purpose: they depend on libzip and
# libpng, neither of which exists in this rootfs, and adding two
# libraries for a core is a bad trade on an immutable image. USE_LIBZIP,
# USE_MINIZIP and USE_PNG are pinned OFF instead; zlib stays ON because
# it is already here (RetroArch links it). The cost is mGBA's own archive
# reading, which nothing uses: RetroArch extracts .zip itself into
# cache_directory before the core ever sees the file.
#
# The .so keeps its upstream name (M20 rule): the <core> word in
# es_systems.cfg is the prefix of the file on the target.

LIBRETRO_MGBA_VERSION = c65e8a3d4666b0ea68a01578232452f31b185332
LIBRETRO_MGBA_SITE = $(call github,mgba-emu,mgba,$(LIBRETRO_MGBA_VERSION))
LIBRETRO_MGBA_LICENSE = MPL-2.0
LIBRETRO_MGBA_LICENSE_FILES = LICENSE
LIBRETRO_MGBA_DEPENDENCIES = retroarch zlib

LIBRETRO_MGBA_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_LIBRETRO=ON \
	-DSKIP_LIBRARY=ON \
	-DBUILD_QT=OFF \
	-DBUILD_SDL=OFF \
	-DBUILD_GLES2=ON \
	-DBUILD_GLES3=OFF \
	-DBUILD_GL=OFF \
	-DUSE_ZLIB=ON \
	-DUSE_LIBZIP=OFF \
	-DUSE_MINIZIP=OFF \
	-DUSE_PNG=OFF \
	-DUSE_LZMA=OFF \
	-DUSE_FFMPEG=OFF \
	-DUSE_SQLITE3=OFF \
	-DUSE_EDITLINE=OFF \
	-DUSE_ELF=OFF \
	-DUSE_LUA=OFF \
	-DUSE_JSON_C=OFF \
	-DUSE_FREETYPE=OFF \
	-DUSE_EPOXY=OFF \
	-DUSE_DISCORD_RPC=OFF

# mGBA declares CMake in-source support, so Buildroot's builddir IS the
# source tree here (pkg-cmake.mk) and the core lands in $(@D) -- not in
# the $(@D)/buildroot-build an out-of-source CMake package would use.
# Build 1 of M20 paid this: the core linked, the install could not find it.
define LIBRETRO_MGBA_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/mgba_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/mgba_libretro.so
endef

$(eval $(cmake-package))
