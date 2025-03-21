#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include "items.h"
#include "bottom.h"
#include "menu.h"
#include "timer.h"
#include "cleanup.h"

void BOOT_Go() {
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
