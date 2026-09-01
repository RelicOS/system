#!/usr/bin/env bash
# Runs after every build, with BINARIES_DIR pointing at output/images.
# Creates the marker file and assembles sdcard.img from genimage.cfg.
set -eu

BOARD_DIR="$(dirname "$0")"

# Which build is on the card, readable from the device. key=value so the
# boot script can "env import -t" it and print itself in the serial log;
# still human-readable with md.b at the prompt.
printf 'relicos_build=%s (%s)\n' \
	"$(git -C "${BOARD_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	> "${BINARIES_DIR}/RELICOS.TXT"

# The RELIC partition's build-time content (M12): README, the relicos.env
# override template (it moved here from boot -- it is a user file and has
# to survive updates), the dummy ROM, and the reserved folders. genimage's
# vfat handler copies directories recursively.
rm -rf "${BINARIES_DIR}/relic"
cp -a "${BOARD_DIR}/relic" "${BINARIES_DIR}/"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"
