/* sdl2-diag: minimal SDL2 observability tool for RelicOS bring-up (M10).
 *
 * One question per line on stdout (the serial console): does KMSDRM video
 * come up, how many joysticks does SDL enumerate without udev, and are the
 * events sane. The blue rectangle on the panel is the second channel.
 *
 * Usage: sdl2-diag [seconds]   (default 15)
 */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	int secs = (argc > 1) ? atoi(argv[1]) : 15;

	SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1"); /* keep Ctrl+C usable */

	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) != 0) {
		fprintf(stderr, "SDL_Init(VIDEO|JOYSTICK): %s\n", SDL_GetError());
		/* the input floor is observable even with the video floor down */
		if (SDL_Init(SDL_INIT_JOYSTICK) != 0)
			return 1;
		printf("video: FAILED, continuing joystick-only\n");
	}

	if (SDL_WasInit(SDL_INIT_VIDEO)) {
		SDL_DisplayMode m;
		printf("video driver: %s\n", SDL_GetCurrentVideoDriver());
		if (SDL_GetCurrentDisplayMode(0, &m) == 0)
			printf("display mode: %dx%d @ %dHz\n", m.w, m.h, m.refresh_rate);
		SDL_Window *w = SDL_CreateWindow("sdl2-diag", 0, 0, 640, 480,
		                                 SDL_WINDOW_FULLSCREEN);
		if (!w) {
			printf("window: FAILED: %s\n", SDL_GetError());
		} else {
			SDL_Renderer *r = SDL_CreateRenderer(w, -1, 0);
			if (r) {
				SDL_SetRenderDrawColor(r, 0, 96, 160, 255);
				SDL_RenderClear(r);
				SDL_RenderPresent(r);
				printf("window: up (solid blue on the panel)\n");
			} else {
				printf("renderer: FAILED: %s\n", SDL_GetError());
			}
		}
	}

	int n = SDL_NumJoysticks();
	printf("joysticks: %d\n", n);
	for (int i = 0; i < n; i++) {
		SDL_Joystick *j = SDL_JoystickOpen(i);
		char guid[64];
		if (!j) {
			printf("  #%d: open failed: %s\n", i, SDL_GetError());
			continue;
		}
		SDL_JoystickGetGUIDString(SDL_JoystickGetGUID(j), guid, sizeof(guid));
		printf("  #%d: \"%s\" axes=%d buttons=%d hats=%d guid=%s\n", i,
		       SDL_JoystickName(j), SDL_JoystickNumAxes(j),
		       SDL_JoystickNumButtons(j), SDL_JoystickNumHats(j), guid);
	}

	printf("printing events for %ds...\n", secs);
	Uint32 end = SDL_GetTicks() + (Uint32)secs * 1000;
	SDL_Event e;
	while (SDL_GetTicks() < end) {
		while (SDL_PollEvent(&e)) {
			if (e.type == SDL_JOYAXISMOTION)
				printf("axis   joy=%d axis=%d value=%d\n",
				       e.jaxis.which, e.jaxis.axis, e.jaxis.value);
			else if (e.type == SDL_JOYBUTTONDOWN || e.type == SDL_JOYBUTTONUP)
				printf("button joy=%d button=%d %s\n", e.jbutton.which,
				       e.jbutton.button,
				       e.type == SDL_JOYBUTTONDOWN ? "down" : "up");
			else if (e.type == SDL_JOYDEVICEADDED)
				printf("device added: idx=%d\n", (int)e.jdevice.which);
		}
		SDL_Delay(10);
	}
	SDL_Quit();
	printf("sdl2-diag: clean exit\n");
	return 0;
}
