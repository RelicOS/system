/*
 * relicos-joypad -- fuse this unit's two evdev halves into one gamepad.
 *
 * The R36S on mainline drivers exposes its controls as two input devices:
 * "gpio-keys" (the 17 buttons, BTN_* codes, no axes) and "adc-joystick"
 * (the two sticks, ABS_X/Y/RX/RY, no buttons). EmulationStation copes
 * (it sees two "players" and navigates with both); RetroArch does not:
 * its udev joypad driver binds ONE device per port, so the buttons would
 * become player 1 and the sticks player 2. Every RK3326 distro solves
 * this in the kernel with an out-of-tree joypad driver. RelicOS keeps the
 * kernel mainline (M8) and solves it here instead, in userspace:
 *
 *   1. find both source devices BY NAME (never by event index: the probe
 *      order shifted once already, M8 field note);
 *   2. grab them (EVIOCGRAB): nothing else receives their events;
 *   3. create one uinput device, "R36S Gamepad", carrying exactly the
 *      key bits of gpio-keys and the axes of adc-joystick -- each axis
 *      re-centred and normalised, see "The sticks" below;
 *   4. forward every EV_KEY/EV_ABS/EV_SYN event, one SYN_REPORT per
 *      source SYN, so a stick frame or a key frame stays atomic.
 *
 * A udev rule (61-relicos-joypad.rules) then drops ID_INPUT_JOYSTICK from
 * the two originals, so SDL2 (the ES) and RetroArch enumerate only the
 * fused device. The daemon logs what it found and what it created on
 * stderr -- the serial console at boot -- and only then detaches, so the
 * init script's "OK" means the device exists.
 *
 * No timers, no polling: the loop sleeps in poll(). SIGTERM tears the
 * uinput device down and releases the grabs.
 *
 * The volume keys and the brightness shortcut (M17). VOLUME-UP/DOWN live
 * in a third device, "gpio-keys-vol" (their own gpio-keys node, with
 * autorepeat). It is grabbed too and its keys never leave this daemon:
 * VOL+/VOL- alone step the ALSA "Master" control (the codec's digital
 * volume, the same control the ES's sound slider drives), and with FN
 * held they step the panel backlight instead (/sys/class/backlight). One
 * step is 5 % of the control's range, repeating while held; the
 * backlight never goes below 5 %. Nothing is re-emitted: a keys-only
 * uinput device shows up in the ES as an unconfigured keyboard and opens
 * its controller wizard on the first press (observed after M17 build 4),
 * and RetroArch's own volume hotkeys would double the change. One volume
 * for the menu and the game, in the hardware, is the point. That makes
 * FN a modifier, and a modifier cannot be delivered on press (RetroArch
 * opens its menu on FN): FN is held back while down and, if no VOL key
 * was used meanwhile, delivered on release as a short synthetic tap --
 * pressed for FN_TAP_MS, long enough for a consumer that samples once a
 * frame to see it down. Each change is also written to
 * /data/system/{brightness,volume}, which S01backlight and S30audio
 * restore at boot.
 *
 * The power button (M21). A fourth device, "rk805 pwrkey" (the RK817's
 * PWRON pin, driver rk805-pwrkey, one key: KEY_POWER), grabbed like the
 * others so nothing else ever sees KEY_POWER (SDL would hand it to the ES
 * and RetroArch as a keyboard key). A short tap -- release within
 * PWR_TAP_MAX_MS of the press -- runs /usr/bin/relicos-suspend in a child
 * process; the daemon never blocks. Holding the button is left to the
 * PMIC, which powers the board off by itself (banner off=0x04). After a
 * resume, the tap that woke the device is delivered here as a fresh
 * press/release pair and asks for a second sleep; relicos-suspend's lock
 * turns that one away. Acting on the release, not the press, is what
 * keeps the long press free.
 *
 * The sticks (M26). From M14 to M26 each axis's absinfo was copied
 * verbatim and the values forwarded raw. The SARADC range in the DTS
 * (abs-range, min..max) was measured on another unit, and on this one
 * the sticks do not rest at its midpoint: measured 2026-09-20 with
 * EVIOCGABS, hands off, ABS_X 409 in 30..900 (-12.9 % of the
 * half-travel), ABS_Y -7.2 %, ABS_RX +0.5 %, ABS_RY 527 in 60..850
 * (+18.2 %). Every consumer scales min..max linearly, so at rest the
 * left stick read "left" and the right stick "down" past the 12.5 %
 * threshold PortMaster's interface uses (which has no dead zone of its
 * own): its menu scrolled by itself the moment a stick was touched
 * (M26 build 6), and RetroArch's menu had shown the same in M23. Every
 * unit is different, so the answer is not a number in the DTS: at
 * start the rest position of each axis is read (EVIOCGABS: the value
 * field is the current one -- with the sticks untouched at boot, the
 * centre), the output axis is declared as -AXIS_OUT_MAX..AXIS_OUT_MAX,
 * and each value is mapped from its own side of the rest position with
 * a dead zone of AXIS_DEADZONE % of that side's travel: rest is 0, the
 * zone is 0, the rest of the travel is linear to the edge. A stick held
 * at boot makes that its centre until the next boot; re-centring on
 * demand and a wider or narrower zone from the menu are seeds. The raw
 * device keeps the DTS's fuzz: the kernel filters the ADC noise before
 * it reaches here.
 *
 * Bench: `relicos-joypad -f -v` stays in the foreground and echoes every
 * forwarded event (the evtest this rootfs does not carry).
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <alsa/asoundlib.h>

#define KEYS_NAME   "gpio-keys"
#define AXES_NAME   "adc-joystick"
#define VOL_NAME    "gpio-keys-vol"
#define PWR_NAME    "rk805 pwrkey"
#define OUT_NAME    "R36S Gamepad"
#define OUT_VENDOR  0x5245   /* "RE" */
#define OUT_PRODUCT 0x0036   /* R36S */
#define OUT_VERSION 0x0001
#define PIDFILE     "/var/run/relicos-joypad.pid"

