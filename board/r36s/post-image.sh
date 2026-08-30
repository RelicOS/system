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

# Override template for the FAT partition (boot.scr imports it last, so a
# card can be fixed in the field by editing this file — no rebuild).
cp "${BOARD_DIR}/relicos.env" "${BINARIES_DIR}/relicos.env"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"
