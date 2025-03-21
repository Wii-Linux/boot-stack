#ifndef MENU_H
#define MENU_H
#include <stdbool.h>
extern int MENU_LastSelected;
extern int MENU_Selected;
extern bool MENU_NeedRedraw;
extern bool MENU_NeedFullRedraw;

extern void MENU_Redraw(bool resize, bool full_redraw);
#endif