#define BACKLIGHT_CLASS "/sys/class/backlight"
#define BRIGHTNESS_SAVE "/data/system/brightness"
#define MIXER_CARD      "default"
#define MIXER_CONTROL   "Master"
#define VOLUME_SAVE     "/data/system/volume"
#define FN_TAP_MS       40   /* the synthetic FN press stays down this long */
#define STEP_DIV        20   /* one VOL step = max_brightness / 20 = 5 % */
#define FLOOR_DIV       20   /* never below max_brightness / 20 */
#define STEP_MIN_MS     80   /* autorepeat is faster than the eye */
#define SUSPEND_CMD     "/usr/bin/relicos-suspend"
#define PWR_TAP_MAX_MS  1000 /* a release later than this is a hold, not a tap */

/* The four sources, in pollfd order. */
enum { SRC_KEYS, SRC_AXES, SRC_VOL, SRC_PWR, SRC_COUNT };

/* The sticks: the output range of every axis, and the dead zone as a
 * percentage of each side's travel from the rest position. */
#define AXIS_OUT_MAX  32767
#define AXIS_DEADZONE 8
static struct { int present, min, max, rest; } axis_cal[ABS_MAX + 1];
static const char *const src_name[SRC_COUNT] = {
	KEYS_NAME, AXES_NAME, VOL_NAME, PWR_NAME
};

#define LONG_BITS       (8 * sizeof(unsigned long))
#define BITS_TO_LONGS(n) (((n) + LONG_BITS - 1) / LONG_BITS)
#define TEST_BIT(bit, arr) \
	(((arr)[(bit) / LONG_BITS] >> ((bit) % LONG_BITS)) & 1UL)

static volatile sig_atomic_t stopping;
static int verbose;

/* The FN modifier and the brightness shortcut. */
static int fn_down;          /* the physical FN is held */
static int fn_used;          /* a VOL key was used while it was held */
static long fn_release_at;   /* ms clock: when to lift the synthetic tap; 0 = none */
static int vol_swallowed[2]; /* [0]=VOL-, [1]=VOL+: its press was eaten, eat its release too */
static long last_step_at;
static long pwr_down_at;     /* ms clock: when the power key went down; 0 = up */
static char bl_brightness[128], bl_max[128];
static int bl_max_value;
static snd_mixer_t *mixer;
static snd_mixer_elem_t *master;
static long vol_min, vol_max;

static long now_ms(void)
{
	struct timeval tv;

	gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000L + tv.tv_usec / 1000;
}

