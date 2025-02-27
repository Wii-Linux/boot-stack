#include "include.h"
#include "items.h"
#include "term.h"
#include "menu.h"

int TERM_Width;
int TERM_Height;

void TERM_DoResize(int dummy) {
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

void TERM_Init(struct termios *oldt) {
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
