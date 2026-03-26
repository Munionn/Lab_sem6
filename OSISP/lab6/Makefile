CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -O2

SERVER = chat_server
CLIENT = chat_client

.PHONY: all clean

all: $(SERVER) $(CLIENT)

$(SERVER): server.c common.h
	$(CC) $(CFLAGS) server.c -o $(SERVER)

$(CLIENT): client.c common.h
	$(CC) $(CFLAGS) client.c -o $(CLIENT)

clean:
	rm -f $(SERVER) $(CLIENT)

