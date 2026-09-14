################################################################################
#
# Linux kernel extension: the RTL8733BU driver and firmware, in tree (M22)
#
################################################################################
# Buildroot's mechanism for "patch the kernel with a package's contents"
# (linux/linux-ext-xenomai.mk is the in-tree mould): with
# BR2_LINUX_KERNEL_EXT_RTL8733BU set, the rtl8733bu package is built
# before the kernel is patched and this hook runs on the freshly extracted
# kernel source, before patches/linux/*.patch. Rerun by `make -C output
# linux-dirclean`, which is what any kernel-side change needs anyway.
#
# Two moves, both inside $(LINUX_DIR):
#  1. the driver directory becomes drivers/net/wireless/realtek/rtl8733bu;
#  2. the realtek Kconfig and Makefile learn about it -- the two lines
#     every BSP kernel that ships this driver carries (the Kconfig one
#     inside the WLAN_VENDOR_REALTEK block, so the option inherits the
#     vendor switch like its neighbours); guarded so a rerun on the same
#     tree adds them once.
# CONFIG_RTL8733BU (board/r36s/linux.fragment) then decides =y or =m; the
# kernel build does the rest. In M22 part 1 the extension also carried the
# Bluetooth firmware into the kernel source for CONFIG_EXTRA_FIRMWARE,
# because btusb was built in and probed the module before any rootfs;
# with btusb a module (part 2) the blobs are ordinary files in
# /lib/firmware, installed by the package itself.

LINUX_EXTENSIONS += rtl8733bu

RTL8733BU_KERNEL_SUBDIR = drivers/net/wireless/realtek

define RTL8733BU_PREPARE_KERNEL
	rm -rf $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/rtl8733bu
	mkdir -p $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/rtl8733bu
	cp -a $(RTL8733BU_DIR)/. $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/rtl8733bu/
	grep -q 'rtl8733bu/Kconfig' $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/Kconfig || \
		sed -i '/^endif # WLAN_VENDOR_REALTEK/i source "$(RTL8733BU_KERNEL_SUBDIR)/rtl8733bu/Kconfig"' \
			$(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/Kconfig
	grep -q 'rtl8733bu/' $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/Makefile || \
		echo 'obj-$$(CONFIG_RTL8733BU) += rtl8733bu/' \
			>> $(LINUX_DIR)/$(RTL8733BU_KERNEL_SUBDIR)/Makefile
endef
