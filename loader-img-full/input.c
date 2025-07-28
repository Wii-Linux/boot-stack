#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <linux/joystick.h>
#include <termios.h>
#include <time.h>

#include "include.h"
#include "menu.h"
#include "items.h"
#include "cleanup.h"
#include "boot.h"
#include "timer.h"
#include "input.h"


static int controllerFd;
static bool noController = false;

static int kbdFds[MAX_KBD_DEVICES];
static char kbdPaths[16][MAX_KBD_DEVICES];
static int numKbdFds = 0;
static int numKbdPaths = 0;
static struct pollfd fds[1 + MAX_KBD_DEVICES];

#define TEST_KEY(k) (keybits[(k)/8] & (1 << ((k)%8)))
static int isKeyboard(const char *devPath) {
	unsigned long evbits;
	unsigned char keybits[KEY_MAX/8 + 1];
	int fd = open(devPath, O_RDONLY);
	if (fd < 0) return 0;

	evbits = 0;
	if (ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), &evbits) < 0) {
		close(fd);
		return 0;
	}

	/* Must support EV_KEY */
	if (!(evbits & (1 << EV_KEY))) {
		close(fd);
		return 0;
	}


	memset(keybits, 0, sizeof(keybits));
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0) {
		close(fd);
		return 0;
	}

	if (TEST_KEY(KEY_A) && TEST_KEY(KEY_ENTER)) {
		close(fd);
		return 1;  /* looks like a keyboard */
	}

	close(fd);
	return 0;
}

static void INPUT_CheckNewKbds(void) {
	struct dirent *dp;
	DIR *dir;

	/* check for keyboards */
	dir = opendir("/dev/input");

	while ((dp = readdir(dir)) != NULL) {
		bool skip = false;
		if (strncmp(dp->d_name, "event", 5) == 0) {
			char fullpath[268]; /* d_name is 256 bytes */
			int i;
			for (i = 0; i != numKbdPaths; i++) {
				if (strncmp(dp->d_name, kbdPaths[i], 15) == 0) {
					skip = true; // we already know this one
					break;
				}
			}
			if (skip) continue;

			sprintf(fullpath, "/dev/input/%s", dp->d_name);

			fprintf(logfile, "Checking if %s is a keyboard\n", fullpath);
			if (isKeyboard(fullpath) && numKbdFds < MAX_KBD_DEVICES) {
				fprintf(logfile, "It is\n");
				int fd = open(fullpath, O_RDONLY | O_NONBLOCK);
				if (fd >= 0) {
					kbdFds[numKbdFds++] = fd;
					fds[numKbdFds].fd = fd;
					fds[numKbdFds].events = POLLIN;
					ioctl(fd, EVIOCGRAB, 1); /* grab exclusive access to the device */
				}
			}
			else {
				fprintf(logfile, "It is NOT\n");
			}

			strncpy(kbdPaths[numKbdPaths], dp->d_name, 15);
			numKbdPaths++;
		}
	}
	closedir(dir);
}


int INPUT_Init(void) {
	struct js_event js_ev;

	controllerFd = open(CONTROLLER_DEVICE, O_RDONLY);
	if (controllerFd < 0) {
		perror("Error opening controller device");
		// this is nonfatal, the user might just
		// not have a GCN controller
		noController = true;
	}

	/* Set up poll structs for the controller and keyboards */
	if (!noController) {
		fds[0].fd = controllerFd;
		fds[0].events = POLLIN;

		// flush out it's starting input
		while (true) {
			poll(fds, 1, 10);
			if (fds[0].revents & POLLIN)
				read(controllerFd, &js_ev, sizeof(js_ev));
			else
				break;
		}
	}

	INPUT_CheckNewKbds();
	return 0;
}

void INPUT_Shutdown(void) {
	if (controllerFd >= 0) {
		close(controllerFd);
	}
}

