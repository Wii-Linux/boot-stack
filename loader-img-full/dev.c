#include "include.h"
#include "args.h"
#include "items.h"
#include "timer.h"

#include <blkid/blkid.h>


#define MAX_PROBLEMS 50000
#define MAX_PROBLEM_CHAR 256

static bool DEV_ignore(const char *name)
{
	static const char *PREFIX[] = { "loop", "zram", "ram", "nbd", "nfs", NULL };
	int i;
	for (i = 0; PREFIX[i]; i++) {
		const char *prefix = PREFIX[i];
		size_t len = strlen(prefix);
		if (strlen(name) <= len) continue;
		if (memcmp(name, prefix, len) != 0) continue;
		if (!isdigit(name[len])) continue;
		return true; // <prefix><digit>...
	}
	return false;
}

static char ___problems[MAX_PROBLEMS][MAX_PROBLEM_CHAR];
static int  ___problemsIndex = 0;
void DEV_Detect(char bdevs[MAX_BDEV][MAX_BDEV_CHAR]) {
	DIR *dir;
	struct dirent *ent;
	struct stat st;
	int i = 0;

	memset(bdevs, 0, MAX_BDEV * MAX_BDEV_CHAR);

	dir = opendir("/dev");
	if (dir == NULL) {
		perror("Couldn't open /dev");
		exit(1);
	}

	while ((ent = readdir(dir)) != NULL) {
		char path[261];
		if (DEV_ignore(ent->d_name)) continue; // ignored

		snprintf(path, sizeof(path), "/dev/%s", ent->d_name);

		// get its type
		if (lstat(path, &st) == -1) {
			fprintf(stderr, "lstat() failed on %s: %s\r\n", path, strerror(errno));
			continue;
		}

		// is it a bdev?
		if (S_ISBLK(st.st_mode)) {
			fprintf(logfile, "DEV_Detect(): adding %s", path);
			strcpy(bdevs[i], path);
			i++;
			if (i == MAX_BDEV) break; // no overflow
			bdevs[i][0] = '\0';
		}
	}

	closedir(dir);
	return;
}


static void addProblem(char *str);
static bool _readDistro(char *suffix, char *distroName, char *distroNameHighlighted, char *problems, int *colorLen, int *colorLenHighlighted, bool *isAndroid, bool *isBatocera) {
	char str[256];
	int fd;
	bool ret = false;

	snprintf(str, sizeof(str), "/._distro%s", suffix);
	fd = open(str, O_RDONLY);
	if (fd == -1) {
		// wtf, it should, but handle it hear anyways for completeness
		strcpy(distroName, "Unknown");
		if (strlen(problems) > 0) {
			strcat(problems, "; ");
		}


		strcat(problems, "Failed to get distro name from checkBdev");
		return false;
	}
	// read in the distro name

	// get size
	struct stat st;
	fstat(fd, &st);

	// read that many bytes, close the file, and null terminate the str
	read(fd, str, st.st_size);
	close(fd);
	str[st.st_size] = '\0';

	char *tok = strchr(str, '\n');

	if (tok != NULL) {
		memcpy(distroName, str, tok - str);
		distroName[tok - str] = '\0';
		strcpy(distroNameHighlighted, tok + 1);
	}
	else {
		strcpy(distroName, str);
	}

	snprintf(str, sizeof(str), "/._colors%s", suffix);
	fd = open(str, O_RDONLY);
	if (fd != -1) {
		// has color
		fstat(fd, &st);

		// read that many bytes, close the file, and null terminate the str
		read(fd, str, st.st_size);
		close(fd);
		str[st.st_size] = '\0';

		char *inBetween = strchr(str, ' ');
		if (inBetween) {
			*inBetween = '\0';
			*colorLen = atoi(str);
			*colorLenHighlighted = atoi(inBetween + 1);
		}
		ret = true;
	}
	close(fd);
	remove(str);

	// check if distro is Android
	snprintf(str, sizeof(str), "/._android%s", suffix);
	fd = open(str, O_RDONLY);

	// fd == -1, file doesn't exist, not android
	// fd != -1, file exists (valid fd), is android
	*isAndroid = (fd != -1);
	close(fd);
	remove(str);

	// check if distro is Batocera
	snprintf(str, sizeof(str), "/._batocera%s", suffix);
	fd = open(str, O_RDONLY);

	// fd == -1, file doesn't exist, not batocera
	// fd != -1, file exists (valid fd), is batocera
	*isBatocera = (fd != -1);
	close(fd);
	remove(str);

	if (fd == -1 && ARGS_IsPPCDroid) {
		addProblem("Linux distro on PPCDroid kernel");
		return false;
	}

	return ret;
}

