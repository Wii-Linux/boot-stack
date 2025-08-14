#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <strings.h>
#include <ctype.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <termios.h>
#include <signal.h>
#include <stdarg.h>

#include <sys/stat.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/utsname.h>


#ifdef PROD_BUILD
// disable logging, the Wii is too slow.
#define fprintf(file, format, ...) ((void)0)
#define fopen(filename, mode) ((void *)0)
#define fputs(str, file) ((void)0)
#elif defined(DEBUG_WII)
#define fprintf(file, format, ...) fprintf(file, format, __VA_ARGS__); fflush(file)
#define fputs(str, file) fputs(str, file); fflush(file)
#endif

extern FILE *logfile;
