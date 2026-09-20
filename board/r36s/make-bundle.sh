#!/usr/bin/env bash
# Builds the RAUC update bundle for this image (M25). Called by post-image.sh
# after genimage, with BINARIES_DIR, HOST_DIR, TARGET_DIR and
# BR2_EXTERNAL_RELICOS_PATH in the environment (Buildroot exports them).
#
# A bundle is a squashfs holding a manifest and the slot images, signed
# (CMS, X.509) with the private key in secrets/ -- gitignored, PC only. The
# console verifies the signature against /etc/rauc/keyring.pem, the
# certificate of that key, and refuses anything else. Format "verity":
# the squashfs is read through dm-verity, every block checked against a
# hash tree whose root hash is in the signed manifest.
#
# No key, no bundle: the sdcard.img never depends on this step. A fresh
# checkout builds a flashable card and prints how to make a key.
set -eu

BOARD_DIR="$(dirname "$0")"
KEY="${BR2_EXTERNAL_RELICOS_PATH}/secrets/rauc-key.pem"
CERT="${BOARD_DIR}/rootfs-overlay/etc/rauc/keyring.pem"
VERSION="$(cat "${TARGET_DIR}/etc/relicos-version")"
OUT="${BINARIES_DIR}/relicos-r36s-${VERSION}.raucb"

if [ ! -f "${KEY}" ]; then
	echo "make-bundle: no ${KEY}, no bundle (the card image is unaffected)."
	echo "make-bundle: to make one: openssl req -x509 -newkey rsa:4096 -nodes -days 7300" \
	     "-subj '/O=RelicOS/CN=RelicOS development signing key' -keyout ${KEY} -out ${CERT}"
	exit 0
fi

# The content directory: hard links into BINARIES_DIR (same filesystem,
# no copy of 340 MiB; mksquashfs follows them), a manifest, nothing else.
# Slot class names (rootfs, boot) are the ones /etc/rauc/system.conf
# declares; RAUC fills in size and sha256 of each image at bundle time.
# type=raw on both: RAUC 1.15 wants the image type spelled out unless the
# file extension is one it knows (.img, .ext4, .vfat, ...) -- .erofs is
# not -- and "raw" says what the slots are: whole partitions, written as
# they come (build 2 of M25 stopped on exactly this line).
WORK="${BINARIES_DIR}/bundle"
# One bundle per images/: the previous build's, named by its own stamp,
# would otherwise pile up next to the new one.
rm -rf "${WORK}" "${BINARIES_DIR}"/relicos-r36s-*.raucb
mkdir -p "${WORK}"
ln -f "${BINARIES_DIR}/rootfs.erofs" "${WORK}/rootfs.erofs" 2>/dev/null || cp "${BINARIES_DIR}/rootfs.erofs" "${WORK}/"
ln -f "${BINARIES_DIR}/boot.vfat"    "${WORK}/boot.vfat"    2>/dev/null || cp "${BINARIES_DIR}/boot.vfat" "${WORK}/"
cat > "${WORK}/manifest.raucm" <<MANIFEST
[update]
compatible=relicos-r36s
version=${VERSION}

[bundle]
format=verity

[image.rootfs]
filename=rootfs.erofs
type=raw

[image.boot]
filename=boot.vfat
type=raw
MANIFEST

"${HOST_DIR}/bin/rauc" bundle --cert="${CERT}" --key="${KEY}" "${WORK}" "${OUT}"
rm -rf "${WORK}"
echo "make-bundle: ${OUT} ($(du -h "${OUT}" | cut -f1))"
