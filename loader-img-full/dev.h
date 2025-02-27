#ifndef DEV_H
#define DEV_H

#include "items.h"
extern void DEV_Compare(char bdevs[MAX_BDEV][MAX_BDEV_CHAR], char bdevsOld[MAX_BDEV][MAX_BDEV_CHAR],
                        char added[MAX_BDEV][MAX_BDEV_CHAR], char removed[MAX_BDEV][MAX_BDEV_CHAR]);
extern void DEV_Scan(char* block_device);
extern void DEV_Detect(char bdevs[MAX_BDEV][MAX_BDEV_CHAR]);

#endif
