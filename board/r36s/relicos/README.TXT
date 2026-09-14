RelicOS user partition (RELICOS)
================================

This is the only partition of the card your PC is meant to see, and the
only one you should ever need to touch. Everything else on the card is
the system itself, updated as a whole; anything you put THERE is lost on
update. Anything you put HERE survives updates.

Fresh from the image this partition is 1 GB. The first time the console
boots it grows the partition to the end of the card, keeping whatever
you already copied here -- so a card written today shows 1 GB on the PC
until its first boot, and the rest of the card after it.

Folders (created automatically on first boot if missing):

  roms/         Your games, one folder per system (roms/gb, roms/nes...).
  bios/         BIOS files some systems need (Game Boy needs none).
  saves/        Save files and save states, one folder per system.
  themes/       Extra menu themes. Same name as a built-in theme? The
                built-in one wins; pick a different folder name.
  music/        Background music for the menu.
  screenshots/  Screenshots taken from the menu.
  overlays/     Reserved for hardware overlays (advanced, documented
                separately).
  update/       Drop RelicOS update files here (future).
  diag/         Written by the console: boot.txt (the kernel log and the
                USB/network/Bluetooth state at the end of every boot),
                shutdown.txt (the same at every clean shutdown), and the
                Bluetooth log and trace. Safe to delete. A script saved here as run.sh runs once per boot,
                as root, with its output in run.txt -- a bench tool for
                the people who build RelicOS; leave it out otherwise.

Files:

  relicos.env   Advanced boot overrides -- read at every boot, documented
                inside. Leave it alone unless you know why you are editing
                it.

Do not reformat this partition: the console recreates missing folders,
but a missing partition means a reflash.
