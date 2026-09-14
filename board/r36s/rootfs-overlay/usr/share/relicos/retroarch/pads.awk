# RelicOS (M22): the ES's controller map, as RetroArch binds, per launch.
#
#   awk -v players="<player>\t<slot>\t<guid>\t<name>\t<layout>\t<mode>[\n...]" \
#       -f pads.awk /data/system/.emulationstation/es_input.cfg
#
# Run by /usr/bin/relicos-pads, which supplies the players (the ES's
# player order, one line each) and the slot (RetroArch's udev joypad
# number, recomputed there). Prints a RetroArch config fragment for
# players 1-8: the pad index and EVERY RetroPad bind, either from the ES's
# es_input.cfg entry for that device (matched by GUID and name, the pair
# the ES itself dedupes on in writeDeviceConfig) or "nul", RetroArch's
# spelling for unbound. Every key is written on purpose: the fragment is
# appended last, over the product defaults for player 1 (relicos.cfg) and
# over whatever the previous session left in the user's retroarch.cfg
# (config_save_on_exit persists the merge), so a bind can only come from
# THIS launch's controller. Players the ES did not name get their default
# slot and no binds at all.
#
# Names: the ES keeps every pad's map by POSITION, the SNES way -- "a"
# is the right button, "b" the bottom, "x" the top, "y" the left -- and
# RetroArch's RetroPad is the same SNES layout (b south, a east, y west,
# x north), so a/b/x/y carry over as they are. The pad's BUTTON LAYOUT
# (its page in CONTROLLER SETTINGS, the <layout> field) mirrors the four
# when it says "xbox": A at the bottom, B on the right, the Xbox and
# PlayStation habit, on any pad; the ES applies the same choice to its
# own menu (InputConfig::relicosName), one option for both worlds. The
# RGUI follows: menu_swap_ok_cancel_buttons makes it confirm with the
# RetroPad B when player 1 is mirrored, so the same physical button
# confirms everywhere.
# Shoulders are "pageup"/"pagedown" in the ES, l/r here. Sticks: the
# ES stores joystick1left/joystick1up with the value's sign giving the
# direction of "left"/"up" (it flips SDL's sign for exactly these), so
# minus_axis takes that sign and plus_axis the opposite. Numbering: the
# ES's ids are SDL's (buttons in evdev-code order, axes ABS_X.. skipping
# hats, hats separate); RetroArch's udev driver counts the same way
# (udev_joypad.c), which is what Batocera's configgen relies on too.
function attr(line, key,   s) {
	if (match(line, key "=\"[^\"]*\"")) {
		s = substr(line, RSTART + length(key) + 2, RLENGTH - length(key) - 3)
		gsub(/&quot;/, "\"", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s)
		gsub(/&amp;/, "\\&", s)
		return s
	}
	return ""
}
# One digital RetroPad key from an es_input entry: sets BTN and AXIS.
function digital(m,   f) {
	split(m, f, SUBSEP)
	if (f[1] == "button")     BTN  = f[2]
	else if (f[1] == "hat")   BTN  = "h" f[2] HATDIR[f[3]]
	else if (f[1] == "axis")  AXIS = (f[3] < 0 ? "-" : "+") f[2]
}
BEGIN {
	nd = split("b a x y up down left right pageup pagedown l2 r2 l3 r3 select start", ESK, " ")
	split("b a x y up down left right l r l2 r2 l3 r3 select start", RAK, " ")
	SWAP["a"] = "b"; SWAP["b"] = "a"; SWAP["x"] = "y"; SWAP["y"] = "x"
	ns = split("joystick1left joystick1up joystick2left joystick2up", ESS, " ")
	split("l_x l_y r_x r_y", RAS, " ")
	HATDIR[1] = "up"; HATDIR[2] = "right"; HATDIR[4] = "down"; HATDIR[8] = "left"
	cur = ""
}
/<inputConfig / {
	cur = ""
	if (attr($0, "type") == "joystick") {
		cur = attr($0, "deviceGUID") SUBSEP attr($0, "deviceName")
		HAVE[cur] = 1
		# For the fallbacks below: the first entry per GUID, per name.
		if (!(attr($0, "deviceGUID") in BYGUID)) BYGUID[attr($0, "deviceGUID")] = cur
		if (!(attr($0, "deviceName") in BYNAME)) BYNAME[attr($0, "deviceName")] = cur
		# internal="1" is what the ES writes for the handheld's pad; the
		# name covers an entry written before the ES knew to.
		INTERNAL[cur] = (attr($0, "internal") == "1" || attr($0, "deviceName") == "R36S Gamepad")
	}
}
/<\/inputConfig>/ { cur = "" }
/<input / && cur != "" {
	MAP[cur, attr($0, "name")] = attr($0, "type") SUBSEP attr($0, "id") SUBSEP attr($0, "value")
}
END {
	n = split(players, P, "\n")
	for (i = 1; i <= n; i++) {
		split(P[i], f, "\t")
		if (f[1] == "") continue
		SLOT[f[1]] = f[2]; KEY[f[1]] = f[3] SUBSEP f[4]; NAME[f[1]] = f[4]
		MIRROR[f[1]] = (f[5] == "xbox"); MODE[f[1]] = f[6]
	}
	menu = "nul"; swapmenu = "false"
	for (p = 1; p <= 8; p++) {
		pre = "input_player" p "_"
		if (!(p in SLOT)) {
			print pre "joypad_index = \"" p - 1 "\""
			continue
		}
		# The entry: by GUID and name, the pair the ES dedupes on; else
		# by GUID; else by name -- the ES itself falls back to the name
		# (InputManager.cpp, tryLoadInputConfig), and a pad it accepted
		# that way must not come out unbound here (build 25: a
		# reconnected pad with every bind "nul" but the menu toggle).
		split(KEY[p], kf, SUBSEP)
		k = (KEY[p] in HAVE) ? KEY[p] : (kf[1] in BYGUID) ? BYGUID[kf[1]] : (kf[2] in BYNAME) ? BYNAME[kf[2]] : ""
		if (k != "" && k != KEY[p]) print "# player " p ": entry matched by " ((kf[1] in BYGUID) ? "GUID" : "name") " only"
		mirror = (k != "" && MIRROR[p])
		print "# player " p ": " NAME[p] (k == "" ? " (no es_input.cfg entry: unbound)" : mirror ? " (layout xbox: A bottom, B right)" : " (layout nintendo: A right, B bottom)")
		print pre "joypad_index = \"" SLOT[p] "\""
		for (d = 1; d <= nd; d++) {
			BTN = "nul"; AXIS = "nul"
			es = ESK[d]
			if (mirror && (es in SWAP)) es = SWAP[es]
			if (k != "" && ((k, es) in MAP)) digital(MAP[k, es])
			print pre RAK[d] "_btn = \"" BTN "\""
			print pre RAK[d] "_axis = \"" AXIS "\""
		}
		for (s = 1; s <= ns; s++) {
			minus = "nul"; plus = "nul"
			if (k != "" && ((k, ESS[s]) in MAP)) {
				split(MAP[k, ESS[s]], f, SUBSEP)
				if (f[1] == "axis") {
					minus = (f[3] < 0 ? "-" : "+") f[2]
					plus  = (f[3] < 0 ? "+" : "-") f[2]
				}
			}
			print pre RAS[s] "_minus_axis = \"" minus "\""
			print pre RAS[s] "_plus_axis = \"" plus "\""
			print pre RAS[s] "_minus_btn = \"nul\""
			print pre RAS[s] "_plus_btn = \"nul\""
		}
		# The RGUI toggle is a hotkey, and RetroArch reads joypad hotkeys
		# from player 1's pad only: that pad's BTN_MODE -- its Xbox/PS/Home
		# button, FN on the handheld -- numbered by relicos-pads from the
		# kernel's own bitmap (<mode>), since SDL's table can be stale for
		# a kernel (build 21: "guide" 16, the button is 12). Without one,
		# the "hotkey" the user chose in the ES's configurator, unless it
		# is the select button (the ES's fallback when a pad has neither;
		# build 18 showed a View button that both selected and toggled).
		# Otherwise no menu button. Player 1's pad is the only one the
		# frontend hears in a game (patches/retroarch/0001): FN and
		# Start+Select on any other pad do nothing -- decided, not a gap.
		if (p == 1) {
			hk = ""; sel = ""
			if (k != "" && ((k, "hotkey") in MAP)) { split(MAP[k, "hotkey"], f, SUBSEP); if (f[1] == "button") hk = f[2] }
			if (k != "" && ((k, "select") in MAP)) { split(MAP[k, "select"], f, SUBSEP); if (f[1] == "button") sel = f[2] }
			if (MODE[1] != "") menu = MODE[1]
			else if (hk != "" && hk != sel) menu = hk
			swapmenu = mirror ? "true" : "false"
		}
	}
	print "input_menu_toggle_btn = \"" menu "\""
	print "menu_swap_ok_cancel_buttons = \"" swapmenu "\""
}
