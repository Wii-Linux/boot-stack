#include "include.h"
#include "term.h"

int TIMER_TicksRemaining = 5*30;
bool TIMER_Stopped = false;
bool TIMER_Paused = false;
void TIMER_Stop() {
	TIMER_Stopped = true;
}

void TIMER_Pause() {
	TIMER_Paused = true;
}

void TIMER_Resume() {
	TIMER_Paused = false;
}

void TIMER_Redraw() {
	char str[64];
	int len;
	int seconds = TIMER_TicksRemaining / 30;
	if (TIMER_Stopped) {
		len = snprintf(str, sizeof(str), "                     ");
	}
	else {
		len = snprintf(str, sizeof(str), "Auto-Booting in %ds", seconds);
	}
	int pos = TERM_Width - len;
	char *color = "\e[1;37m";
	if (seconds <= 3) {
		color = "\e[1;33m";
	}
	if (seconds <= 1) {
		color = "\e[1;31m";
	}

	printf("\e[%d;%dH%s%s\e[0m", TERM_Height, pos, color, str);
	fflush(stdout);
}
