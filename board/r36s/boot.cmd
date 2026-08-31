# RelicOS boot script. Compiled into boot.scr by mkimage -T script (see
# BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT in the defconfig) and run by our
# CONFIG_BOOTCOMMAND (board/r36s/uboot.fragment).
#
# Load addresses are U-Boot's own defaults for px30 boards
# (include/configs/px30_common.h): scriptaddr=0x00500000,
# pxefile_addr_r=0x00600000. Confirmed on the device 2026-08-30.
#
# hwid_adc is set by patch 0003 and is DECIMAL (env_set_ulong -> simple_itoa).
# Compare with "test" (decimal parsing), never "itest" (hex parsing: 166
# would silently become 0x166 = 358).

echo
echo "RelicOS boot script (M3)"

# Build identity, so the serial log says which card this is.
if load mmc 0:1 ${pxefile_addr_r} RELICOS.TXT; then
	env import -t ${pxefile_addr_r} ${filesize}
fi
echo "  build                 : ${relicos_build}"
echo "  board id (SARADC ch0) : ${hwid_adc}"

# --- Layer 2: ADC window -> device tree ---
# Arch-R's full map, for whoever adds a device:
#   60-110 go3 / 140-190 r36s / 450-495 gameforce-chi /
#   652-702 rgb10|go2-v11|rg351m (GPIO tie-break) / 831-881 go2 /
#   1000-1050 magicx-xu10
# Only the window we have measured (R36S: 166) gets an entry. "unknown" is
# deliberately noisy: it means the table needs a new row, not that boot broke.
setenv relicos_fdt "unknown"
if test ${hwid_adc} -ge 140 && test ${hwid_adc} -le 190; then
	setenv relicos_fdt "rk3326-r36s.dtb"
fi

# --- The root filesystem ---
# MBR partitions cannot carry labels, and the kernel does not understand
# root=LABEL= at all (block/early-lookup.c: "MSDOS partitions do not support
# labels!"). PARTUUID is the only way to name a partition without a device node:
# for MBR it is "<disk signature>-<partition number>", and our disk signature is
# pinned in genimage.cfg. Never /dev/mmcblkXpY: this board has two SD slots and
# U-Boot's numbering does not match the kernel's.
# Set before the relicos.env import so a card can be repointed in the field: if
# the PARTUUID is ever wrong, "relicos_root=..." in that file fixes the boot
# with a text editor instead of a reflash.
setenv relicos_root "PARTUUID=52454c43-02"

# --- Manual override: a text file on the card beats the table ---
# Applied AFTER the table so it wins. This is what fixes a device whose
# hardware does not match its board id (e.g. a swapped panel).
if load mmc 0:1 ${pxefile_addr_r} relicos.env; then
	env import -t ${pxefile_addr_r} ${filesize}
fi

echo "  device tree           : ${relicos_fdt}"
echo "  root                  : ${relicos_root}"
echo

# --- Kernel command line ---
# console=ttyS2: UART2 at 0xff160000 is this SoC's debug port; the odroid-go
# dtsi says stdout-path = "serial2:115200n8". earlycon prints before the
# regular console driver is up -- the difference between "the kernel died
# early" and "the kernel never started".
# uboot.hwid_adc carries what layer 1 measured into /proc/cmdline. Same name
# Arch-R uses, on purpose.
# rootwait: the SD card is enumerated asynchronously (~1.5 s on this unit in
# M4), so the kernel must wait for the block device instead of giving up.
# rootfstype=ext4: skip probing other filesystems, and make the log say plainly
# which driver mounted the root.
# console=tty1 comes FIRST and console=ttyS2 LAST, and the order is the whole
# point. The kernel prints to every console= on the line, but /dev/console --
# what the getty in /etc/inittab opens -- is the last one. So kernel messages
# appear on the screen (the observable this milestone is built around: garbled
# or rolling text says the video mode is wrong, in a way a penguin cannot) and
# the login prompt stays on the serial port, where it has been since M5.
setenv bootargs "console=tty1 console=ttyS2,115200n8 earlycon=uart8250,mmio32,0xff160000 uboot.hwid_adc=${hwid_adc} root=${relicos_root} rootwait rootfstype=ext4"

# A device tree we cannot name is a device tree we must not guess at. Stopping
# at the prompt is also the field escape hatch: putting "relicos_fdt=unknown"
# in relicos.env stops the boot without reflashing the card.
if test "${relicos_fdt}" = "unknown"; then
	echo "  no device tree for this board id - stopping at the prompt"
	exit
fi

# Addresses are U-Boot's px30 defaults (include/configs/px30_common.h):
# fdt_addr_r=0x01e00000, kernel_addr_r=0x02080000.
if load mmc 0:1 ${fdt_addr_r} ${relicos_fdt}; then
	if load mmc 0:1 ${kernel_addr_r} Image; then
		echo "  booting the kernel..."
		echo
		booti ${kernel_addr_r} - ${fdt_addr_r}
	fi
fi

echo "  kernel boot failed - back to the prompt"