static int read_int(const char *path, int *out)
{
	FILE *f = fopen(path, "r");
	int ok;

	if (!f)
		return -1;
	ok = fscanf(f, "%d", out) == 1;
	fclose(f);
	return ok ? 0 : -1;
}

static int write_int(const char *path, int v)
{
	FILE *f = fopen(path, "w");

	if (!f)
		return -1;
	fprintf(f, "%d\n", v);
	return fclose(f) == 0 ? 0 : -1;
}

/* The first backlight the kernel offers (this unit has one, "backlight"). */
static void find_backlight(void)
{
	DIR *dir = opendir(BACKLIGHT_CLASS);
	struct dirent *ent;

	if (!dir)
		return;
	while ((ent = readdir(dir))) {
		if (ent->d_name[0] == '.')
			continue;
		snprintf(bl_brightness, sizeof bl_brightness, "%s/%s/brightness",
			 BACKLIGHT_CLASS, ent->d_name);
		snprintf(bl_max, sizeof bl_max, "%s/%s/max_brightness",
			 BACKLIGHT_CLASS, ent->d_name);
		if (read_int(bl_max, &bl_max_value) == 0 && bl_max_value > 0) {
			fprintf(stderr, "relicos-joypad: backlight = %s (max %d)\n",
				ent->d_name, bl_max_value);
			break;
		}
		bl_max_value = 0;
	}
	closedir(dir);
	if (!bl_max_value)
		fprintf(stderr, "relicos-joypad: no backlight, FN+VOL does nothing\n");
}

static void step_brightness(int dir)
{
	int cur, next, step, floor;
	long t = now_ms();

	if (!bl_max_value || t - last_step_at < STEP_MIN_MS)
		return;
	last_step_at = t;
	if (read_int(bl_brightness, &cur) < 0)
		return;
	step = bl_max_value / STEP_DIV;
	if (step < 1)
		step = 1;
	floor = bl_max_value / FLOOR_DIV;
	if (floor < 1)
		floor = 1;
	next = cur + dir * step;
	if (next > bl_max_value)
		next = bl_max_value;
	if (next < floor)
		next = floor;
	if (next == cur)
		return;
	if (write_int(bl_brightness, next) < 0) {
		fprintf(stderr, "relicos-joypad: %s: %s\n", bl_brightness, strerror(errno));
		return;
	}
	/* Remembered for S01backlight; /data may be missing on a bench card. */
	write_int(BRIGHTNESS_SAVE, next);
	if (verbose)
		fprintf(stderr, "brightness: %d -> %d of %d\n", cur, next, bl_max_value);
}

/* The mixer is opened on the first VOL press: the card is there at S05
 * (built-in driver), but there is no reason to hold it before it is
 * needed. Errors are logged once and the keys then do nothing. */
static int open_mixer(void)
{
	snd_mixer_selem_id_t *sid;
	static int failed;

	if (master)
		return 0;
	if (failed)
		return -1;
	failed = 1;
	if (snd_mixer_open(&mixer, 0) < 0 ||
	    snd_mixer_attach(mixer, MIXER_CARD) < 0 ||
	    snd_mixer_selem_register(mixer, NULL, NULL) < 0 ||
	    snd_mixer_load(mixer) < 0) {
		fprintf(stderr, "relicos-joypad: mixer %s: cannot open\n", MIXER_CARD);
		return -1;
	}
	snd_mixer_selem_id_alloca(&sid);
	snd_mixer_selem_id_set_index(sid, 0);
	snd_mixer_selem_id_set_name(sid, MIXER_CONTROL);
	master = snd_mixer_find_selem(mixer, sid);
	if (!master || snd_mixer_selem_get_playback_volume_range(master, &vol_min, &vol_max) < 0 ||
	    vol_max <= vol_min) {
		fprintf(stderr, "relicos-joypad: mixer control %s: not found\n", MIXER_CONTROL);
		master = NULL;
		return -1;
	}
	failed = 0;
	fprintf(stderr, "relicos-joypad: volume = %s \"%s\" (%ld..%ld)\n",
		MIXER_CARD, MIXER_CONTROL, vol_min, vol_max);
	return 0;
}

