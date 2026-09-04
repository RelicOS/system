# Boot splash artwork

Two frames, each owned by the layer that is alive when it is shown. Both
are generated from the PNGs in this folder by `make-splash.py` (standard
library only; it runs inside Buildroot's post-build).

| Frame | Source | Output | Who draws it, when |
|---|---|---|---|
| 1 | `r36s-mark-640x480.png` | `mark` mode: a P3 PPM of the mark alone, frozen into `patches/linux/0003-…` as `drivers/video/logo/logo_linux_clut224.ppm` | fbcon, the moment the panel lights (~3.3 s into the kernel), centred by `fbcon=logo-pos:center,logo-count:1` in `boot.cmd` |
| 2 | `relicos-splash-640x480.png` | `full` mode: a P6 PPM at `/usr/share/relicos/splash.ppm`, made by `post-build.sh` | `S15splash`, BusyBox `fbsplash` onto `/dev/fb0`, after udevd |

The ES's own splash follows frame 2 once `relicos-menu` starts it.

## Changing frame 1

The kernel logo lives inside the kernel `Image`, so a new mark is a new
kernel patch, not a file on the card:

```bash
./make-splash.py mark r36s-mark-640x480.png /tmp/logo_linux_clut224.ppm
cd ../../output/build/linux-6.12.91
diff -u drivers/video/logo/logo_linux_clut224.ppm /tmp/logo_linux_clut224.ppm \
    | sed 's|^--- .*|--- a/drivers/video/logo/logo_linux_clut224.ppm|; s|^+++ .*|+++ b/drivers/video/logo/logo_linux_clut224.ppm|'
```

Paste that hunk under the header of `patches/linux/0003-…` and
`make -C output linux-dirclean` so Buildroot re-applies the patches.
CLUT224 takes at most 224 colours; the script refuses more.

## Changing frame 2

Replace the PNG and rebuild (`make -C output target-finalize` is not
enough on its own: post-build runs as part of `make`). 640x480, 8-bit RGB or
RGBA, non-interlaced.
