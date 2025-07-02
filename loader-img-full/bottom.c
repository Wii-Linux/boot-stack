#include "include.h"
#include "term.h"

void BOTTOM_Init() {
	fprintf(logfile, "BOTTOM_Init() called\r\n");
	printf("\e[%d;1HControls: Supports Keyboard or GCN Controller, format of \"Kbd Key [GCN button]\"", TERM_Height - 2);
	printf("\e[%d;1HPress Up/Down (Keyboard/D-Pad) to select an item, Enter [A] to boot", TERM_Height - 1);
	printf("\e[%d;1Hr [X]: Recovery Shell", TERM_Height);
	fflush(stdout);
}
void BOTTOM_Destroy() {
	printf("\e[%d;1H%*c", TERM_Height - 2, TERM_Width, ' ');
	printf("\e[%d;1H%*c", TERM_Height - 1, TERM_Width, ' ');
	printf("\e[%d;1H%*c", TERM_Height, TERM_Width, ' ');
	fflush(stdout);
}

#define MAX_BOTTOM_LOG_MSGS 10
#define MAX_BOTTOM_LOG_CHAR 128
static char _BOTTOM_LogMsgs[MAX_BOTTOM_LOG_MSGS][MAX_BOTTOM_LOG_CHAR];
static int _BOTTOM_LogMsgsIndex = 0;


static void _BOTTOM_Log(const char *src) {
	// Copy the message into the destination array
	strncpy(_BOTTOM_LogMsgs[_BOTTOM_LogMsgsIndex], src, MAX_BOTTOM_LOG_CHAR - 1);
	_BOTTOM_LogMsgs[_BOTTOM_LogMsgsIndex][MAX_BOTTOM_LOG_CHAR - 1] = '\0'; // Ensure null-terminated

	// Determine where to print the message
	int row = TERM_Height - MAX_BOTTOM_LOG_MSGS + _BOTTOM_LogMsgsIndex;

	// Move cursor to the correct position
	printf("\e[%d;1H", row);

	// Print the message
	printf("%s", _BOTTOM_LogMsgs[_BOTTOM_LogMsgsIndex]);

	// Increment index with wrap-around
	_BOTTOM_LogMsgsIndex = (_BOTTOM_LogMsgsIndex + 1) % MAX_BOTTOM_LOG_MSGS;
}

// Wrapper function to handle formatted log messages
void BOTTOM_Log(const char *fmt, ...) {
	va_list args;
	char str[MAX_BOTTOM_LOG_CHAR];
	va_start(args, fmt);
	vsnprintf(str, sizeof(str), fmt, args);
	va_end(args);

	// Store the message in the log
	_BOTTOM_Log(str);
}
