# Thin wrapper over Buildroot. All state lives under output/ (gitignored).
#
# Trap to remember: Buildroot does NOT notice edits to files in this external
# tree (genimage.cfg, post-image.sh, ...). After editing one, force the
# affected package: make -C output <package>-rebuild (or -dirclean).

O ?= $(CURDIR)/output
BR = $(MAKE) -C $(CURDIR)/buildroot O=$(O) BR2_EXTERNAL=$(CURDIR)

.PHONY: r36s menuconfig savedefconfig

r36s:
	$(BR) relicos_r36s_defconfig
	$(BR)

menuconfig:
	$(BR) menuconfig

savedefconfig:
	$(BR) savedefconfig BR2_DEFCONFIG=$(CURDIR)/configs/relicos_r36s_defconfig
