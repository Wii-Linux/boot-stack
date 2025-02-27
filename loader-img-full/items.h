#ifndef ITEMS_H
#define ITEMS_H

#define MAX_ITEMS     24
#define MAX_BDEV      64
#define MAX_BDEV_CHAR 16

typedef struct {
    char name[32];
    char nameHighlighted[32];
    char bdevName[MAX_BDEV_CHAR];
    char problems[256];
    char fsType[8];
    bool canBoot;
    bool colorName;
    bool android;
    int colorLen;
    int colorLenHighlighted;
} Item;

extern Item items[MAX_ITEMS];
extern int ITEM_NumItems;

extern void ITEM_RemoveByBdev(char *bdev);

#endif
