#include "include.h"
static void ITEM_RemoveByBdev(char *bdev) {
    fprintf(logfile, "ITEM_RemoveByBdev(\"%s\")\r\n", bdev);
    int idx = 0xDEAD;
    for (int i = 0; i < ITEM_NumItems; i++) {
        fprintf(logfile, "does \"%s\" == \"%s\"? ", bdev, items[i].bdevName);
        if (strcmp(bdev, items[i].bdevName) == 0) {
            fputs("yes\r\n", logfile);
            idx = i;
        }
        fputs("no\r\n", logfile);
    }
    if (idx == 0xDEAD) {
        fprintf(logfile, "idx == 0xDEAD, nothing found.\r\n");
        return;
    }
    fprintf(logfile, "nuking item at index %d\r\n", idx);

    bzero(&items[idx], sizeof(Item));
    for (int i = idx; i < ITEM_NumItems; i++) {
        if (i + 1 != ITEM_NumItems) {
            memcpy(&items[i], &items[i + 1], sizeof(Item));
        }
    }
    ITEM_NumItems--;
}

static void TERM_DoResize(int dummy) {
    (void)dummy;
    struct winsize w;
    ioctl(0, TIOCGWINSZ, &w);
    TERM_Width = w.ws_col;
    TERM_Height = w.ws_row;

    // force redraw
    MENU_Redraw(false, true);
}


#ifndef PROD_BUILD
static void cleanupAndExit(int dummy) {
    (void)dummy;
    doCleanup();
    exit(0);
}
#else
static void dummySignalHandler(int dummy) {
    (void)dummy;
}
#endif

static void TERM_Init(struct termios *oldt) {
    struct termios newt;
    tcgetattr(STDIN_FILENO, oldt);
    newt = *oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    printf("\e[?25l");
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);

    signal(SIGWINCH, TERM_DoResize);

    // so we can restore the terminal
    #ifndef PROD_BUILD
    signal(SIGINT, cleanupAndExit);
    #else
    signal(SIGINT, dummySignalHandler);
    #endif
}