static void addProblem(char *str) {
	printf("\r\n\r\n%d %d\r\n\r\n", sizeof(___problems[0]), ___problemsIndex);
	strcpy(___problems[___problemsIndex], str);
	___problemsIndex++;
}

static void problemsDone(char *dest) {
	strcat(dest, ___problems[0]);
	for (int i = 1; i != MAX_PROBLEMS; i++) {
		if (___problems[i][0] == '\0') {
			break;
		}
		strcat(dest, "; ");
		strcat(dest, ___problems[i]);
	}

	bzero(___problems, sizeof(___problems));
	___problemsIndex = 0;
}

static void _readProblems(char *suffix) {
	char str[256];

	snprintf(str, sizeof(str), "/._problems%s", suffix);
	int fd = open(str, O_RDONLY);

	if (fd == -1) { return; }
	// we got problems, read them in

	// get size
	struct stat st;
	fstat(fd, &st);

	// read that many bytes, close the file, and null terminate the str
	read(fd, str, st.st_size);
	close(fd);
	str[st.st_size] = '\0';

	char *tok = strtok(str, "\n");
	while (tok != NULL) {
		addProblem(tok);
		tok = strtok(NULL, "\n");
	}
}

void DEV_Scan(char* block_device) {
	blkid_probe pr;
	int rc;
	char problems[64];
	const char *fsType = "???";
	char distroName[128] = "???";
	char distroNameHighlighted[128] = "???";
	int colorLen = 0;
	int colorLenHighlighted = 0;
	bool canBoot = true;
	bool color = false;
	bool paused = TIMER_Paused;
	bool android = false;
	bool batocera = false;

	fprintf(logfile, "DEV_Scan(): scan initiated for \"%s\"\r\n", block_device);


	TIMER_Pause();
	pr = blkid_new_probe_from_filename(block_device);
	if (!pr) {
		addProblem("Couldn't create new blkid probe");
		fputs("DEV_Scan(): skipping to out because !pr\n", logfile);
		goto out;
	}
	blkid_probe_enable_partitions(pr, true);

	rc = blkid_do_fullprobe(pr);

	if (rc != 0) {
		addProblem("Couldn't execute blkid fullprobe");
		fputs("DEV_Scan(): skipping to out because rc!=0\n", logfile);
		goto out;
	}

	// Is this a whole device containing a partition table?  if so, skip it.
	if (blkid_probe_lookup_value(pr, "PTTYPE", &fsType, NULL) == 0) {
		fprintf(logfile, "DEV_Scan(): Detected full block device \"%s\"\r\n", block_device);
		blkid_free_probe(pr);
		TIMER_Resume();
		return;
	}


	if (blkid_probe_lookup_value(pr, "TYPE", &fsType, NULL) == 0) {
		char str[64];
		// TODO: run multiple in parallel with different suffixes for more speed
		char *suffix = "0";

		snprintf(str, sizeof(str), "/checkBdev.sh %s %s %s", block_device, suffix, fsType);
		fprintf(logfile, "DEV_Scan(): running \"%s\"\r\n", str);

		// #ifdef PROD_BUILD
		int ret = WEXITSTATUS(system(str));
		// #else
		// int ret = 0;
		// #endif

		fprintf(logfile, "DEV_Scan(): checkBdev.sh gave ret %d for bdev %s\r\n", ret, block_device);
		switch (ret) {
			case 0:
				// ._problems[suffix] may exist, and ._distro[suffix] will
				_readProblems(suffix);
				color = _readDistro(suffix, distroName, distroNameHighlighted, problems, &colorLen, &colorLenHighlighted, &android, &batocera);
				break;
			case 101:
				// fatal error checking bdev, ._problems[suffix] will exist, ._distro[name] will not
				_readProblems(suffix);
				strcpy(distroName, "Unknown");
				break;
			case 102:
				// fatal internal error (we gave it bad args?), ._problems will exist with no suffix, nothing related to the name will
				_readProblems("");
				blkid_free_probe(pr);
				strcpy(distroName, "Unknown");
				break;
			case 103:
				// not a Linux distro at all, or corrupted beyond repair, don't even list it.
				fprintf(logfile, "DEV_Scan(): \"%s\" is not a Linux distro\r\n", block_device);
				blkid_free_probe(pr);
		if (!paused) TIMER_Resume();
				return;
			case 104:
				// non-fatal error, checking continued, distro will boot
				_readProblems(suffix);
				color = _readDistro(suffix, distroName, distroNameHighlighted, problems, &colorLen, &colorLenHighlighted, &android, &batocera);
				break;
			case 105:
				// distro will not boot, but did not stop it from continuing to check
				_readProblems(suffix);
				color = _readDistro(suffix, distroName, distroNameHighlighted, problems, &colorLen, &colorLenHighlighted, &android, &batocera);
				canBoot = false;
				break;
			default:
				// unknown
				snprintf(str, sizeof(str), "internal err - checkBdev unk ret (%d)", ret);
				addProblem(str);
		}
	}
	// done:
	fprintf(logfile, "DEV_Scan(): Detected partition block device \"%s\"\r\n", block_device);


	out:

	fprintf(logfile, "DEV_Scan(): Setting up items[%d], previously containing bdev %s\r\n", ITEM_NumItems, items[ITEM_NumItems].bdevName);
	strncpy(items[ITEM_NumItems].bdevName, block_device, sizeof(items->bdevName));

	problemsDone(items[ITEM_NumItems].problems);
	if (strcmp(distroNameHighlighted, "???") != 0) {
		strncpy(items[ITEM_NumItems].nameHighlighted,   distroNameHighlighted, sizeof(items->nameHighlighted));
	}
	strncpy(items[ITEM_NumItems].fsType, fsType, sizeof(items->fsType));
	strncpy(items[ITEM_NumItems].name, distroName, sizeof(items->name));

	blkid_free_probe(pr);
	items[ITEM_NumItems].canBoot = canBoot;
	items[ITEM_NumItems].colorName = color;
	items[ITEM_NumItems].colorLen = colorLen;
	items[ITEM_NumItems].colorLenHighlighted = colorLenHighlighted;
	items[ITEM_NumItems].android = android;
	items[ITEM_NumItems].batocera = batocera;
	ITEM_NumItems++;

	if (!paused) TIMER_Resume();
}


