#!/usr/bin/env bash
# Runs after the target directory is finalized and before any filesystem image
# is generated. $1 is TARGET_DIR.
set -eu

# Drop the kernel modules.
#
# The upstream arm64 defconfig builds ~1300 modules: 71 MiB installed, which is
# 95% of this root filesystem. This milestone needs none of them -- every driver
# on the boot path (dw_mmc-rockchip, mmc_block, ext4, 8250_dw, rk817, devtmpfs)
# is built into the kernel image. Nothing here would load them either: device
# nodes come from devtmpfs and there is no mdev/udev hotplug agent to call
# modprobe.
#
# Modules come back in the milestone that needs one (SARADC, panel), on purpose
# and with the device watching -- not as a 71 MiB side effect.
rm -rf "${1}/lib/modules"
