#include <stdlib.h>
#include <unistd.h>
#include "timer.h"
#include "menu.h"
#include "items.h"
#include "cleanup.h"
#include "boot.h"

void INPUT_Handle() {
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
}