static void step_volume(int dir)
{
	long cur, next, step;
	long t = now_ms();

	if (t - last_step_at < STEP_MIN_MS)
		return;
	last_step_at = t;
	if (open_mixer() < 0)
		return;
	snd_mixer_handle_events(mixer); /* pick up what the ES slider did */
	if (snd_mixer_selem_get_playback_volume(master, SND_MIXER_SCHN_FRONT_LEFT, &cur) < 0)
		return;
	step = (vol_max - vol_min) / STEP_DIV;
	if (step < 1)
		step = 1;
	next = cur + dir * step;
	if (next > vol_max)
		next = vol_max;
	if (next < vol_min)
		next = vol_min;
	if (next == cur)
		return;
	if (snd_mixer_selem_set_playback_volume_all(master, next) < 0) {
		fprintf(stderr, "relicos-joypad: mixer set: failed\n");
		return;
	}
	/* Remembered for S30audio; /data may be missing on a bench card. */
	write_int(VOLUME_SAVE, (int)next);
	if (verbose)
		fprintf(stderr, "volume: %ld -> %ld of %ld..%ld\n", cur, next, vol_min, vol_max);
}

static void emit(int ui, unsigned type, unsigned code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof ev);
	ev.type = type;
	ev.code = code;
	ev.value = value;
	if (write(ui, &ev, sizeof ev) != (ssize_t)sizeof ev)
		fprintf(stderr, "relicos-joypad: uinput write: %s\n", strerror(errno));
}

static void on_signal(int sig)
{
	(void)sig;
	stopping = 1;
}

static void die(const char *what)
{
	fprintf(stderr, "relicos-joypad: %s: %s\n", what, strerror(errno));
	exit(1);
}

/* Open the evdev node whose EVIOCGNAME equals `name`, or return -1. */
static int find_source(const char *name)
{
	DIR *dir = opendir("/dev/input");
	struct dirent *ent;

	if (!dir)
		die("/dev/input");
	while ((ent = readdir(dir))) {
		char path[64], devname[80];
		int fd;

		if (strncmp(ent->d_name, "event", 5) != 0)
			continue;
		snprintf(path, sizeof path, "/dev/input/%s", ent->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof devname), devname) < 0)
			devname[0] = '\0';
		if (strcmp(devname, name) == 0) {
			closedir(dir);
			fprintf(stderr, "relicos-joypad: \"%s\" = %s\n", name, path);
			return fd;
		}
		close(fd);
	}
	closedir(dir);
	fprintf(stderr, "relicos-joypad: \"%s\": not found\n", name);
	return -1;
}

/* Copy the EV_KEY bits and the EV_ABS axes (with absinfo) of `src` onto
 * the uinput device being built on `ui`. Counts what it copied. */
static void copy_caps(int ui, int src, int *nkeys, int *naxes)
{
	unsigned long keys[BITS_TO_LONGS(KEY_MAX + 1)];
	unsigned long axes[BITS_TO_LONGS(ABS_MAX + 1)];
	int code;

	memset(keys, 0, sizeof keys);
	memset(axes, 0, sizeof axes);
	/* A device without a type answers with an empty mask, not an error. */
	ioctl(src, EVIOCGBIT(EV_KEY, sizeof keys), keys);
	ioctl(src, EVIOCGBIT(EV_ABS, sizeof axes), axes);

	for (code = 0; code <= KEY_MAX; code++) {
		if (!TEST_BIT(code, keys))
			continue;
		if (ioctl(ui, UI_SET_KEYBIT, code) < 0)
			die("UI_SET_KEYBIT");
		(*nkeys)++;
	}
	for (code = 0; code <= ABS_MAX; code++) {
		struct uinput_abs_setup abs;

		if (!TEST_BIT(code, axes))
			continue;
		memset(&abs, 0, sizeof abs);
		abs.code = code;
		if (ioctl(src, EVIOCGABS(code), &abs.absinfo) < 0)
			die("EVIOCGABS");
		/* The rest position is the current value; see "The sticks". */
		axis_cal[code].present = 1;
		axis_cal[code].min  = abs.absinfo.minimum;
		axis_cal[code].max  = abs.absinfo.maximum;
		axis_cal[code].rest = abs.absinfo.value;
		fprintf(stderr, "relicos-joypad: axis %d: rest %d in %d..%d "
			"(%+.1f%% of the half-travel), centred\n", code,
			abs.absinfo.value, abs.absinfo.minimum, abs.absinfo.maximum,
			(abs.absinfo.maximum > abs.absinfo.minimum) ?
			100.0 * (abs.absinfo.value - (abs.absinfo.minimum + abs.absinfo.maximum) / 2.0) /
			((abs.absinfo.maximum - abs.absinfo.minimum) / 2.0) : 0.0);
		abs.absinfo.value = 0;
		abs.absinfo.minimum = -AXIS_OUT_MAX;
		abs.absinfo.maximum = AXIS_OUT_MAX;
		abs.absinfo.fuzz = 0;
		abs.absinfo.flat = 0;
		abs.absinfo.resolution = 0;
		if (ioctl(ui, UI_SET_ABSBIT, code) < 0)
			die("UI_SET_ABSBIT");
		if (ioctl(ui, UI_ABS_SETUP, &abs) < 0)
			die("UI_ABS_SETUP");
		(*naxes)++;
	}
}

