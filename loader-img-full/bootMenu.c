#include "include.h"
#include "bottom.h"
#include "items.h"
#include "menu.h"
#include "timer.h"
#include "term.h"
#include "main.h"
#include "args.h"
#include "dev.h"
#include "items.h"

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

static void BOOT_Go() {
    doCleanup();
    TIMER_Stop();
    BOTTOM_Destroy();
    char *bdev = items[MENU_Selected].bdevName;
    BOTTOM_Log("booting bdev %s\r\n", bdev);

    #if defined(PROD_BUILD) || defined(DEBUG_WII)
    int fd = open("/._bootdev", O_CREAT | O_WRONLY, 0777);
    if (fd == -1) {
        BOTTOM_Log("opening /._bootdev error: %s (%d)\r\n", strerror(errno), errno);
        exit(1);
    }
    write(fd, bdev, strlen(bdev));
    close(fd);
    BOTTOM_Log("Wrote /._bootdev, exiting with status 0 to tell init to go boot it\r\n");

    if (items[MENU_Selected].android) {
	    fd = open("/._isAndroid", O_CREAT | O_WRONLY, 0777);
	    if (fd == -1) {
		    BOTTOM_Log("openning /._isAndroid error: %s (%d)\r\n", strerror(errno), errno);
		    exit(1);
	    }

	    write(fd, "true", 4);
	    close(fd);
	    BOTTOM_Log("Wrote /._isAndroid to tell init that this is Android\r\n");
    }

    if (items[MENU_Selected].batocera) {
	    fd = open("/._isBatocera", O_CREAT | O_WRONLY, 0777);
	    if (fd == -1) {
		    BOTTOM_Log("openning /._isBatocera error: %s (%d)\r\n", strerror(errno), errno);
		    exit(1);
	    }

	    write(fd, "true", 4);
	    close(fd);
	    BOTTOM_Log("Wrote /._isBatocera to tell init that this is Batocera\r\n");
    }
    #endif

    exit(0);
}

int main() {
    char bdevs   [MAX_BDEV][MAX_BDEV_CHAR];
    char bdevsOld[MAX_BDEV][MAX_BDEV_CHAR];
    char added   [MAX_BDEV][MAX_BDEV_CHAR];
    char removed [MAX_BDEV][MAX_BDEV_CHAR];
    struct utsname tmp;

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


    struct timeval start_time;
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
                MENU_Redraw(true, true);
                i++;
            }
            i = 0;

            while (removed[i][0] != '\0') {
                ITEM_RemoveByBdev(removed[i]);
                MENU_Redraw(true, true);
                i++;
            }

            memcpy(bdevsOld, bdevs, sizeof(bdevs));
        }

        if (MAIN_LoopIters % 5 == 0) {
            TIMER_Redraw();
        }
        if (TIMER_TicksRemaining == 0 && !TIMER_Stopped) {
            BOOT_Go();
        }

        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(STDIN_FILENO, &readfds);

        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 33333; // Approximately 30 times per second

        // Check for key presses
        int result = select(STDIN_FILENO + 1, &readfds, NULL, NULL, &timeout);
        if (result > 0) {
            char c;
            read(STDIN_FILENO, &c, 1);
            TIMER_Stop();
            switch (c) {
                case 'r':
                    // exiting with status 2 causes init to spawn a recovery shell, and
                    // when exited, restart boot_menu.
                    doCleanup();
                    exit(2);
                case '\n': // Enter key
                    BOOT_Go();
                    break;
                case 'A': // Up arrow key
                    if (MENU_Selected > 0) {
                        MENU_LastSelected = MENU_Selected;
                        MENU_Selected--;
                        MENU_NeedFullRedraw = false;
                        MENU_NeedRedraw = true;
                    }
                    break;
                case 'B': // Down arrow key
                    if (MENU_Selected < ITEM_NumItems - 1) {
                        MENU_LastSelected = MENU_Selected;
                        MENU_Selected++;
                        MENU_NeedFullRedraw = false;
                        MENU_NeedRedraw = true;
                    }
                    break;
            }

            // Redraw menu if needed
            if (MENU_NeedRedraw) {
                MENU_Redraw(true, false);
                MENU_NeedRedraw = 0;
            }

            // Calculate elapsed time and sleep to maintain 30 iterations per second
            struct timeval current_time;
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
    }

    #if !defined(PROD_BUILD) && !defined(DEBUG_WII)
    cleanupAndExit(0);
    #endif
    return 0;
}
