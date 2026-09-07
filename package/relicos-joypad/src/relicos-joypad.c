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
 *   3. create one uinput device, "RelicOS Gamepad", carrying exactly the
 *      key bits of gpio-keys and the axes of adc-joystick, with each
 *      axis's absinfo (min/max/fuzz/flat) copied verbatim -- that is what
 *      lets consumers normalise the raw SARADC range correctly;
 *   4. forward every EV_KEY/EV_ABS/EV_SYN event unchanged, one SYN_REPORT
 *      per source SYN, so a stick frame or a key frame stays atomic.
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
 * autorepeat). It is grabbed too and re-emitted as a second uinput
 * device, "RelicOS Keys", so RetroArch keeps seeing them as the keyboard
 * keys its volume hotkeys are bound to -- except while FN is held: then
 * VOL+/VOL- step the panel backlight instead (/sys/class/backlight, one
 * step = 5 % of max_brightness, repeat while held, never below 5 %), and
 * neither key reaches anyone. That makes FN a modifier, and a modifier
 * cannot be delivered on press (RetroArch opens its menu on FN): FN is
 * held back while down and, if no VOL key was used meanwhile, delivered
 * on release as a short synthetic tap -- pressed for FN_TAP_MS, long
 * enough for a consumer that samples once a frame to see it down. Each
 * change is also written to /data/system/brightness, which S01backlight
 * restores at boot.
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

#define KEYS_NAME   "gpio-keys"
#define AXES_NAME   "adc-joystick"
#define VOL_NAME    "gpio-keys-vol"
#define OUT_NAME    "RelicOS Gamepad"
#define KBD_NAME    "RelicOS Keys"
#define OUT_VENDOR  0x5245   /* "RE" */
#define OUT_PRODUCT 0x0036   /* R36S */
#define KBD_PRODUCT 0x0037
#define OUT_VERSION 0x0001
#define PIDFILE     "/var/run/relicos-joypad.pid"

#define BACKLIGHT_CLASS "/sys/class/backlight"
#define BRIGHTNESS_SAVE "/data/system/brightness"
#define FN_TAP_MS       40   /* the synthetic FN press stays down this long */
#define STEP_DIV        20   /* one VOL step = max_brightness / 20 = 5 % */
#define FLOOR_DIV       20   /* never below max_brightness / 20 */
#define STEP_MIN_MS     80   /* autorepeat is faster than the eye */

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
static char bl_brightness[128], bl_max[128];
static int bl_max_value;

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
		if (ioctl(ui, UI_SET_ABSBIT, code) < 0)
			die("UI_SET_ABSBIT");
		if (ioctl(ui, UI_ABS_SETUP, &abs) < 0)
			die("UI_ABS_SETUP");
		(*naxes)++;
	}
}

/* One uinput device named `name` carrying the caps of the given sources
 * (axes_fd may be -1). */
static int create_output(const char *name, int product, int keys_fd, int axes_fd)
{
	struct uinput_setup setup;
	char sysname[64];
	int ui, nkeys = 0, naxes = 0;

	ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (ui < 0)
		die("/dev/uinput");
	/* EV_SYN comes for free from the input core. No EV_REP: the kernel
	 * would synthesise autorepeat on a gamepad, and the volume keys carry
	 * their source's own repeats (value 2 passes through). No EV_MSC. */
	if (ioctl(ui, UI_SET_EVBIT, EV_KEY) < 0 ||
	    (axes_fd >= 0 && ioctl(ui, UI_SET_EVBIT, EV_ABS) < 0))
		die("UI_SET_EVBIT");
	copy_caps(ui, keys_fd, &nkeys, &naxes);
	if (axes_fd >= 0)
		copy_caps(ui, axes_fd, &nkeys, &naxes);

	memset(&setup, 0, sizeof setup);
	setup.id.bustype = BUS_VIRTUAL;
	setup.id.vendor  = OUT_VENDOR;
	setup.id.product = product;
	setup.id.version = OUT_VERSION;
	strncpy(setup.name, name, UINPUT_MAX_NAME_SIZE - 1);
	if (ioctl(ui, UI_DEV_SETUP, &setup) < 0)
		die("UI_DEV_SETUP");
	if (ioctl(ui, UI_DEV_CREATE) < 0)
		die("UI_DEV_CREATE");
	if (ioctl(ui, UI_GET_SYSNAME(sizeof sysname), sysname) < 0)
		strcpy(sysname, "?");
	fprintf(stderr, "relicos-joypad: created \"%s\" as %s (%d keys, %d axes)\n",
		name, sysname, nkeys, naxes);
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

/* The volume keys: returns 1 when the event was consumed. */
static int handle_vol(const struct input_event *ev)
{
	int idx;

	if (ev->type != EV_KEY)
		return 0;
	if (ev->code == KEY_VOLUMEUP)
		idx = 1;
	else if (ev->code == KEY_VOLUMEDOWN)
		idx = 0;
	else
		return 0;
	if (ev->value == 0) {
		if (!vol_swallowed[idx])
			return 0;
		vol_swallowed[idx] = 0;
		return 1;
	}
	/* press (1) or repeat (2) */
	if (fn_down || (ev->value == 2 && vol_swallowed[idx])) {
		fn_used = 1;
		vol_swallowed[idx] = 1;
		step_brightness(idx ? +1 : -1);
		return 1;
	}
	return 0;
}

/* Forward the pending events of `fd` to `ui`. `pad` is the gamepad uinput
 * (where a synthetic FN tap goes); `is_vol` marks the volume-key source. */
static void forward(int ui, int pad, int fd, const char *tag, int is_vol)
{
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
		if (is_vol ? handle_vol(&ev[i]) : handle_fn(pad, &ev[i]))
			continue;
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
	struct pollfd pfd[3];
	int foreground = 0, keys_fd, axes_fd, vol_fd, ui, kbd = -1, nfds, i;

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
	ui = create_output(OUT_NAME, OUT_PRODUCT, keys_fd, axes_fd);

	/* The volume keys are optional: without them the pad still fuses,
	 * there is just no shortcut and no "RelicOS Keys". */
	vol_fd = find_source(VOL_NAME);
	if (vol_fd >= 0) {
		if (ioctl(vol_fd, EVIOCGRAB, 1) < 0)
			die("EVIOCGRAB");
		kbd = create_output(KBD_NAME, KBD_PRODUCT, vol_fd, -1);
		find_backlight();
	}

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	/* Detach only now: the device exists, the evidence is on the console.
	 * noclose=1 keeps stderr on the console for anything said later. */
	if (!foreground && daemon(0, 1) < 0)
		die("daemon");
	write_pidfile();

	pfd[0].fd = keys_fd; pfd[0].events = POLLIN;
	pfd[1].fd = axes_fd; pfd[1].events = POLLIN;
	pfd[2].fd = vol_fd;  pfd[2].events = POLLIN;
	nfds = vol_fd >= 0 ? 3 : 2;
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
			const char *tag = i == 0 ? KEYS_NAME : i == 1 ? AXES_NAME : VOL_NAME;

			if (pfd[i].revents & (POLLERR | POLLHUP)) {
				fprintf(stderr, "relicos-joypad: %s went away\n", tag);
				stopping = 1;
			}
			if (pfd[i].revents & POLLIN)
				forward(i == 2 ? kbd : ui, ui, pfd[i].fd, tag, i == 2);
		}
	}

	ioctl(ui, UI_DEV_DESTROY);
	close(ui);
	if (kbd >= 0) {
		ioctl(kbd, UI_DEV_DESTROY);
		close(kbd);
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