static int create_output(int keys_fd, int axes_fd)
{
	struct uinput_setup setup;
	char sysname[64];
	int ui, nkeys = 0, naxes = 0;

	ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (ui < 0)
		die("/dev/uinput");
	/* EV_SYN comes for free from the input core. No EV_REP: the kernel
	 * would synthesise autorepeat on a gamepad. No EV_MSC (scancodes). */
	if (ioctl(ui, UI_SET_EVBIT, EV_KEY) < 0 ||
	    ioctl(ui, UI_SET_EVBIT, EV_ABS) < 0)
		die("UI_SET_EVBIT");
	copy_caps(ui, keys_fd, &nkeys, &naxes);
	copy_caps(ui, axes_fd, &nkeys, &naxes);

	memset(&setup, 0, sizeof setup);
	setup.id.bustype = BUS_VIRTUAL;
	setup.id.vendor  = OUT_VENDOR;
	setup.id.product = OUT_PRODUCT;
	setup.id.version = OUT_VERSION;
	strncpy(setup.name, OUT_NAME, UINPUT_MAX_NAME_SIZE - 1);
	if (ioctl(ui, UI_DEV_SETUP, &setup) < 0)
		die("UI_DEV_SETUP");
	if (ioctl(ui, UI_DEV_CREATE) < 0)
		die("UI_DEV_CREATE");
	if (ioctl(ui, UI_GET_SYSNAME(sizeof sysname), sysname) < 0)
		strcpy(sysname, "?");
	fprintf(stderr, "relicos-joypad: created \"%s\" as %s (%d keys, %d axes)\n",
		OUT_NAME, sysname, nkeys, naxes);
	return ui;
}

/* The FN modifier: returns 1 when the event was consumed (not forwarded).
 * `ui` is the gamepad, where the synthetic tap goes. */
static int handle_fn(int ui, const struct input_event *ev)
{
	if (ev->type != EV_KEY || ev->code != BTN_MODE)
		return 0;
	if (ev->value == 1) {
		fn_down = 1;
		fn_used = 0;
		return 1;
	}
	if (ev->value == 0) {
		fn_down = 0;
		if (!fn_used && !fn_release_at) {
			emit(ui, EV_KEY, BTN_MODE, 1);
			emit(ui, EV_SYN, SYN_REPORT, 0);
			fn_release_at = now_ms() + FN_TAP_MS;
			if (verbose)
				fprintf(stderr, "fn: tap\n");
		}
		return 1;
	}
	return 1; /* a repeat, which gpio-keys never sends */
}

/* The volume keys never leave the daemon: alone they are the volume,
 * with FN the brightness. A key that went down under FN keeps meaning
 * brightness for its repeats even if FN is lifted first. */
static void handle_vol(const struct input_event *ev)
{
	int idx;

	if (ev->type != EV_KEY)
		return;
	if (ev->code == KEY_VOLUMEUP)
		idx = 1;
	else if (ev->code == KEY_VOLUMEDOWN)
		idx = 0;
	else
		return;
	if (ev->value == 0) {
		vol_swallowed[idx] = 0;
		return;
	}
	/* press (1) or repeat (2) */
	if (fn_down || (ev->value == 2 && vol_swallowed[idx])) {
		fn_used = 1;
		vol_swallowed[idx] = 1;
		step_brightness(idx ? +1 : -1);
	} else {
		step_volume(idx ? +1 : -1);
	}
}

