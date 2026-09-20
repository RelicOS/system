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

## Ports (PortMaster)

Ports are games that run natively on the console, outside the emulators;
PortMaster is the tool that installs them. RelicOS ships none of it: download
`Install.PortMaster.sh` from [portmaster.games](https://portmaster.games)
(the *Full* installer bundles every runtime, for a console without Wi-Fi),
copy it into `roms/ports/` on the `RELICOS` partition, and run it from
**PORTS** in the menu. PortMaster, its runtimes and every port then live in
`roms/ports/` — on your partition, untouched by system updates, and updated
by PortMaster itself. Without Wi-Fi, a port's zip copied into
`roms/ports/autoinstall/` is installed the next time PortMaster opens.

The pads work in every port the way the menu maps them, including each
pad's BUTTON LAYOUT (Nintendo or Xbox); the sticks are the sticks. The
system provides what PortMaster asks of it (bash, python3, the SDL
libraries, the LÖVE runtime's dependencies) and identifies itself to it
through `/etc/os-release`; the launcher, `relicos-port`, logs every launch
to `roms/ports/logs/`.

## Updating a console

RelicOS keeps two copies of the system on the card and updates the one not
in use, so an update that fails to boot falls back to the previous version
on its own. An update is a signed RAUC bundle, `relicos-r36s-<version>.raucb`:
copy it into the `update/` folder of the `RELICOS` partition (the one the
PC sees), boot the console, and choose **UPDATES → START UPDATE** in the
menu. About a minute later it asks you to reboot; **APPLY UPDATE** does it.
Games, saves and settings are not touched.

A build produces the bundle next to the card image, `output/images/
relicos-r36s-<version>.raucb`, when a signing key exists at
`secrets/rauc-key.pem` (gitignored). The matching certificate is what the
console trusts, `board/r36s/rootfs-overlay/etc/rauc/keyring.pem`; a
console only installs bundles signed by the key behind the certificate it
carries. To create a development key pair (the bundle step prints this
command when the key is missing):

```bash
openssl req -x509 -newkey rsa:4096 -nodes -days 7300   -subj '/O=RelicOS/CN=RelicOS development signing key'   -keyout secrets/rauc-key.pem -out board/r36s/rootfs-overlay/etc/rauc/keyring.pem
```

The version of a build is `<UTC stamp>-<git short hash>`, the same string
in `/etc/relicos-version` on the console, in `RELICOS.TXT` on its boot
partition, and in the bundle's name.
