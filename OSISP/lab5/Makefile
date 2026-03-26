CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -O2 -pthread
TARGET = mt_sort
SRC = main.c

.PHONY: all clean run test

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET)

run: $(TARGET)
	./$(TARGET) 2000000 4

test: $(TARGET)
	./$(TARGET) 100000 1
	./$(TARGET) 100000 2
	./$(TARGET) 100000 4
	./$(TARGET) 100000 8

clean:
	rm -f $(TARGET)

