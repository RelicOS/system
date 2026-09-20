#!/usr/bin/env bash
# Runs after the target directory is finalized and before any filesystem image
# is generated. $1 is TARGET_DIR.
set -eu

# The kernel modules: keep ours, drop the defconfig's (M5, rewritten in M22).
#
# The upstream arm64 defconfig builds ~1300 modules, 71 MiB installed, and
# from M5 to M22 part 1 this script deleted the directory whole: every
# driver the card needed was built in, nothing loaded modules, so a =m was
# a driver that never ran. M22 part 2 rewrote the rule (Tiago, 2026-09-10):
# =y for what must exist before the rootfs or is a fixed part of every
# unit, =m for what is peripheral or optional -- the radio is the first.
# So MODULES_KEEP lists the modules this image wants, the closure of their
# dependencies is computed from the modules.dep that Buildroot's depmod
# (a target-finalize hook, run before this script) already wrote, and
# everything else goes. depmod runs again at the end, so modules.alias
# names only what is on the card: udev's coldplug (eudev with module
# loading, BR2_PACKAGE_EUDEV_MODULE_LOADING) loads by MODALIAS and never
# asks for a file that is not there. A wanted module that is missing fails
# the build loudly, like S09haveged below.
#
# Trimming the defconfig itself so the 1300 are never built (a
# config-slim milestone) is a seed; this is the cheap step.
MODULES_KEEP="8733bu btusb"

MODDIR="$(echo "${1}"/lib/modules/*)"
if [ ! -d "${MODDIR}" ]; then
	echo "post-build: no /lib/modules in the target" >&2; exit 1
fi
KVER="$(basename "${MODDIR}")"
DEP="${MODDIR}/modules.dep"
[ -f "${DEP}" ] || { echo "post-build: ${DEP} missing" >&2; exit 1; }

# Closure of MODULES_KEEP over modules.dep ("path.ko: dep.ko dep.ko"),
# by fixed point: small sets, plain sh.
keep=""
for m in ${MODULES_KEEP}; do
	path="$(grep -E "^[^:]*/${m}\.ko:" "${DEP}" | cut -d: -f1 | head -n1)"
	[ -n "${path}" ] || { echo "post-build: module ${m} not built" >&2; exit 1; }
	keep="${keep} ${path}"
done
changed=1
while [ "${changed}" = 1 ]; do
	changed=0
	for cur in ${keep}; do
		for dep in $(grep "^${cur}:" "${DEP}" | head -n1 | cut -d: -f2); do
			case " ${keep} " in *" ${dep} "*) ;; *) keep="${keep} ${dep}"; changed=1 ;; esac
		done
	done
done

# Delete every module outside the closure, then the empty directories.
find "${MODDIR}" -name '*.ko' | while read -r f; do
	rel="${f#"${MODDIR}"/}"
	case " ${keep} " in *" ${rel} "*) ;; *) rm -f "${f}" ;; esac
done
find "${MODDIR}" -type d -empty -delete
rm -f "${MODDIR}/build" "${MODDIR}/source"
depmod -a -b "${1}" "${KVER}"
echo "post-build: kept modules:${keep}"

# Mount points for the two writable partitions (M12): git does not track
# empty directories, so they are born here instead of in the overlay.
# S00storage mounts data (ext4, system state) and relicos (FAT32, the user's
# partition) onto them, first thing in the rcS.
mkdir -p "${1}/data" "${1}/relicos"

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

# The radio's daemons (M22 part 3). Buildroot installs an init script for
# dbus (S30dbus-daemon) and one for bluetoothd (S40bluetoothd) that start
# both unconditionally; the overlay's S45bluetooth starts them only when
# the menu's Bluetooth switch is on, so those two go. Both daemons write
# under /var/lib, which is on the erofs: bluetoothd its pairings, dbus its
# machine id. S45bluetooth bind-mounts /data/system/{bluetooth,dbus} over
# those two directories before the first start -- pairings survive a
# reboot and an update, like every other piece of user state. Bind mounts,
# not symlinks into /data: a link to a path that only exists on the device
# dangles on the host, and bluez's own install step (`install -dm700
# .../var/lib/bluetooth`, rerun on every bluez rebuild into the persisting
# TARGET_DIR) fails on it (build 10). The directories themselves are the
# mount points, empty on the image.
rm -f "${1}/etc/init.d/S30dbus-daemon" "${1}/etc/init.d/S40bluetoothd"
for d in bluetooth dbus; do
	[ -L "${1}/var/lib/${d}" ] && rm -f "${1}/var/lib/${d}"
	mkdir -p "${1}/var/lib/${d}"
