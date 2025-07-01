#include "include.h"
#include "boot.h"
#include "bottom.h"
#include "menu.h"
#include "timer.h"
#include "term.h"
#include "main.h"
#include "args.h"
#include "dev.h"
#include "items.h"
#include "input.h"

static struct termios oldt;
bool ARGS_IsPPCDroid;
int MAIN_LoopIters = 0;
#if defined(DEBUG_WII) || defined(DEBUG_PC)
FILE *logfile;
#endif

void doCleanup() {
	printf("\e[?25h");
	tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
}

int main() {
	char bdevs   [MAX_BDEV][MAX_BDEV_CHAR];
	char bdevsOld[MAX_BDEV][MAX_BDEV_CHAR];
	char added   [MAX_BDEV][MAX_BDEV_CHAR];
	char removed [MAX_BDEV][MAX_BDEV_CHAR];
	struct utsname tmp;
	struct timeval start_time, current_time;
	inputEvent_t ev;

	// XXX: HACK!  Somehow, and I have absolutely no damned idea how,
	// uClibc botches argument handling!  argc turns into argv, and
	// argv turns into envp.
	//
	// I have absolutely no idea how this is possible, but no
	// matter what I've tried, that's the result I've gotten.
	// So working around it here by manually checking
	// if we're a PPCDroid kernel or not.
	uname(&tmp);

	// null if no match, thus not PPCDroid kernel, and evaluating to false
	// non-null if match found, thus true
	ARGS_IsPPCDroid = (strstr(tmp.release, "ppcdroid") != NULL);

	TERM_Init(&oldt);

	#if defined(DEBUG_WII) || defined(DEBUG_PC)
	logfile = fopen("log.txt", "w+");
	if (logfile == NULL) {
		fprintf(stderr, "Couldn't open logfile: %s\r\n", strerror(errno));
		exit(1);
	}
	#endif

	INPUT_Init();


	for (int i = 0; i != MAX_BDEV; i++) {
		bzero(bdevs   [i], MAX_BDEV_CHAR);
		bzero(bdevsOld[i], MAX_BDEV_CHAR);
		bzero(added   [i], MAX_BDEV_CHAR);
		bzero(removed [i], MAX_BDEV_CHAR);
	}
	strcpy(bdevs[0], "dummy0");
	strcpy(bdevsOld[0], "dummy0");


	TERM_DoResize(0);
	BOTTOM_Init();

	gettimeofday(&start_time, NULL);

	TIMER_Pause();

	while (true) {
		MAIN_LoopIters++;
		if (!TIMER_Paused) {
			TIMER_TicksRemaining--;
		}

		if (MAIN_LoopIters % 15 == 0 || MAIN_LoopIters == 1) {
			int i = 0;
			DEV_Detect(bdevs);

			if (strcmp(bdevs[0], "dummy0") == 0) {
				fprintf(stderr, "\e[1;31minternal error - DEV_Detect() failed\e[0m\r\n");
				exit(1);
			}

			// compare with bdevsOld
			DEV_Compare(bdevs, bdevsOld, added, removed);

			while (added[i][0] != '\0') {
				DEV_Scan(added[i]);

				ev = -2;
				while (ev != INPUT_TYPE_NONE) {
					ev = INPUT_Handle();
					fprintf(logfile, "INPUT_Handle() returned, ev: %d, MENU_NeedRedraw: %d\n", ev, MENU_NeedRedraw);
				}

				MENU_Redraw(true, true);
				i++;
			}

			i = 0;

			while (removed[i][0] != '\0') {
				ITEM_RemoveByBdev(removed[i]);
				i++;
				// don't waste time checking for inputs or redrawing the menu.
				// removal takes next to no time.
			}
			if (i != 0) {
				// we removed stuff
				MENU_Redraw(true, true);
			}

			memcpy(bdevsOld, bdevs, sizeof(bdevs));
		}

		if (MAIN_LoopIters % 5 == 0) {
			TIMER_Redraw();
		}
		if (TIMER_TicksRemaining == 0 && !TIMER_Stopped) {
			BOOT_Go();
		}

		ev = -2;
		while (ev != INPUT_TYPE_NONE) {
			ev = INPUT_Handle();
			fprintf(logfile, "INPUT_Handle() returned, ev: %d, MENU_NeedRedraw: %d\n", ev, MENU_NeedRedraw);
		}

		if (MENU_NeedRedraw) {
			MENU_Redraw(true, false);
			MENU_NeedRedraw = false;
		}

		// Calculate elapsed time and sleep to maintain 30 iterations per second
		gettimeofday(&current_time, NULL);
		long seconds = current_time.tv_sec - start_time.tv_sec;
		long microseconds = current_time.tv_usec - start_time.tv_usec;
		double elapsed = seconds + microseconds / 1000000.0;
		double interval = 1.0 / 30.0; // Desired interval in seconds
		double delay = interval - elapsed;

		if (delay > 0) {
			usleep(delay * 1000000); // Convert milliseconds to microseconds
		}

		start_time = current_time; // Update start time for next iteration
	}

	#if !defined(PROD_BUILD) && !defined(DEBUG_WII)
	cleanupAndExit(0);
	#endif
	return 0;
}
