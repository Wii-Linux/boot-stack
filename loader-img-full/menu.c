#include "include.h"
#include "items.h"
#include "menu.h"
#include "term.h"
#include "timer.h"
#include "bottom.h"

int MENU_Selected = 0;
int MENU_LastSelected = 0;
bool MENU_NeedRedraw = false;
bool MENU_NeedFullRedraw = false;

static void MENU_DrawLine(int i, bool forcePad) {
    bool needPad = forcePad;
    char num[32];
    char str[512];
    char *color = "\e[0m";
    char *hasProblems = "";

    if (ITEM_NumItems > 99) {sprintf(num, "%03d", i);}
    else if (ITEM_NumItems > 9) {sprintf(num, "%02d", i);}
    else {sprintf(num, "%d", i);}

    char *name = items[i].name;
    if (i == MENU_Selected) {
        color = "\e[0m\e[30m\e[47m";
        printf(color);
        needPad = true;
        if (items[i].nameHighlighted[0] != '\0') {
            name = items[i].nameHighlighted;
        }
    }

    if (items[i].problems[0] != '\0') {
        hasProblems=", Problems: ";
    }

    int len = sprintf(str, "%s: %s%s on %s\e[1;33m%s%s%s (%s)",
        num, name, color, items[i].bdevName, hasProblems, items[i].problems, color, items[i].fsType
    );
    printf("%s", str);
    if (needPad) {
        len -= strlen("\e[1;33m");
        len -= strlen(color) * 2;
        if (i == MENU_Selected) {
            len -= items[i].colorLenHighlighted;
        }
        else {
            len -= items[i].colorLen;
        }
        int pad = TERM_Width - len;

        if (pad > 0) {
            printf("%*s", pad, "");
        }
    }
    puts("\e[0m");
}

static void MENU_FullRedraw() {
    char *title = "Wii Linux Boot Menu v0.5.0";
    int numSpc = (TERM_Width / 2) - (strlen(title) / 2);
    printf("\e[1;1H\e[2J\r\n");
    printf("\e[1;37m%*c%s\e[0m\r\n", numSpc, ' ', title);
    for (int i = 0; i < ITEM_NumItems; i++) {
        MENU_DrawLine(i, false);
    }
    BOTTOM_Init();
    TIMER_Redraw();
}

static void MENU_PartialRedraw() {
    // we were at MENU_LastSelected + 1 on the screen before, so go there, and redraw it as not selected
    printf("\e[%d;1H", MENU_LastSelected + 3);
    MENU_DrawLine(MENU_LastSelected, true);

    // let's now redraw the line that we want to draw
    printf("\e[%d;1H", MENU_Selected + 3);
    MENU_DrawLine(MENU_Selected, true);
}

void MENU_Redraw(bool resize, bool full_redraw) {
    if (resize) {
        // TERM_DoResize(0);
    }
    #ifdef DEBUG_FORCE_FULLREDRAW
        MENU_FullRedraw();
    #else
        if (full_redraw) { MENU_FullRedraw(); }
        else { MENU_PartialRedraw(); }
    #endif
}
