#include "include.h"
#include "items.h"
int ITEM_NumItems = 0;
Item items[MAX_ITEMS];

void ITEM_RemoveByBdev(char *bdev) {
	fprintf(logfile, "ITEM_RemoveByBdev(\"%s\")\r\n", bdev);
	int idx = 0xDEAD;
	for (int i = 0; i < ITEM_NumItems; i++) {
		fprintf(logfile, "does \"%s\" == \"%s\"? ", bdev, items[i].bdevName);
		if (strcmp(bdev, items[i].bdevName) == 0) {
			fputs("yes\r\n", logfile);
			idx = i;
		}
		fputs("no\r\n", logfile);
	}
	if (idx == 0xDEAD) {
		fprintf(logfile, "idx == 0xDEAD, nothing found.\r\n");
		return;
	}
	fprintf(logfile, "nuking item at index %d\r\n", idx);

	bzero(&items[idx], sizeof(Item));
	for (int i = idx; i < ITEM_NumItems; i++) {
		if (i + 1 != ITEM_NumItems) {
			memcpy(&items[i], &items[i + 1], sizeof(Item));
		}
	}
	ITEM_NumItems--;
}
