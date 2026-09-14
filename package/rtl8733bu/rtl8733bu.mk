################################################################################
#
# rtl8733bu
#
################################################################################
# The radio (M22): the source of everything the RTL8733BU needs that the
# mainline kernel lacks. Nothing is compiled here -- the kernel extension
# linux/linux-ext-rtl8733bu.mk copies this package's directory into the
# kernel tree, and the kernel builds the driver (CONFIG_RTL8733BU=m since
# part 2: 8733bu.ko, kept by board/r36s/post-build.sh). What this package
# installs itself is the Bluetooth firmware, into /lib/firmware/rtl_bt/.
#
# The driver: Realtek's rtl8733BU v5.15.12-126, via wirenboard's clean-up
# and ROCKNIX's "Fix building on Linux 6.12" (3a706fef, 2025-01-04; the
# tree ROCKNIX shipped on 6.12 for the Miyoo Flip). Our two patches are
# in patches/rtl8733bu/: a platform block for the in-tree build, and the
# Kconfig dependency. The Wi-Fi firmware is a C array inside the driver
# (hal/rtl8733b/hal8733b_fw.c): no file, no request_firmware, no race.
#
# The Bluetooth firmware: rtl_bt/rtl8723fu_fw.bin + rtl8723fu_config.bin,
# the pair btrtl asks for once patches/linux/0005 teaches it the chip
# (the 8733BU's BT core identifies as an 8723 with hci_rev 0xf). Not in
# linux-firmware as of 20251011; ROCKNIX carries them in tree, wirenboard
# packages the same bytes for Debian. Pinned to one ROCKNIX commit and
# hashed, like any other download.
#
# Buildroot does NOT notice edited patches or a new version on its own:
# `make -C output rtl8733bu-dirclean linux-dirclean` after either.

RTL8733BU_VERSION = 3a706fef8d4ab4aa74524dd9176af789b2593261
RTL8733BU_SITE = $(call github,ROCKNIX,RTL8733BU,$(RTL8733BU_VERSION))
RTL8733BU_LICENSE = GPL-2.0
RTL8733BU_LICENSE_FILES = README.md

RTL8733BU_FIRMWARE_COMMIT = c65e7990903c55063b61fcd2fc32cdcb84918045
RTL8733BU_FIRMWARE_SITE = https://raw.githubusercontent.com/ROCKNIX/distribution/$(RTL8733BU_FIRMWARE_COMMIT)/projects/ROCKNIX/packages/linux-firmware/kernel-firmware/extra-firmware/rtl_bt
RTL8733BU_FIRMWARE_FILES = rtl8723fu_fw.bin rtl8723fu_config.bin
RTL8733BU_EXTRA_DOWNLOADS = $(addprefix $(RTL8733BU_FIRMWARE_SITE)/,$(RTL8733BU_FIRMWARE_FILES))

# The blobs land in the download directory ($(RTL8733BU_DL_DIR),
# dl/rtl8733bu/), not in the source tree; from there to the rootfs. btrtl
# asks for them by name when btusb (a module, loaded by udev after the
# rootfs is up) registers hci0 -- request_firmware reads /lib/firmware.
define RTL8733BU_INSTALL_TARGET_CMDS
	$(foreach f,$(RTL8733BU_FIRMWARE_FILES),\
		$(INSTALL) -D -m 0644 $(RTL8733BU_DL_DIR)/$(f) \
			$(TARGET_DIR)/lib/firmware/rtl_bt/$(f)$(sep))
endef
$(eval $(generic-package))
