extern int TERM_Width;
extern int TERM_Height;

extern void TERM_Init(struct termios *oldt);
extern void TERM_DoResize(int dummy);
