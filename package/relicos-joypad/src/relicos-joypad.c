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
#include <linux/input.h>
#include <linux/uinput.h>

#define KEYS_NAME   "gpio-keys"
#define AXES_NAME   "adc-joystick"
#define OUT_NAME    "RelicOS Gamepad"
#define OUT_VENDOR  0x5245   /* "RE" */
#define OUT_PRODUCT 0x0036   /* R36S */
#define OUT_VERSION 0x0001
#define PIDFILE     "/var/run/relicos-joypad.pid"

#define LONG_BITS       (8 * sizeof(unsigned long))
#define BITS_TO_LONGS(n) (((n) + LONG_BITS - 1) / LONG_BITS)
#define TEST_BIT(bit, arr) \
	(((arr)[(bit) / LONG_BITS] >> ((bit) % LONG_BITS)) & 1UL)

static volatile sig_atomic_t stopping;
static int verbose;

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

static void forward(int ui, int fd, const char *tag)
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
	struct pollfd pfd[2];
	int foreground = 0, keys_fd, axes_fd, ui, i;

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
	while (!stopping) {
		if (poll(pfd, 2, -1) < 0) {
			if (errno == EINTR)
				continue;
			die("poll");
		}
		for (i = 0; i < 2; i++) {
			if (pfd[i].revents & (POLLERR | POLLHUP)) {
				fprintf(stderr, "relicos-joypad: %s went away\n",
					i ? AXES_NAME : KEYS_NAME);
				stopping = 1;
			}
			if (pfd[i].revents & POLLIN)
				forward(ui, pfd[i].fd, i ? AXES_NAME : KEYS_NAME);
		}
	}

	ioctl(ui, UI_DEV_DESTROY);
	close(ui);
	ioctl(keys_fd, EVIOCGRAB, 0);
	ioctl(axes_fd, EVIOCGRAB, 0);
	close(keys_fd);
	close(axes_fd);
	unlink(PIDFILE);
	fprintf(stderr, "relicos-joypad: stopped\n");
	return 0;
}
