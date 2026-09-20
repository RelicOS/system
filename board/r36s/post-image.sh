#!/usr/bin/env bash
# Runs after every build, with BINARIES_DIR pointing at output/images.
# Creates the marker file and assembles sdcard.img from genimage.cfg.
set -eu

BOARD_DIR="$(dirname "$0")"

# Which build is on the card, readable from the device. key=value so the
# boot script can "env import -t" it and print itself in the serial log;
# still human-readable with md.b at the prompt. Since M25 the value is the
# one post-build.sh wrote into the rootfs as /etc/relicos-version, so the
# boot partition, the rootfs and the update bundle all name the same build.
printf 'relicos_build=%s\n' "$(cat "${TARGET_DIR}/etc/relicos-version")" \
	> "${BINARIES_DIR}/RELICOS.TXT"

# The RELICOS partition's build-time content (M12): README, the relicos.env
# override template (it moved here from boot -- it is a user file and has
# to survive updates), the dummy ROM, and the reserved folders. genimage's
# vfat handler copies directories recursively.
rm -rf "${BINARIES_DIR}/relicos"
cp -a "${BOARD_DIR}/relicos" "${BINARIES_DIR}/"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

# The update bundle (M25): the same rootfs.erofs and boot.vfat that went
# into sdcard.img, signed, for RELICOS/update/. Skipped, with a note, when
# there is no signing key in secrets/.
"${BOARD_DIR}/make-bundle.sh"
