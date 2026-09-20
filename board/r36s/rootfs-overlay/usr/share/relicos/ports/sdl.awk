# RelicOS (M26): the ES's controller map, as SDL game-controller mappings.
#
#   awk -v players="<player>\t<slot>\t<guid>\t<name>\t<layout>\t<mode>\t<stick>[\n...]" \
#       -f sdl.awk /data/system/.emulationstation/es_input.cfg
#
# Run by /usr/bin/relicos-pads --sdl with the same players string it
# builds for RetroArch (retroarch/pads.awk); slot, mode and stick are
# not used here. One line per pad, in SDL's own mapping format
# (<guid>,<name>,a:b1,...,platform:Linux,), for relicos-port to export as
# SDL_GAMECONTROLLERCONFIG: PortMaster's interface, gptokeyb and the
# game read it before any file, so a port sees each pad the way the ES
# maps it and the way its BUTTON LAYOUT says.
#
# Names. The ES keeps every pad's map by POSITION, the SNES way: "a" is
# the right button, "b" the bottom, "x" the top, "y" the left. SDL's
# names are Xbox positions -- "a" bottom, "b" right, "x" left, "y" top --
# but every port reads them as the ACTIONS printed on an Xbox pad: "a"
# confirms. So the layout decides which physical button is SDL's "a":
# NINTENDO (the default, this handheld's own labels): the right button,
# the ES's "a" -- SDL a <- ES a, b <- b, x <- x (top), y <- y (left);
# XBOX (A bottom, B right, X left, Y top): the ES's four mirrored, the
# same SWAP relicos-pads applies for RetroArch and the ES applies to its
# own menu (InputConfig::relicosName) -- one option, every world.
# Shoulders: pageup/pagedown -> leftshoulder/rightshoulder; l2/r2 ->
# lefttrigger/righttrigger; select -> back; hotkey (the pad's own FN,
# Xbox or Home button) -> guide, which is gptokeyb's hotkey; l3/r3 ->
# leftstick/rightstick; up/down/left/right -> dpup/dpdown/dpleft/dpright.
# Types: a button is bN; a hat is hI.D (the ES stores SDL's own bit for
# the direction: 1 up, 2 right, 4 down, 8 left); a digital input on an
# axis is the half-axis with the ES's sign (+aN/-aN). Sticks: the ES
# stores joystick1left/joystick1up with the sign giving the direction of
# "left"/"up"; SDL's leftx/lefty are negative to the left/up, so a
# positive sign is SDL's inverted axis, aN~. Numbering: the ES's ids are
# SDL's (InputManager), so they go through as they are.
function attr(line, key,   s) {
	if (match(line, key "=\"[^\"]*\"")) {
		s = substr(line, RSTART + length(key) + 2, RLENGTH - length(key) - 3)
		gsub(/&quot;/, "\"", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s)
		gsub(/&amp;/, "\\&", s)
		return s
	}
	return ""
}
# One SDL digital target from an es_input entry, or "".
function digital(m,   f) {
	split(m, f, SUBSEP)
	if (f[1] == "button")     return "b" f[2]
	else if (f[1] == "hat")   return "h" f[2] "." f[3]
	else if (f[1] == "axis")  return (f[3] < 0 ? "-" : "+") "a" f[2]
	return ""
}
# One SDL stick axis from an es_input entry, or "".
function stick(m,   f) {
	split(m, f, SUBSEP)
	if (f[1] == "axis") return "a" f[2] (f[3] < 0 ? "" : "~")
	return ""
}
BEGIN {
	nd = split("a b x y pageup pagedown l2 r2 select start hotkey l3 r3 up down left right", ESK, " ")
	split("a b x y leftshoulder rightshoulder lefttrigger righttrigger back start guide leftstick rightstick dpup dpdown dpleft dpright", SDLK, " ")
	SWAP["a"] = "b"; SWAP["b"] = "a"; SWAP["x"] = "y"; SWAP["y"] = "x"
	ns = split("joystick1left joystick1up joystick2left joystick2up", ESS, " ")
	split("leftx lefty rightx righty", SDLS, " ")
	cur = ""
}
/<inputConfig / {
	cur = ""
	if (attr($0, "type") == "joystick") {
		cur = attr($0, "deviceGUID") SUBSEP attr($0, "deviceName")
		HAVE[cur] = 1
		if (!(attr($0, "deviceGUID") in BYGUID)) BYGUID[attr($0, "deviceGUID")] = cur
		if (!(attr($0, "deviceName") in BYNAME)) BYNAME[attr($0, "deviceName")] = cur
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
		guid = f[3]; name = f[4]; mirror = (f[5] == "xbox")
		key = guid SUBSEP name
		k = (key in HAVE) ? key : (guid in BYGUID) ? BYGUID[guid] : (name in BYNAME) ? BYNAME[name] : ""
		if (k == "") {
			print "# player " f[1] ": " name " (no es_input.cfg entry: SDL's own mapping)" > "/dev/stderr"
			continue
		}
		split(k, kf, SUBSEP)
		line = kf[1] "," kf[2] ","
		for (d = 1; d <= nd; d++) {
			es = ESK[d]
			if (mirror && (es in SWAP)) es = SWAP[es]
			if (((k, es) in MAP) && (t = digital(MAP[k, es])) != "") line = line SDLK[d] ":" t ","
		}
		for (s = 1; s <= ns; s++)
			if (((k, ESS[s]) in MAP) && (t = stick(MAP[k, ESS[s]])) != "") line = line SDLS[s] ":" t ","
		print line "platform:Linux,"
		print "# player " f[1] ": " name (mirror ? " (layout xbox: A bottom, B right)" : " (layout nintendo: A right, B bottom)") > "/dev/stderr"
	}
}