// Function to find if a string exists in an array of strings
static int stringExistsInArray(const char *str, const char arr[][MAX_BDEV_CHAR], int size) {
	for (int i = 0; i < size; ++i) {
		if (strcmp(str, arr[i]) == 0) {
			return true;
		}
	}
	return false;
}

void DEV_Compare(char bdevs[MAX_BDEV][MAX_BDEV_CHAR], char bdevsOld[MAX_BDEV][MAX_BDEV_CHAR],
						char added[MAX_BDEV][MAX_BDEV_CHAR], char removed[MAX_BDEV][MAX_BDEV_CHAR]) {
	int addedCount = 0, removedCount = 0;

	fputs("DEV_Compare(): starting...\n", logfile);
	for (int i = 0; i != MAX_BDEV; i++) {
		fprintf(logfile, "bdevs[%d]=\"%s\" ", i, bdevs[i]);
	}
	fputs("\n", logfile);
	for (int i = 0; i != MAX_BDEV; i++) {
		fprintf(logfile, "bdevsOld[%d]=\"%s\" ", i, bdevsOld[i]);
	}
	fputs("\n", logfile);

	memset(added, 0, MAX_BDEV * MAX_BDEV_CHAR);
	memset(removed, 0, MAX_BDEV * MAX_BDEV_CHAR);
	// Find items added
	for (int i = 0; i < MAX_BDEV && bdevs[i][0]!= '\0'; ++i) {
		fprintf(logfile, "DEV_Compare(): did %s exist before? ", bdevs[i]);
		if (!stringExistsInArray(bdevs[i], bdevsOld, MAX_BDEV)) {
			fputs("no, adding\r\n", logfile);
			strcpy(added[addedCount++], bdevs[i]);
		}
		else {
			fputs("yes\r\n", logfile);
		}
	}

	// Find items removed
	for (int i = 0; i < MAX_BDEV && bdevsOld[i][0]!= '\0'; ++i) {
		fprintf(logfile, "DEV_Compare(): does %s exist anymore? ", bdevsOld[i]);
		if (!stringExistsInArray(bdevsOld[i], bdevs, MAX_BDEV)) {
			fputs("no, removing\r\n", logfile);
			strcpy(removed[removedCount++], bdevsOld[i]);
		}
		else {
			fputs("yes\r\n", logfile);
		}
	}
	fputs("DEV_Compare(): leaving\n", logfile);
}
