Ports: native games, managed by PortMaster
==========================================

A port is a game that runs on the console itself, outside the emulators
(Doom, Stardew Valley, Celeste...). PortMaster is the tool that
downloads, installs and updates them. RelicOS ships none of it: you
install the version you want, and it lives here, on your partition --
system updates never touch it.

  1. Download Install.PortMaster.sh from https://portmaster.games
     (Install.Full.PortMaster.sh, much larger, includes every runtime
     -- for a console without Wi-Fi).
  2. Copy it into this folder (roms/ports).
  3. On the console: PORTS > Install.PortMaster. When it returns, the
     list shows PortMaster; open it. With Wi-Fi on (NETWORK SETTINGS),
     it lists the ports you can install.

Without Wi-Fi: copy a port's zip (from the PortMaster site) into
roms/ports/autoinstall/ and open PortMaster -- it installs what it finds
there. Many ports need the game's own data files; PortMaster tells you
which, and where to put them.

The menu lists PORTS only when at least one .sh is in this folder.
PortMaster keeps its log in roms/ports/PortMaster/log.txt; the last
launch of anything from this folder is in roms/ports/logs/.