done

# The clock floor (M16): the second this image was built, for S01clock to
# raise a never-set RTC to (the RK817's RTC resets to 2000-01-01, and the
# ES hides its clock for any year up to 2000). SOURCE_DATE_EPOCH wins when
# a reproducible build sets it. Rewritten every build on purpose: the floor
# should be the newest date the card knows about.
echo "${SOURCE_DATE_EPOCH:-$(date -u +%s)}" > "${1}/etc/relicos-build-epoch"

# The build's name (M25): /etc/relicos-version, "<UTC stamp>-<git short
# hash>", e.g. 20260920T0430Z-7958301. One string for three places -- the
# boot partition's RELICOS.TXT (post-image.sh copies it there), the RAUC
# bundle's version and file name (make-bundle.sh), and what the menu will
# show as the system version -- so "which build is this" has one answer
# wherever it is asked. The stamp first: it sorts, and two builds of the
# same tree (a rebuilt bundle) still differ. Replaces the stamp post-image.sh
# used to compute on its own since M3.
printf '%s-%s\n' "$(date -u +%Y%m%dT%H%MZ)" \
	"$(git -C "${BOARD_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
	> "${1}/etc/relicos-version"

# Who this system is, for software that asks (M26): /etc/os-release. The
# PortMaster reads NAME as its firmware name (CFW_NAME, on the bash side
# and the Python side alike -- unknown names get its generic behaviour,
# which is the right one here) and HW_DEVICE as the device on the Python
# side: "R36S" normalises to the r36s it knows (640x480, two sticks,
# RK3326), where the devicetree model, which starts with "RelicOS",
# matches none of its patterns and would leave the device unknown. The
# bash side takes the device from the model's second word, R36S, for
# free. Buildroot writes its own file (NAME=Buildroot) in target-finalize,
# before the overlay and this script; /etc/os-release is its symlink to
# /usr/lib/os-release, kept. Every value quoted: the Python side's regex
# only takes quoted ones. The version is the build's name.
ver="$(cat "${1}/etc/relicos-version")"
cat > "${1}/usr/lib/os-release" <<OSREL
NAME="RelicOS"
ID="relicos"
VERSION="${ver}"
VERSION_ID="${ver}"
PRETTY_NAME="RelicOS ${ver}"
HW_DEVICE="R36S"
OSREL

# libtheoradec.so.1 (M26 build 3b, measured): PortMaster's LOVE runtime
# (liblove-11.5.so) is linked against libtheoradec.so.1, the soname of
# libtheora 1.1; Buildroot's 1.2.0 installs libtheoradec.so.2. The ABI is
# the same one -- every symbol liblove imports is there, under the same
# version node, libtheoradec_1.0 (readelf -V/-Ws, build 3) -- only the file
# name moved. The loader matches by file name, so the old name points at
# the new file. Fails the build loudly if the library is not there.
[ -e "${1}/usr/lib/libtheoradec.so.2" ] || {
	echo "post-build: libtheoradec.so.2 missing" >&2; exit 1; }
ln -sfn libtheoradec.so.2 "${1}/usr/lib/libtheoradec.so.1"

# The wall clock's zone (M16, the clock commit): /etc/localtime on the
# immutable rootfs cannot hold the user's choice, so it points into /data,
# where the seed (board/r36s/rootfs-overlay/usr/share/relicos/data/system/
# localtime) puts the BR2_TARGET_LOCALTIME default and relicos-timezone puts
# whatever the ES's TIME ZONE menu picks. Until S00storage mounts /data the
# link dangles and libc falls back to UTC, which is what the RTC holds.
ln -sfn /data/system/localtime "${1}/etc/localtime"
