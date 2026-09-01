RelicOS user partition (RELIC)
==============================

This is the only partition of the card your PC is meant to see, and the
only one you should ever need to touch. Everything else on the card is
the system itself, updated as a whole; anything you put THERE is lost on
update. Anything you put HERE survives updates.

Folders (created automatically on first boot if missing):

  roms/         Your games, one folder per system (roms/gba, roms/snes...).
  saves/        Save files and save states.
  themes/       Extra menu themes. Same name as a built-in theme? The
                built-in one wins; pick a different folder name.
  music/        Background music for the menu.
  screenshots/  Screenshots taken from the menu.
  overlays/     Reserved for hardware overlays (advanced, documented
                separately).
  update/       Drop RelicOS update files here (future).

Files:

  relicos.env   Advanced boot overrides -- read at every boot, documented
                inside. Leave it alone unless you know why you are editing
                it.

Do not reformat this partition: the console recreates missing folders,
but a missing partition means a reflash.