/* Run relicos-suspend in a child and return at once. SIGCHLD is ignored
 * (main), so the child is reaped by the kernel; the evdev, uinput and
 * mixer descriptors are O_CLOEXEC, the child inherits only the console. */
static void run_suspend(void)
{
	pid_t pid = fork();

	if (pid < 0) {
		fprintf(stderr, "relicos-joypad: fork: %s\n", strerror(errno));
		return;
	}
	if (pid == 0) {
		execl(SUSPEND_CMD, "relicos-suspend", (char *)NULL);
		fprintf(stderr, "relicos-joypad: %s: %s\n", SUSPEND_CMD, strerror(errno));
		_exit(127);
	}
}

/* The power key never leaves the daemon: a short tap asks for sleep on
 * the release, a hold does nothing here (the PMIC owns the hold). */
static void handle_pwr(const struct input_event *ev)
{
	long held;

	if (ev->type != EV_KEY || ev->code != KEY_POWER)
		return;
	if (ev->value == 1) {
		pwr_down_at = now_ms();
		return;
	}
	if (ev->value != 0)
		return; /* a repeat: the driver sends none, but be explicit */
	if (!pwr_down_at)
		return; /* a release without a press: seen after a resume */
	held = now_ms() - pwr_down_at;
	pwr_down_at = 0;
	if (held > PWR_TAP_MAX_MS) {
		fprintf(stderr, "relicos-joypad: power held %ld ms, ignored\n", held);
		return;
	}
	fprintf(stderr, "relicos-joypad: power tap (%ld ms) -> %s\n", held, SUSPEND_CMD);
	run_suspend();
}

/* One raw axis value to the output range: 0 at rest and through the dead
 * zone, then linear to the edge on that side. See "The sticks". */
static int scale_axis(unsigned code, int value)
{
	int rest, span, d, dz, out;

	if (code > ABS_MAX || !axis_cal[code].present)
		return value;
	rest = axis_cal[code].rest;
	d = value - rest;
	span = d < 0 ? rest - axis_cal[code].min : axis_cal[code].max - rest;
	if (span <= 0)
		return 0;
	dz = span * AXIS_DEADZONE / 100;
	if (d > -dz && d < dz)
		return 0;
	out = (int)((long)((d < 0 ? -d : d) - dz) * AXIS_OUT_MAX / (span - dz));
	if (out > AXIS_OUT_MAX)
		out = AXIS_OUT_MAX;
	return d < 0 ? -out : out;
}

/* Forward the pending events of `fd` to the gamepad `ui`; the volume-key
 * and power-key sources are consumed here instead. */
static void forward(int ui, int fd, int src)
{
	const char *tag = src_name[src];
	struct input_event ev[64];
	ssize_t n;
	size_t i;

	n = read(fd, ev, sizeof ev);
	if (n < 0) {
		if (errno == EAGAIN || errno == EINTR)
			return;
		fprintf(stderr, "relicos-joypad: read %s: %s\n", tag, strerror(errno));
		stopping = 1;
		return;
	}
	for (i = 0; i < (size_t)n / sizeof ev[0]; i++) {
		if (ev[i].type != EV_KEY && ev[i].type != EV_ABS &&
		    ev[i].type != EV_SYN)
			continue;
		if (verbose)
			fprintf(stderr, "%s: type %u code %u value %d\n",
				tag, ev[i].type, ev[i].code, ev[i].value);
		if (src == SRC_VOL) {
			handle_vol(&ev[i]);
			continue;
		}
		if (src == SRC_PWR) {
			handle_pwr(&ev[i]);
			continue;
		}
		if (handle_fn(ui, &ev[i]))
			continue;
		if (ev[i].type == EV_ABS)
			ev[i].value = scale_axis(ev[i].code, ev[i].value);
		if (write(ui, &ev[i], sizeof ev[i]) != (ssize_t)sizeof ev[i])
			fprintf(stderr, "relicos-joypad: uinput write: %s\n",
				strerror(errno));
	}
}

static void write_pidfile(void)
{
	FILE *f = fopen(PIDFILE, "w");

	if (!f)
		return;
	fprintf(f, "%d\n", (int)getpid());
	fclose(f);
}

