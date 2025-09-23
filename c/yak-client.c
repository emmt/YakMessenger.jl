#include "yak.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <readline/readline.h>
#include <readline/history.h>

#define BLACK   "\033[30m"
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define MAGENTA "\033[35m"
#define CYAN    "\033[36m"
#define WHITE   "\033[37m"
#define RESET   "\033[0m"

int main(int argc, char* argv[])
{
    const char* host = "localhost";
    int i1 = 1;
    while (i1 < argc) {
        if (strcmp(argv[i1], "--") == 0) {
            ++i1;
            break;
        }
        if (strcmp(argv[i1], "--help") == 0 || strcmp(argv[i1], "-h") == 0) {
            fprintf(stdout, "Syntax: %s [-h|--help] [--] [HOST] PORT\n", argv[0]);
            fprintf(stdout, "Connect to service PORT on HOST machine (\"localhost\" if not specified).\n");
            return 0;
        }
        if (argv[i1][0] == '-') {
            fprintf(stderr, "%s: unknown option \"%s\"\n", argv[0], argv[i1]);
            return 1;
        } else {
            break;
        }
        ++i1;
    }
    int n = argc - i1; /* number of positional arguments */
    if (n < 1 || n > 2) {
        fprintf(stderr, "%s: too %s arguments (try with \"--help\")\n", argv[0],
                (n < 1 ? "few" : "many"));
        return 1;
    }
    int port = 0;
    char dummy;
    if (sscanf(argv[i1], "%d %1c", &port, &dummy) != 1 || port <= 0) {
        fprintf(stderr, "%s: invalid port number.\n", argv[0]);
        return 1;
    }
    if (n >= 2) {
        host = argv[i1 + 1];
    }
    yak_connection conn;
    int status = yak_connect(&conn, host, port);
    if (status != 0) {
        fprintf(stderr, "%s: connection error (%d).\n", argv[0], status);
        return 1;
    }
    const char* prompt = YELLOW "cmd>" RESET " ";
    using_history();
    while (1) {
        char* line = readline(prompt);
        if (line == NULL) {
            break;
        }
        long len = strlen(line);
        if (len > 0) {
            add_history(line);
        }
        status = yak_send_message(&conn, 'X', line, len);
        free(line);
        if (status != 0) {
            fprintf(stderr, "%s: sending of command failed (%d).\n", argv[0], status);
            return 1;
        }
        char* buf;
        char type;
        status = yak_recv_message(&conn, &type, (void**)&buf, &len);
        if (status != 0) {
            fprintf(stderr, "%s: receiving answer failed (%d).\n", argv[0], status);
            return 1;
        }
        fputs(type == 'E' ? RED : CYAN, stdout);
        for (long i = 0; i < len; ++i) {
            fputc(buf[i], stdout);
        }
        fputs(RESET "\n", stdout);
        fflush(stdout);
        if (buf != NULL) {
            free(buf);
        }
    }
    yak_close(&conn);
    return 0;
}
