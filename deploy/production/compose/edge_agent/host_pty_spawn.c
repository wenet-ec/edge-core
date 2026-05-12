/*
 * host_pty_spawn — allocate a PTY in another mount namespace and exec a shell.
 *
 * Why this exists
 * ---------------
 * The agent runs in a container. Docker gives every container its own private
 * /dev/pts mount (devpts is namespaced). When erlexec spawns a process with
 * the `:pty` option, it calls openpty(3) from inside the container, so the
 * resulting PTY lives in the container's devpts. If that process then enters
 * the host's mount namespace via nsenter(1) (which is how `hostscript` puts
 * commands on the host's filesystem), the kernel object behind the PTY fds
 * is still valid — but path-based ioctls like TIOCSCTTY fail with ENOTTY
 * because the kernel checks that the controlling-tty device matches what the
 * process's mount namespace sees at /dev/pts. The shell ends up running
 * without job control, in a degraded state where the prompt never appears.
 *
 * This helper closes the gap: it enters the host's mount namespace FIRST,
 * THEN allocates the PTY (with forkpty(3)) on the host's devpts, where it
 * naturally belongs. The shell that forkpty execs is bash --login -i, which
 * sees the host's filesystem (mount ns), the host's PATH (via /etc/profile),
 * the host's editors, and a real working PTY with job control.
 *
 * It proxies bytes between its own stdio (which the agent talks to via
 * erlexec's pipes) and the host PTY's master, and forwards SIGWINCH from
 * its own controlling-tty's window size onto the host PTY master so terminal
 * resize events reach bash naturally.
 *
 * Usage
 * -----
 *   host_pty_spawn <ns-handle-path> <command> [args...]
 *
 *   <ns-handle-path> is typically /host/proc/1/ns/mnt
 *     (the agent compose service bind-mounts the host root at /host, so
 *      /host/proc/1 is the host's PID 1 = systemd, whose mount-ns handle is
 *      our entry point into the host's filesystem view).
 *
 *   <command> and args are exec'd inside the host namespace on the new PTY.
 *     Typical use: `bash --login -i`.
 *
 * Build
 * -----
 *   gcc -O2 -Wall -Wextra -o host_pty_spawn host_pty_spawn.c -lutil
 *
 *   (-lutil for forkpty/openpty; everything else is plain glibc.)
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static int g_master_fd = -1;  /* host-side PTY master, for SIGWINCH handler */

/*
 * Edge-branded rcfile. Sourced as `bash --rcfile /proc/self/fd/N` so the host's
 * bash picks it up but it leaves no file on disk (memfd, lives in RAM, dies
 * with the process). Pulls in the host's standard interactive setup first
 * so operators keep their own aliases/completion/etc., then overrides PS1
 * and `cd`s to $HOME so the shell lands somewhere sensible.
 */
static const char EDGE_RCFILE[] =
    "[ -f /etc/profile ] && . /etc/profile\n"
    "[ -f ~/.bashrc ] && . ~/.bashrc\n"
    "NODE_ID=\"${EDGE_NODE_ID:-unknown}\"\n"
    "SHORT_NODE_ID=\"${NODE_ID:0:8}\"\n"
    "CURRENT_USER=\"${USER:-root}\"\n"
    "export PS1=\"\\[\\033[1;32m\\]${CURRENT_USER}\\[\\033[0m\\]@\\[\\033[1;36m\\]node-${SHORT_NODE_ID}\\[\\033[0m\\]:\\[\\033[1;34m\\]\\w\\[\\033[0m\\]# \"\n"
    "cd ~ 2>/dev/null || cd /\n"
    ;

/*
 * Write the rcfile into a memfd and return its fd (CLOEXEC cleared so the
 * exec'd bash can still see it via /proc/self/fd/N). Returns -1 on failure;
 * the caller can fall back to spawning bash without --rcfile.
 */
