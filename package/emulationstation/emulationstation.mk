################################################################################
#
# emulationstation
#
################################################################################
# batocera-emulationstation via the KNULLI fork (ADR 0005 lineage): same
# Buildroot base as us, and the fork targets exactly this class of handheld.
# Version pinned to the head of the `knulli` branch on 2026-08-31.
#
# Built STANDALONE -- no -DBATOCERA/-DKNULLI (M10 decision): paths resolve to
# the exe dir + $HOME/.emulationstation instead of Batocera's hardcoded
# /userdata tree. The runtime wiring (es_systems.cfg, symlinks, the dummy
# game) lives in board/r36s/rootfs-overlay/.
#
# Recipe transplanted from knulli-linux's knulli-emulationstation.mk, minus
# the KNULLI plumbing: no knulli-es-system (generates es_systems.cfg from
# 800 KB of YAML -- ours is six lines, written by hand), no host-gettext
# (vlc already drags it in; NLS is optional in the ES's CMake), no libmali
# (we render on mainline Panfrost), no sway/xorg/init hooks. Of their four
# patches only the display-mode fallback survives: the other three need
# Batocera infrastructure (one does not even compile against vanilla SDL2).

EMULATIONSTATION_VERSION = f7c5ae103815761ccd34bc55b021c6e150442c96
EMULATIONSTATION_SITE = https://github.com/knulli-cfw/batocera-emulationstation
EMULATIONSTATION_SITE_METHOD = git
# external/pugixml is a git submodule (USE_SYSTEM_PUGIXML defaults to OFF).
EMULATIONSTATION_GIT_SUBMODULES = YES
EMULATIONSTATION_LICENSE = MIT, Apache-2.0
EMULATIONSTATION_LICENSE_FILES = LICENSE.md
EMULATIONSTATION_DEPENDENCIES = \
	sdl2 sdl2_mixer vlc freeimage freetype alsa-lib libcurl rapidjson

# GLES2 is our renderer (Mali-G31 via Panfrost); everything else that the
# CMake can toggle is off: no CEC, no Kodi hooks, no PulseAudio (alsa only).
# POLICY_VERSION_MINIMUM: the vendored pugixml submodule declares a
# cmake_minimum_required older than 3.5, which Buildroot's modern host-cmake
# refuses outright; this is the workaround CMake itself suggests.
EMULATIONSTATION_CONF_OPTS = \
	-DGLES2=ON \
	-DCEC=OFF \
	-DDISABLE_KODI=ON \
	-DENABLE_PULSE=OFF \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5

# CMake's install() only ships the binary. The resources tree (fonts, svgs,
# shaders, splash) is found at runtime through the rootfs overlay's
# $HOME/.emulationstation/resources symlink pointing here.
define EMULATIONSTATION_INSTALL_RESOURCES
	mkdir -p $(TARGET_DIR)/usr/share/emulationstation
	cp -r $(@D)/resources $(TARGET_DIR)/usr/share/emulationstation/
endef
EMULATIONSTATION_POST_INSTALL_TARGET_HOOKS += EMULATIONSTATION_INSTALL_RESOURCES

$(eval $(cmake-package))
