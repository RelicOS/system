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

# --- Manual override: a text file on the card beats the table ---
# Applied AFTER the table so it wins. This is what fixes a device whose
# hardware does not match its board id (e.g. a swapped panel).
if load mmc 0:1 ${pxefile_addr_r} relicos.env; then
	env import -t ${pxefile_addr_r} ${filesize}
fi

echo "  device tree           : ${relicos_fdt}"
echo
# No kernel yet: falling off the end returns to the prompt. That is M3 success.