static inputEvent_t INPUT_Check(void) {
	int ret, i, keepGoing;
	struct input_event ev;
	struct js_event js_ev;

	keepGoing = 1;

	while (keepGoing) {
		keepGoing = 0; // break unless all we got was a release
		ret = poll(fds, 1 + numKbdFds, 30);  /* wait for up to 30ms */

		if (ret < 0) {
			perror("poll");
			return INPUT_TYPE_ERROR;
		}

		/* Check for events */
		if (!noController && fds[0].revents & POLLIN) {
			read(controllerFd, &js_ev, sizeof(js_ev));

			fprintf(logfile, "Event from controller: type=%u number=%u value=%d\n", js_ev.type, js_ev.number, js_ev.value);

			if (js_ev.type == JS_EVENT_BUTTON &&
			    js_ev.number == 0 /* A button */ &&
			    js_ev.value == 1 /* pressed */)
				return INPUT_TYPE_SELECT;

			if (js_ev.type == JS_EVENT_BUTTON &&
			    js_ev.number == 2 /* X button */ &&
			    js_ev.value == 1 /* pressed */)
				return INPUT_TYPE_RECOVERY;

			if (js_ev.type == JS_EVENT_AXIS &&
			    js_ev.number == 7 /* D-Pad Up/Down */ &&
			    js_ev.value == -32767 /* Up */)
				return INPUT_TYPE_UP;

			if (js_ev.type == JS_EVENT_AXIS &&
			    js_ev.number == 7 /* D-Pad Up/Down */ &&
			    js_ev.value == 32767 /* Down */)
				return INPUT_TYPE_DOWN;

			// we got something, but it was probably a release
			keepGoing = 1;
		}

		for (i = 1; i < MAX_KBD_DEVICES; i++) {
			if (fds[i].revents & POLLIN) {
				read(kbdFds[i - 1], &ev, sizeof(ev));

				fprintf(logfile, "Event from keyboard: type=%d code=%d value=%d\n", ev.type, ev.code, ev.value);

				if (ev.value == 1 && (ev.code == KEY_DOWN || ev.code == KEY_UP || ev.code == KEY_ENTER || ev.code == KEY_R)) {
					if (ev.code == KEY_DOWN) return INPUT_TYPE_DOWN;
					if (ev.code == KEY_UP) return INPUT_TYPE_UP;
					if (ev.code == KEY_ENTER) return INPUT_TYPE_SELECT;
					if (ev.code == KEY_R) return INPUT_TYPE_RECOVERY;
				}


				// we got something, but it was probably a release
				keepGoing = 1;
			}
		}
	}
	return INPUT_TYPE_NONE;
}

inputEvent_t INPUT_Handle(void) {
	INPUT_CheckNewKbds();
	inputEvent_t ret = INPUT_Check();
	switch (ret) {
		case INPUT_TYPE_RECOVERY: {
			// exiting with status 2 causes init to spawn a recovery shell, and
			// when exited, restart boot_menu.
			doCleanup();
			exit(2);
			break;
		}
		case INPUT_TYPE_SELECT: {
			BOOT_Go();
			break;
		}
		case INPUT_TYPE_UP: {
			if (MENU_Selected > 0) {
				MENU_LastSelected = MENU_Selected;
				MENU_Selected--;
				MENU_NeedFullRedraw = false;
				MENU_NeedRedraw = true;
			}
			break;
		}
		case INPUT_TYPE_DOWN: {
			if (MENU_Selected < ITEM_NumItems - 1) {
				MENU_LastSelected = MENU_Selected;
				MENU_Selected++;
				MENU_NeedFullRedraw = false;
				MENU_NeedRedraw = true;
			}
			break;
		}
		case INPUT_TYPE_ERROR:
		case INPUT_TYPE_NONE:
			break;
	}
	if (ret != INPUT_TYPE_NONE) {
		TIMER_Stop();
		fprintf(logfile, "Got real input!\n");
	}
	return ret;
}
