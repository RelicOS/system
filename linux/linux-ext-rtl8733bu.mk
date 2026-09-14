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
# Three moves, all inside $(LINUX_DIR):
#  1. the driver directory becomes drivers/net/wireless/realtek/rtl8733bu;
#  2. the realtek Kconfig and Makefile learn about it -- the two lines
#     every BSP kernel that ships this driver carries (the Kconfig one
#     inside the WLAN_VENDOR_REALTEK block, so the option inherits the
#     vendor switch like its neighbours); guarded so a rerun on the same
#     tree adds them once;
#  3. the Bluetooth firmware goes from the package's download directory
#     (the extension runs when the package is only *patched*, so nothing
#     built by it exists yet) to firmware/rtl_bt/, which is where
#     CONFIG_EXTRA_FIRMWARE_DIR="firmware" (board/r36s/linux.fragment)
#     points: a path relative to the kernel source, so the fragment needs
#     no absolute path into this tree. Built into the Image, the blobs
#     are there when btusb probes the module at ~2 s, long before any
#     rootfs -- the race KNULLI hit with btusb=y and files on the rootfs.

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
	mkdir -p $(LINUX_DIR)/firmware/rtl_bt
	$(foreach f,$(RTL8733BU_FIRMWARE_FILES),\
		cp $(RTL8733BU_DL_DIR)/$(f) $(LINUX_DIR)/firmware/rtl_bt/$(f)$(sep))
endef
