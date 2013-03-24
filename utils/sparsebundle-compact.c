#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

static char buf[PATH_MAX+1];

static void die(const char *msg) {
	fprintf(stderr, "\n%s\n", msg);
	exit(-1);
}

static void check_path(char *bundle, char *sub) {
	if (snprintf(buf, PATH_MAX, "%s/%s", bundle, sub) >= PATH_MAX)
		die("Paths too long");
	if (access(buf, F_OK) != 0)
		die("Not a sparsebundle");
}

static void compact(char *bundle) {
	check_path(bundle, "token");
	check_path(bundle, "Info.plist");
	
	check_path(bundle, "bands");
	char *bands = strdup(buf);
	DIR *dir = opendir(bands);
	if (!dir)
		die("Can't open band dir");
	struct dirent *de;
	while ((de = readdir(dir))) {
		if (de->d_name[0] == '.')
			continue;
		
		fprintf(stdout, "%5s   ", de->d_name);
		if (snprintf(buf, PATH_MAX, "%s/%s", bands, de->d_name) >= PATH_MAX)
			die("Paths too long");
		int fd = open(buf, O_RDWR);
		if (!fd)
			die("Can't open band");
		ssize_t size = lseek(fd, 0, SEEK_END);
		if (size == -1)
			die("Can't seek");
		char *bytes = mmap(NULL, size, PROT_READ, MAP_FILE | MAP_SHARED, fd, 0);
		if (bytes == MAP_FAILED)
			die("Can't mmap");
		
		size_t nz = size;
		for (; nz > 0 && !bytes[nz - 1]; --nz)
			;
		munmap(bytes, size);
		
		if (nz > 0 && nz < size) {
			fprintf(stdout, "saving %ld", size - nz);
			if (ftruncate(fd, nz) != 0)
				die("Can't truncate");
		}
		close(fd);
		if (nz == 0) {
			fprintf(stdout, "removing");
			if (unlink(buf) != 0)
				die("Can't unlink");
		}
		fprintf(stdout, "\n");
	}
	free(bands);
	closedir(dir);
}

int main(int argc, char *argv[]) {
	if (argc != 2) {
		fprintf(stderr, "Usage: sparsebundle-compact SPARSEBUNDLE\n");
		exit(-2);
	}
	compact(argv[1]);
	return 0;
}