static int make_rcfile_memfd(void)
{
    int fd = memfd_create("edge_rcfile", 0);
    if (fd < 0) return -1;
    const char *p = EDGE_RCFILE;
    size_t left = sizeof EDGE_RCFILE - 1;  /* exclude trailing NUL */
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return -1;
        }
        p += n;
        left -= n;
    }
    /* Rewind so bash reads from the start. */
    if (lseek(fd, 0, SEEK_SET) < 0) {
        close(fd);
        return -1;
    }
    /* memfd_create defaults to no CLOEXEC, but be explicit so we know bash
     * will inherit this fd across exec. */
    int flags = fcntl(fd, F_GETFD);
    if (flags >= 0) (void)fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);
    return fd;
}

static void winch_handler(int sig)
{
    (void)sig;
    struct winsize ws;
    /* Read OUR window size (erlexec set this via TIOCSWINSZ on its PTY,
     * which is wired to our fd 0). Mirror onto the host PTY's master, which
     * will deliver SIGWINCH to bash. */
    if (g_master_fd >= 0 && ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == 0) {
        (void)ioctl(g_master_fd, TIOCSWINSZ, &ws);
    }
}

/* Bidirectional byte pump between fd `master` (host PTY master) and our own
 * stdin/stdout. Returns when either side closes. */
