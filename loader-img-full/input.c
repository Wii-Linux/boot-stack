#include <stdlib.h>
#include <unistd.h>
#include "timer.h"
#include "menu.h"
#include "items.h"
#include "cleanup.h"
#include "boot.h"

#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <termios.h>
#include <time.h>

#include "input.h"
#include "state.h"
#include "menu.h"
#include "screen.h"

static int controllerFd;

static int kbdFds[MAX_KBD_DEVICES];
static int numKbdFds = 0;
static struct pollfd fds[1 + MAX_KBD_DEVICES];
/* static char kbdBuf[128]; */
static struct termios oldTerm;

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


int INPUT_Init(void) {
	struct dirent *dp;
	DIR *dir;
	struct termios newTerm;

	controllerFd = open(CONTROLLER_DEVICE, O_RDONLY);
	if (controllerFd < 0) {
		perror("Error opening controller device");
		return 1;
	}

	/* Set up poll structs for power and volume buttons and the touchscreen */
	fds[0].fd = controllerFd;
	fds[0].events = POLLIN;

	while ((dp = readdir(dir)) != NULL) {
		if (strncmp(dp->d_name, "event", 5) == 0) {
			char fullpath[268]; /* d_name is 256 bytes */
			sprintf(fullpath, "/dev/input/%s", dp->d_name);

			if (isKeyboard(fullpath) && numKbdFds < MAX_KBD_DEVICES) {
				int fd = open(fullpath, O_RDONLY | O_NONBLOCK);
				if (fd >= 0) {
					kbdFds[numKbdFds++] = fd;
					fds[numKbdFds].fd = fd;
					fds[numKbdFds].events = POLLIN;
				}
			}
		}
	}
	closedir(dir);


	/* save old terminal info */
	tcgetattr(STDIN_FILENO, &oldTerm);

	/* set it up so we can properly recieve arrow keys properly without needing a newline */
	/* breaks volume buttons??? */
	newTerm = oldTerm;
	newTerm.c_lflag &= ~(ICANON | ECHO);
	newTerm.c_cc[VMIN] = 1;
	newTerm.c_cc[VTIME] = 0;
	tcsetattr(STDIN_FILENO, TCSANOW, &newTerm);

	return 0;
}

void INPUT_Shutdown(void) {
	if (controllerFd >= 0) {
		close(touchFd);
	}

	/* restore old terminal settings */
	tcsetattr(STDIN_FILENO, TCSANOW, &oldTerm);
}

inputEvent_t INPUT_Check(void) {
	int ret, i;
	struct input_event ev;

	ret = poll(fds, 3 + numKbdFds, 30);  /* wait for up to 30ms */

	if (ret < 0) {
		perror("poll");
		return INPUT_TYPE_ERROR;
	}

	/* Check for events */
	if (fds[0].revents & POLLIN) {
		read(pwrButtonFd, &ev, sizeof(ev));

		#ifdef INPUT_DEBUG
		printf("Event from controller: type=%d code=%d value=%d\n", ev.type, ev.code, ev.value);
		#endif

		if (ev.code == KEY_SLEEP && ev.value == 1) {
			return INPUT_TYPE_SELECT;
		}
	}

	for (i = 1; i < MAX_KBD_DEVICES; i++) {
		if (fds[i].revents & POLLIN) {
			read(kbdFds[i - 2], &ev, sizeof(ev));

			#ifdef INPUT_DEBUG
			printf("Event from keyboard: type=%d code=%d value=%d\n", ev.type, ev.code, ev.value);
			#endif

			if (ev.value == 1 && (ev.code == KEY_DOWN || ev.code == KEY_UP || ev.code == KEY_ENTER)) {
				if (ev.code == KEY_DOWN) return INPUT_TYPE_DOWN;
				if (ev.code == KEY_UP) return INPUT_TYPE_UP;
				if (ev.code == KEY_ENTER) return INPUT_TYPE_SELECT;
				if (ev.code == KEY_R) return INPUT_TYPE_RECOVERY;
			}
		}
	}

	return INPUT_TYPE_NONE;
}
