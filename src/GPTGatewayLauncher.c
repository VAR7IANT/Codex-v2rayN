#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void fail(const char *message) {
    fprintf(stderr, "GPT Gateway: %s: %s\n", message, strerror(errno));
    _exit(127);
}

int main(int argc, char *argv[]) {
    char executable[PATH_MAX];
    if (realpath(argv[0], executable) == NULL) {
        fail("cannot resolve launcher path");
    }

    char *slash = strrchr(executable, '/');
    if (slash == NULL) {
        errno = EINVAL;
        fail("invalid launcher path");
    }
    *slash = '\0';

    char script[PATH_MAX];
    int written = snprintf(
        script,
        sizeof(script),
        "%s/../Resources/gateway.zsh",
        executable
    );
    if (written < 0 || (size_t)written >= sizeof(script)) {
        errno = ENAMETOOLONG;
        fail("resource path is too long");
    }

    char **child_argv = calloc((size_t)argc + 2, sizeof(char *));
    if (child_argv == NULL) {
        fail("cannot allocate argument list");
    }

    child_argv[0] = "/bin/zsh";
    child_argv[1] = script;
    for (int i = 1; i < argc; ++i) {
        child_argv[i + 1] = argv[i];
    }
    child_argv[argc + 1] = NULL;

    execv("/bin/zsh", child_argv);
    fail("cannot start /bin/zsh");
    return 127;
}
