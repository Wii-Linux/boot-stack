#ifndef INPUT_H
#define INPUT_H
extern void INPUT_Handle();
#define MAX_KBD_DEVICES 8
#define CONTROLLER_DEVICE "/dev/input/by-path/"

typedef enum {
	INPUT_TYPE_NONE,
	INPUT_TYPE_SELECT,
	INPUT_TYPE_UP,
	INPUT_TYPE_DOWN,
	INPUT_TYPE_RECOVERY,
	INPUT_TYPE_ERROR = -1
} inputEvent_t;


extern int INPUT_Init();
extern void INPUT_Shutdown();
extern inputEvent_t INPUT_Handle();
#endif
#endif