static void pump(int master)
{
    char buf[4096];
    struct pollfd pfds[2];

    pfds[0].fd = master;
    pfds[0].events = POLLIN;
    pfds[1].fd = STDIN_FILENO;
    pfds[1].events = POLLIN;

    for (;;) {
        int n = poll(pfds, 2, -1);
        if (n < 0) {
            if (errno == EINTR) continue;  /* e.g. SIGWINCH we handle */
            break;
        }
        /* host PTY master → our stdout */
        if (pfds[0].revents & POLLIN) {
            ssize_t r = read(master, buf, sizeof buf);
            if (r <= 0) break;
            ssize_t off = 0;
            while (off < r) {
                ssize_t w = write(STDOUT_FILENO, buf + off, r - off);
                if (w < 0) { if (errno == EINTR) continue; return; }
                off += w;
            }
        }
        if (pfds[0].revents & (POLLHUP | POLLERR | POLLNVAL)) break;
        /* our stdin → host PTY master */
        if (pfds[1].revents & POLLIN) {
            ssize_t r = read(STDIN_FILENO, buf, sizeof buf);
            if (r <= 0) break;
            ssize_t off = 0;
            while (off < r) {
                ssize_t w = write(master, buf + off, r - off);
                if (w < 0) { if (errno == EINTR) continue; return; }
                off += w;
            }
        }
        if (pfds[1].revents & (POLLHUP | POLLERR | POLLNVAL)) break;
    }
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s <ns-handle-path> <command> [args...]\n", argv[0]);
        return 2;
    }

    /* Put OUR stdin (the outer PTY's slave, given to us by erlexec) into raw
     * mode. Without this, the outer PTY's line discipline buffers keystrokes
     * until newline (canonical mode) and echoes them back, which both
     * mangles control characters like Ctrl-O and means we deliver bytes to
     * the inner PTY way too late. Save the original termios so we can
     * restore on exit, though the OS will clean up if we die. */
    struct termios orig_termios;
    int restore_termios = 0;
    if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &orig_termios) == 0) {
        struct termios raw = orig_termios;
        cfmakeraw(&raw);
        if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0) {
            restore_termios = 1;
        }
    }

    const char *ns_path = argv[1];

    /* 1. Open the host namespace handle BEFORE switching, so we still see
     *    the path. Close-on-exec so the eventual child shell doesn't inherit. */
    int ns_fd = open(ns_path, O_RDONLY | O_CLOEXEC);
    if (ns_fd < 0) {
        fprintf(stderr, "host_pty_spawn: open(%s): %s\n", ns_path, strerror(errno));
        return 3;
    }

    /* 2. Enter the host's mount namespace. After this, /dev/pts resolves to
     *    the host's devpts, which is where we want the PTY to live. */
    if (setns(ns_fd, CLONE_NEWNS) < 0) {
        fprintf(stderr, "host_pty_spawn: setns(CLONE_NEWNS): %s\n", strerror(errno));
        close(ns_fd);
        return 4;
    }
    close(ns_fd);

    /* 3. Build the branded rcfile in a memfd so it survives the namespace
     *    swap and the exec. /proc/self/fd/N is the path bash will use. The
     *    memfd lives in RAM, has no on-disk presence, and is garbage-collected
     *    when its last fd closes. Fall back silently if memfd_create fails —
     *    the operator still gets a usable shell, just without our prompt. */
    int rc_fd = make_rcfile_memfd();
    char rc_path[64];
    if (rc_fd >= 0) {
        snprintf(rc_path, sizeof rc_path, "/proc/self/fd/%d", rc_fd);
    }

    /* 4. Mirror our window size to whatever the shell will see. forkpty()
     *    will copy this onto the new slave's tty. */
    struct winsize ws;
    int have_ws = (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == 0);

    /* 5. forkpty inside the host mount ns. The new PTY pair lives in the
     *    host's devpts (where bash expects ttyname() to resolve, where
     *    TIOCSCTTY can find the matching device, etc.). */
    int master = -1;
    pid_t child = forkpty(&master, NULL, NULL, have_ws ? &ws : NULL);
    if (child < 0) {
        fprintf(stderr, "host_pty_spawn: forkpty: %s\n", strerror(errno));
        return 5;
    }
    if (child == 0) {
        /* In the grandchild: forkpty already setsid'd, made us the controlling
         * tty owner of the new pts, and dup'd the slave onto fd 0/1/2. */

        /* Wedge `--rcfile /proc/self/fd/N` into the exec argv between argv[2]
         * (the shell binary, e.g. /bin/bash) and the rest. We do NOT add this
         * when the operator passed `--login` or `--rcfile` themselves — we
         * detect a vanilla bash invocation by checking that argv[2] ends in
         * "bash" and that no --rcfile is already in the args. The rcfile
         * itself sources /etc/profile, mimicking what --login would do.
         *
         * Build a new argv on the stack: [argv[2], "--rcfile", rc_path, "-i",
         * extra args from argv[3..]]. We deliberately replace --login with
         * -i since --login + --rcfile would have bash ignore the rcfile. */
        const char *shell = argv[2];
        const char *shell_basename = strrchr(shell, '/');
        shell_basename = shell_basename ? shell_basename + 1 : shell;
        int inject = (rc_fd >= 0 && strcmp(shell_basename, "bash") == 0);
        if (inject) {
            /* Allocate argv: shell + --rcfile + path + -i + remaining (skip
             * argv[3] if it was --login, since --rcfile and --login conflict).
             * Max size = argc original + 3 extras + NULL. */
            char **new_argv = calloc(argc + 4, sizeof(char *));
            if (!new_argv) _exit(127);
            int n = 0;
            new_argv[n++] = (char *)shell;
            new_argv[n++] = (char *)"--rcfile";
            new_argv[n++] = rc_path;
            new_argv[n++] = (char *)"-i";
            for (int i = 3; i < argc; i++) {
                /* Drop --login / -l — incompatible with --rcfile and we
                 * already do the login work (source /etc/profile) in the
                 * rcfile itself. */
                if (strcmp(argv[i], "--login") == 0 || strcmp(argv[i], "-l") == 0) continue;
                if (strcmp(argv[i], "-i") == 0) continue;  /* already added */
                new_argv[n++] = argv[i];
            }
            new_argv[n] = NULL;
            execvp(shell, new_argv);
        } else {
            execvp(shell, &argv[2]);
        }
        fprintf(stderr, "host_pty_spawn: execvp(%s): %s\n", argv[2], strerror(errno));
        _exit(127);
    }

    /* Parent doesn't need the rcfile fd anymore (the grandchild inherited
     * its own copy via fork). Close it here so we don't pin the memfd. */
    if (rc_fd >= 0) close(rc_fd);

    /* 6. In the parent (still in host mount ns, but no longer a session
     *    leader). Hook up SIGWINCH so terminal resize on our side mirrors
     *    onto the host PTY. */
    g_master_fd = master;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = winch_handler;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGWINCH, &sa, NULL);

    /* 7. Proxy bytes. */
    pump(master);

    /* 8. Reap. */
    close(master);
    int status = 0;
    pid_t waited = waitpid(child, &status, 0);
    if (restore_termios) tcsetattr(STDIN_FILENO, TCSANOW, &orig_termios);
    if (waited < 0) return 1;
    if (WIFEXITED(status))   return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 1;
}