int main(int argc, char **argv)
{
	struct sigaction sa;
	struct pollfd pfd[SRC_COUNT];
	int foreground = 0, keys_fd, axes_fd, vol_fd, pwr_fd, ui, nfds, i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-f") == 0)
			foreground = 1;
		else if (strcmp(argv[i], "-v") == 0)
			verbose = foreground = 1;
		else {
			fprintf(stderr, "usage: relicos-joypad [-f] [-v]\n");
			return 2;
		}
	}

	keys_fd = find_source(KEYS_NAME);
	axes_fd = find_source(AXES_NAME);
	if (keys_fd < 0 || axes_fd < 0)
		return 1;
	if (ioctl(keys_fd, EVIOCGRAB, 1) < 0 || ioctl(axes_fd, EVIOCGRAB, 1) < 0)
		die("EVIOCGRAB");
	ui = create_output(keys_fd, axes_fd);

	/* The volume keys are optional: without them the pad still fuses,
	 * there is just no volume and no brightness from the buttons. */
	vol_fd = find_source(VOL_NAME);
	if (vol_fd >= 0) {
		if (ioctl(vol_fd, EVIOCGRAB, 1) < 0)
			die("EVIOCGRAB");
		find_backlight();
	}

	/* The power key is optional too (a kernel without rk805-pwrkey has
	 * no such device): the pad still fuses, the button just stays with
	 * the PMIC. */
	pwr_fd = find_source(PWR_NAME);
	if (pwr_fd >= 0 && ioctl(pwr_fd, EVIOCGRAB, 1) < 0)
		die("EVIOCGRAB");

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	/* relicos-suspend children are never waited for: let the kernel
	 * reap them (SIG_IGN on SIGCHLD does that on Linux). */
	signal(SIGCHLD, SIG_IGN);

	/* Detach only now: the device exists, the evidence is on the console.
	 * noclose=1 keeps stderr on the console for anything said later. */
	if (!foreground && daemon(0, 1) < 0)
		die("daemon");
	write_pidfile();

	/* Sources that are missing get fd -1, which poll() skips; nfds spans
	 * the last one present so the tag lookup stays index-based. */
	pfd[SRC_KEYS].fd = keys_fd;
	pfd[SRC_AXES].fd = axes_fd;
	pfd[SRC_VOL].fd  = vol_fd;
	pfd[SRC_PWR].fd  = pwr_fd;
	for (i = 0; i < SRC_COUNT; i++)
		pfd[i].events = POLLIN;
	nfds = pwr_fd >= 0 ? SRC_COUNT : vol_fd >= 0 ? SRC_VOL + 1 : SRC_AXES + 1;
	while (!stopping) {
		int timeout = -1;

		if (fn_release_at) {
			long left = fn_release_at - now_ms();

			timeout = left > 0 ? (int)left : 0;
		}
		if (poll(pfd, nfds, timeout) < 0) {
			if (errno == EINTR)
				continue;
			die("poll");
		}
		if (fn_release_at && now_ms() >= fn_release_at) {
			emit(ui, EV_KEY, BTN_MODE, 0);
			emit(ui, EV_SYN, SYN_REPORT, 0);
			fn_release_at = 0;
		}
		for (i = 0; i < nfds; i++) {
			if (pfd[i].fd < 0)
				continue;
			if (pfd[i].revents & (POLLERR | POLLHUP)) {
				fprintf(stderr, "relicos-joypad: %s went away\n", src_name[i]);
				stopping = 1;
			}
			if (pfd[i].revents & POLLIN)
				forward(ui, pfd[i].fd, i);
		}
	}

	ioctl(ui, UI_DEV_DESTROY);
	close(ui);
	if (mixer)
		snd_mixer_close(mixer);
	if (pwr_fd >= 0) {
		ioctl(pwr_fd, EVIOCGRAB, 0);
		close(pwr_fd);
	}
	if (vol_fd >= 0) {
		ioctl(vol_fd, EVIOCGRAB, 0);
		close(vol_fd);
	}
	ioctl(keys_fd, EVIOCGRAB, 0);
	ioctl(axes_fd, EVIOCGRAB, 0);
	close(keys_fd);
	close(axes_fd);
	unlink(PIDFILE);
	fprintf(stderr, "relicos-joypad: stopped\n");
	return 0;
}
