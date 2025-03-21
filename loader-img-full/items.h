#ifndef ITEMS_H
#define ITEMS_H
#include <stdbool.h>

#define MAX_ITEM_NAME_LEN 64
#define MAX_ITEMS     24
#define MAX_BDEV      64
#define MAX_BDEV_CHAR 24

typedef struct {
    char name[MAX_ITEM_NAME_LEN];
    char nameHighlighted[MAX_ITEM_NAME_LEN];
    char bdevName[MAX_BDEV_CHAR];
    char problems[256];
    char fsType[8];
    bool canBoot;
    bool colorName;
    bool android;
    bool batocera;
    int colorLen;
    int colorLenHighlighted;
} Item;

extern Item items[MAX_ITEMS];
extern int ITEM_NumItems;

extern void ITEM_RemoveByBdev(char *bdev);

#endif
