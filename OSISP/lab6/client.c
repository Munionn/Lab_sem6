#include "common.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

static void die(const char *msg) {
    perror(msg);
    exit(1);
}

static int send_line(int fd, const char *line) {
    size_t len = strlen(line);
    ssize_t sent = send(fd, line, len, 0);
    if (sent < 0 || (size_t)sent != len) {
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <server_ip> <port> <nickname>\n", argv[0]);
        return 1;
    }

    const char *ip = argv[1];
    int port = atoi(argv[2]);
    const char *nickname = argv[3];

    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Invalid port: %s\n", argv[2]);
        return 1;
    }
    if (strlen(nickname) == 0 || strlen(nickname) > MAX_NAME_LEN) {
        fprintf(stderr, "Nickname must be 1..%d chars\n", MAX_NAME_LEN);
        return 1;
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        die("socket");
    }

    struct sockaddr_in srv;
    memset(&srv, 0, sizeof(srv));
    srv.sin_family = AF_INET;
    srv.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip, &srv.sin_addr) != 1) {
        fprintf(stderr, "Invalid IP: %s\n", ip);
        close(sock);
        return 1;
    }

    if (connect(sock, (struct sockaddr *)&srv, sizeof(srv)) < 0) {
        die("connect");
    }

    char nick_cmd[MAX_LINE];
    snprintf(nick_cmd, sizeof(nick_cmd), "NICK %s\n", nickname);
    if (send_line(sock, nick_cmd) < 0) {
        die("send NICK");
    }

    printf("Connected to %s:%d as %s\n", ip, port, nickname);
    printf("Type messages and press Enter. Ctrl+D to quit.\n");

    while (1) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(sock, &readfds);
        FD_SET(STDIN_FILENO, &readfds);
        int maxfd = (sock > STDIN_FILENO) ? sock : STDIN_FILENO;

        int ready = select(maxfd + 1, &readfds, NULL, NULL, NULL);
        if (ready < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("select");
        }

        if (FD_ISSET(sock, &readfds)) {
            char buf[MAX_LINE];
            ssize_t n = recv(sock, buf, sizeof(buf) - 1, 0);
            if (n <= 0) {
                printf("Disconnected from server.\n");
                break;
            }
            buf[n] = '\0';
            printf("%s", buf);
            fflush(stdout);
        }

        if (FD_ISSET(STDIN_FILENO, &readfds)) {
            char line[MAX_LINE];
            if (fgets(line, sizeof(line), stdin) == NULL) {
                break;
            }
            if (send_line(sock, line) < 0) {
                printf("Failed to send message.\n");
                break;
            }
        }
    }

    close(sock);
    return 0;
}

