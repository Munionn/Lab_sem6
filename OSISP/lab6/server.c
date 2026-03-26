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

typedef struct {
    int fd;
    char name[MAX_NAME_LEN + 1];
    int named;
} client_t;

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

static void broadcast(client_t clients[], int sender_fd, const char *line) {
    for (int i = 0; i < MAX_CLIENTS; ++i) {
        if (clients[i].fd <= 0) {
            continue;
        }
        if (clients[i].fd == sender_fd) {
            continue;
        }
        if (send_line(clients[i].fd, line) < 0) {
        }
    }
}

static int add_client(client_t clients[], int fd) {
    for (int i = 0; i < MAX_CLIENTS; ++i) {
        if (clients[i].fd == 0) {
            clients[i].fd = fd;
            clients[i].name[0] = '\0';
            clients[i].named = 0;
            return i;
        }
    }
    return -1;
}

static void remove_client(client_t clients[], int idx) {
    if (clients[idx].fd > 0) {
        close(clients[idx].fd);
    }
    clients[idx].fd = 0;
    clients[idx].name[0] = '\0';
    clients[idx].named = 0;
}

static int parse_line(char *buffer) {
    size_t len = strlen(buffer);
    while (len > 0 && (buffer[len - 1] == '\n' || buffer[len - 1] == '\r')) {
        buffer[len - 1] = '\0';
        len--;
    }
    return (int)len;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <port>\n", argv[0]);
        return 1;
    }

    int port = atoi(argv[1]);
    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Invalid port: %s\n", argv[1]);
        return 1;
    }

    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        die("socket");
    }

    int reuse = 1;
    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        die("setsockopt");
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((uint16_t)port);

    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        die("bind");
    }
    if (listen(listen_fd, 16) < 0) {
        die("listen");
    }

    client_t clients[MAX_CLIENTS];
    memset(clients, 0, sizeof(clients));

    printf("Chat server started on port %d\n", port);
    printf("Protocol: first send 'NICK <name>', then send plain lines as messages.\n");

    while (1) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(listen_fd, &readfds);
        int maxfd = listen_fd;

        for (int i = 0; i < MAX_CLIENTS; ++i) {
            if (clients[i].fd > 0) {
                FD_SET(clients[i].fd, &readfds);
                if (clients[i].fd > maxfd) {
                    maxfd = clients[i].fd;
                }
            }
        }

        int ready = select(maxfd + 1, &readfds, NULL, NULL, NULL);
        if (ready < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("select");
        }

        if (FD_ISSET(listen_fd, &readfds)) {
            struct sockaddr_in cli_addr;
            socklen_t cli_len = sizeof(cli_addr);
            int conn_fd = accept(listen_fd, (struct sockaddr *)&cli_addr, &cli_len);
            if (conn_fd >= 0) {
                int idx = add_client(clients, conn_fd);
                if (idx < 0) {
                    const char *full = "Server full, try later.\n";
                    send_line(conn_fd, full);
                    close(conn_fd);
                } else {
                    char ip[64];
                    inet_ntop(AF_INET, &cli_addr.sin_addr, ip, sizeof(ip));
                    printf("Client connected: fd=%d from %s:%d\n",
                           conn_fd, ip, ntohs(cli_addr.sin_port));
                    send_line(conn_fd, "Welcome. Set nickname: NICK <name>\n");
                }
            }
        }

        for (int i = 0; i < MAX_CLIENTS; ++i) {
            if (clients[i].fd <= 0 || !FD_ISSET(clients[i].fd, &readfds)) {
                continue;
            }

            char line[MAX_LINE];
            ssize_t n = recv(clients[i].fd, line, sizeof(line) - 1, 0);
            if (n <= 0) {
                if (clients[i].named) {
                    char out[MAX_LINE];
                    snprintf(out, sizeof(out), "[server] %s left the chat\n", clients[i].name);
                    broadcast(clients, clients[i].fd, out);
                }
                printf("Client disconnected: fd=%d\n", clients[i].fd);
                remove_client(clients, i);
                continue;
            }

            line[n] = '\0';
            parse_line(line);
            if (line[0] == '\0') {
                continue;
            }

            if (!clients[i].named) {
                if (strncmp(line, "NICK ", 5) != 0) {
                    send_line(clients[i].fd, "Please set nickname: NICK <name>\n");
                    continue;
                }
                const char *name = line + 5;
                if (*name == '\0' || strlen(name) > MAX_NAME_LEN) {
                    send_line(clients[i].fd, "Invalid name length.\n");
                    continue;
                }
                strncpy(clients[i].name, name, MAX_NAME_LEN);
                clients[i].name[MAX_NAME_LEN] = '\0';
                clients[i].named = 1;

                char out[MAX_LINE];
                snprintf(out, sizeof(out), "[server] %s joined the chat\n", clients[i].name);
                broadcast(clients, clients[i].fd, out);
                send_line(clients[i].fd, "[server] nickname accepted\n");
                continue;
            }

            char out[MAX_LINE];
            snprintf(out, sizeof(out), "[%s] %s\n", clients[i].name, line);
            broadcast(clients, clients[i].fd, out);
            printf("%s", out);
        }
    }

    close(listen_fd);
    return 0;
}

