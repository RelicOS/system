#!/usr/bin/env bash
# Runs after the target directory is finalized and before any filesystem image
# is generated. $1 is TARGET_DIR.
set -eu

# Drop the kernel modules.
#
# The upstream arm64 defconfig builds ~1300 modules: 71 MiB installed. This
# card needs none of them -- every driver on the boot path (dw_mmc-rockchip,
# mmc_block, ext4, 8250_dw, rk817, devtmpfs) is built into the kernel image.
# Since M10 the rootfs does run a hotplug agent (eudev, for input
# classification), but its module-loading feature is compiled out
# (BR2_PACKAGE_EUDEV_MODULE_LOADING unset), so nothing calls modprobe.
#
# Modules come back in the milestone that needs one (SARADC, panel), on purpose
# and with the device watching -- not as a 71 MiB side effect.
rm -rf "${1}/lib/modules"

# Mount points for the two writable partitions (M12): git does not track
# empty directories, so they are born here instead of in the overlay.
# S00storage mounts data (ext4, system state) and relic (FAT32, the user's
# partition) onto them, first thing in the rcS.
mkdir -p "${1}/data" "${1}/relic"

# ES autostart (M11): a "once" entry in the inittab. BusyBox init runs "once"
# entries only after every sysinit entry -- the whole rcS, S10udevd's
# `udevadm settle` included -- so the menu never races udevd for the input
# devices. Appending here (instead of shipping a full inittab in the overlay)
# preserves Buildroot's generation of the file: the getty line is sed'ed in by
# system.mk over the busybox package's inittab, and a frozen copy of ours
# would silently drift from the vendored tree. The grep guard makes this
# idempotent: TARGET_DIR survives between builds.
if ! grep -q relicos-menu "${1}/etc/inittab"; then
	printf '\n# RelicOS: start the menu (M11)\n::once:/usr/bin/relicos-menu\n' \
		>> "${1}/etc/inittab"
fi

# haveged must feed the crng BEFORE S10udevd blocks on getrandom (M10 measured
# a 7.7 s first-boot stall there: udevd waits for `crng init done`, and the
# settle above holds the whole rcS behind it). Buildroot installs the script
# as S21 -- after udevd, where it is useless for that. The guard keeps this
# idempotent; the check after it fails the build loudly if haveged ever
# disappears from the rootfs.
if [ -f "${1}/etc/init.d/S21haveged" ]; then
	mv "${1}/etc/init.d/S21haveged" "${1}/etc/init.d/S09haveged"
fi
[ -f "${1}/etc/init.d/S09haveged" ] || {
	echo "post-build: S09haveged missing" >&2; exit 1; }

# Boot splash, frame 2 (M15): the RelicOS logo that S15splash paints onto
# /dev/fb0 after udevd. Generated here from the PNG in board/r36s/splash so
# the artwork is versioned once, as a PNG, and the 900 KiB P6 PPM that
# BusyBox fbsplash needs never enters git. Frame 1 (the kernel logo) is the
# same script's "mark" mode, frozen into patches/linux/0003 -- see
# board/r36s/splash/README.md.
BOARD_DIR="$(dirname "$0")"
mkdir -p "${1}/usr/share/relicos"
python3 "${BOARD_DIR}/splash/make-splash.py" full \
	"${BOARD_DIR}/splash/relicos-splash-640x480.png" \
	"${1}/usr/share/relicos/splash.ppm"

# The clock floor (M16): the second this image was built, for S01clock to
# raise a never-set RTC to (the RK817's RTC resets to 2000-01-01, and the
# ES hides its clock for any year up to 2000). SOURCE_DATE_EPOCH wins when
# a reproducible build sets it. Rewritten every build on purpose: the floor
# should be the newest date the card knows about.
echo "${SOURCE_DATE_EPOCH:-$(date -u +%s)}" > "${1}/etc/relicos-build-epoch"

# The wall clock's zone (M16, the clock commit): /etc/localtime on the
# immutable rootfs cannot hold the user's choice, so it points into /data,
# where the seed (board/r36s/rootfs-overlay/usr/share/relicos/data/system/
# localtime) puts the BR2_TARGET_LOCALTIME default and relicos-timezone puts
# whatever the ES's TIME ZONE menu picks. Until S00storage mounts /data the
# link dangles and libc falls back to UTC, which is what the RTC holds.
ln -sfn /data/system/localtime "${1}/etc/localtime"
