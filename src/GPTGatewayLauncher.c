#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

static void fail(const char *message) {
    fprintf(stderr, "GPT Gateway: %s: %s\n", message, strerror(errno));
    _exit(127);
}

static int is_translated(void) {
#ifdef __APPLE__
    int translated = 0;
    size_t size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == 0) {
        return translated;
    }
#endif
    return 0;
}

static const char *native_arch(void) {
#if defined(__arm64__) || defined(__aarch64__)
    return "arm64";
#elif defined(__x86_64__)
    return "x86_64";
#else
    return "unknown";
#endif
}

int main(int argc, char *argv[]) {
    if (argc == 2 && strcmp(argv[1], "--native-self-test") == 0) {
        printf("arch=%s translated=%d\n", native_arch(), is_translated());
        return 0;
    }

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
