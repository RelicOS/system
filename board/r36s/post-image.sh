#!/usr/bin/env bash
# Runs after every build, with BINARIES_DIR pointing at output/images.
# Creates the marker file and assembles sdcard.img from genimage.cfg.
set -eu

BOARD_DIR="$(dirname "$0")"

# One line telling us which build is on the card, readable from the device.
printf 'RelicOS build %s (%s)\n' \
	"$(git -C "${BOARD_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	> "${BINARIES_DIR}/RELICOS.TXT"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"
