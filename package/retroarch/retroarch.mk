################################################################################
#
# retroarch
#
################################################################################
# The libretro frontend, transplanted from batocera.linux master
# (package/batocera/emulators/retroarch/retroarch/, 2026-09-03) in the M10
# mould: same version pin, same shape (qb configure is not autotools, so
# the three steps are spelled out), minus everything that is Batocera:
# no XMB/Ozone (their retroarch-assets + noto/dejavu fonts are ~100 MiB;
# RGUI has a built-in bitmap font and needs nothing), no networking
# (netplay/cheevos/updater/translate -- the device has no network), no
# ffmpeg (recording), no vulkan/x11/wayland, no --enable-odroidgo2 (their
# RK3326 flag turns on a vendor RGA video driver; we render through
# mainline Panfrost), no --enable-neon (an ARM32 flag: -mfpu=neon -marm,
# rejected by the aarch64 gcc), no video/DSP filter plugins.
#
# libretrodb stays ON: at this commit input/bsv/bsvmovie.c and the manual
# content-scan task call rmsgpack_*/task_push_manual_content_scan without
# a HAVE_LIBRETRODB guard, so --disable-libretrodb fails at link (M14
# build 2). A few hundred KB of database code nothing here uses.
#
# Principle for the flag list: qb turns every `auto` on when it finds the
# library in staging (ffmpeg, sdl2, freetype, udev, alsa are all there),
# so every auto that could flip is pinned explicitly, on or off. The
# configure summary in the build log is the first artifact check.
#
# sdl2 stays ON on purpose: it costs one NEEDED entry for a library the
# rootfs already carries, and buys three runtime A/Bs without a rebuild
# (video_driver / input_joypad_driver / audio_driver = "sdl2" -- the
# KMSDRM path the M10 menu proved). "Swap the observable, not the bench."

RETROARCH_VERSION = 4b74434a30c534c763b60ba4cc16f6a94a611c5f
RETROARCH_SITE = $(call github,libretro,RetroArch,$(RETROARCH_VERSION))
RETROARCH_LICENSE = GPL-3.0+
RETROARCH_LICENSE_FILES = COPYING
RETROARCH_DEPENDENCIES = host-pkgconf libdrm mesa3d eudev alsa-lib zlib \
	freetype sdl2

RETROARCH_CONF_OPTS = \
	--prefix=/usr \
	--disable-neon \
	--enable-threads --enable-dynamic \
	--enable-udev --enable-alsa \
	--enable-kms --enable-egl --enable-opengles \
	--disable-opengl --disable-opengles3 --disable-opengl_core --disable-opengl1 \
	--enable-glsl --disable-slang --disable-glslang --disable-builtinglslang \
	--disable-spirv_cross --disable-cg --disable-vg \
	--enable-sdl2 --disable-sdl \
	--disable-x11 --disable-wayland --disable-vulkan \
	--enable-rgui --disable-materialui --disable-xmb --disable-ozone \
	--enable-freetype \
	--enable-zlib --disable-builtinzlib --disable-7zip --disable-chd \
	--disable-networking --disable-ssl --disable-cheevos --disable-discord \
	--disable-translate --disable-online_updater --disable-update_cores \
	--disable-update_assets --disable-update_core_info \
	--disable-qt --disable-cdrom --disable-ffmpeg --disable-mpv --disable-ssa \
	--disable-flac --disable-builtinflac \
	--disable-pulse --disable-pipewire --disable-jack --disable-oss \
	--disable-tinyalsa --disable-roar --disable-rsound --disable-audioio \
	--disable-libusb --disable-hid --disable-v4l2 --disable-parport \
	--disable-blissbox --disable-videoprocessor --disable-videocore \
	--disable-sixel --disable-crtswitchres --disable-systemd --disable-xdelta \
	--disable-video_filter --disable-dsp_filter \
	--disable-imageviewer --disable-langextra \
	--disable-accessibility --disable-audiomixer --disable-overlay \
	--disable-microphone --disable-test_drivers

# No X11 on this rootfs: Mesa's EGL headers must not pull Xlib types.
RETROARCH_CFLAGS = $(TARGET_CFLAGS) -DEGL_NO_X11 -DMESA_EGL_NO_X11_HEADERS=1

# qb reads CC/CXX/CFLAGS/LDFLAGS from the environment and finds pkg-config
# through PKG_CONF_PATH (it does not read PKG_CONFIG). CROSS_COMPILE must
# be non-empty: with it empty, qb/config.libs.sh adds -L/usr/lib64 of the
# BUILD HOST ("there are still broken 64-bit Linux distros out there"),
# which Buildroot's toolchain wrapper refuses as an unsafe path -- build 1
# of M14 died there. -lc: qb's link tests otherwise miss libc symbols with
# our LDFLAGS (batocera carries it too).
define RETROARCH_CONFIGURE_CMDS
	(cd $(@D); rm -rf config.cache; \
		$(TARGET_CONFIGURE_OPTS) \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		CFLAGS="$(RETROARCH_CFLAGS)" \
		CXXFLAGS="$(RETROARCH_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) -lc" \
		PKG_CONF_PATH="$(PKG_CONFIG_HOST_BINARY)" \
		./configure $(RETROARCH_CONF_OPTS) \
	)
endef

define RETROARCH_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		LD="$(TARGET_LD)" -C $(@D)
endef

# `make install` also drops the desktop entry, metainfo, man page,
# pixmaps, an /etc/retroarch.cfg sample and -- unconditionally -- the
# glui/xmb/ozone assets under /usr/share/retroarch. None of it is read on
# this device (configuration comes from --config/--appendconfig, the menu
# is RGUI), and the assets alone would eat the M14 rootfs budget.
define RETROARCH_INSTALL_TARGET_CMDS
	$(MAKE) CXX="$(TARGET_CXX)" -C $(@D) DESTDIR=$(TARGET_DIR) install
	rm -rf $(TARGET_DIR)/usr/share/retroarch \
		$(TARGET_DIR)/usr/share/applications/*etro*rch* \
		$(TARGET_DIR)/usr/share/metainfo/*etro*rch* \
		$(TARGET_DIR)/usr/share/pixmaps/*etro*rch* \
		$(TARGET_DIR)/usr/share/man/man6/retroarch* \
		$(TARGET_DIR)/usr/share/doc/retroarch \
		$(TARGET_DIR)/etc/retroarch.cfg
endef

$(eval $(generic-package))
