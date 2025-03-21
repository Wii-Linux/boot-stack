#ifndef TIMER_H
#define TIMER_H
#include <stdbool.h>
extern bool TIMER_Stopped;
extern bool TIMER_Paused;
extern int TIMER_TicksRemaining;

extern void TIMER_Stop();
extern void TIMER_Pause();
extern void TIMER_Resume();
extern void TIMER_Redraw();
#endif
