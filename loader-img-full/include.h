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

#include <blkid/blkid.h>


/*#ifdef PROD_BUILD
// disable logging, the Wii is too slow.
#define fprintf(file, format, ...) ((void)0)
#define fopen(filename, mode) ((void *)0)
#define fputs(str, file) ((void)0)
#endif*/


// #define DEBUG_FORCE_FULLREDRAW

#define MAX_ITEMS     20
#define MAX_BDEV      20
#define MAX_BDEV_CHAR 32

typedef struct {
    char name[32];
    char nameHighlighted[32];
    char bdevName[MAX_BDEV_CHAR];
    char problems[256];
    char fsType[8];
    bool canBoot;
    bool colorName;
    int colorLen;
    int colorLenHighlighted;
} Item;

static int MAIN_LoopIters = 0;
static int BOTTOM_InitCalls = 0;
static Item items[MAX_ITEMS] = {0};
static int ITEM_NumItems = 0;

static int MENU_LastSelected = 0;
static int MENU_Selected = 0;
static bool MENU_NeedRedraw = 0;
static bool MENU_NeedFullRedraw = 0;

static int TERM_Width;
static int TERM_Height;

static struct termios oldt;

static FILE *logfile;

static void MENU_Redraw(bool resize, bool full_redraw);
