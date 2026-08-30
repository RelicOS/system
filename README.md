# RelicOS — system

RelicOS is an operating system for retro handhelds, focused on four things:

1. **Boot time** — short
2. **Suspend** that actually works
3. **Balance** between battery life and performance
4. **A good-looking interface**, fully preconfigured — the user should never
   have to configure anything

Inspired by ArkOS, but **immutable** and with **OTA updates**.

Supported hardware: the **R36S** (Rockchip RK3326) — a quad Cortex-A35 with a
Mali-G31, 1GB of RAM, a 640x480 panel and no built-in networking.

## Status

**Early development. Nothing here is usable yet** — there is no image to
download and no installation instructions to follow.

## Building

The build is Buildroot (pinned as a submodule) driven by a `BR2_EXTERNAL`
tree — this repository. Buildroot's history is large; the shallow submodule
fetch below avoids downloading all of it:

```bash
git clone https://github.com/relicos/system.git
cd system
git submodule update --init --depth 1
```

On NixOS, enter the FHS build environment first (Buildroot needs a real FHS
hierarchy, which the flake provides):

```bash
nix develop
```

Then:

```bash
make r36s
```

The first build compiles a full cross-toolchain from source: expect about an
hour and ~10 GB of disk. The result is `output/images/sdcard.img`, a complete
SD card image containing mainline U-Boot (TPL + SPL + BL31 + U-Boot proper at
sector 64) and a FAT32 partition with a build marker file.

Write it to a card with:

```bash
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
```

Then verify the write — remove and reinsert the card first, so the checksum
reads the card and not the page cache:

```bash
head -c 16777216 output/images/sdcard.img | sha256sum
sudo head -c 16777216 /dev/sdX | sha256sum
```

The two hashes must match.
