# OSISP Lab4 — Фильтр морзянки (прямой и обратный)
# make / make clean / make test

CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -pedantic
TARGET = morse_filter
OBJS = main.o morse.o io.o

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJS)

main.o: main.c morse.h io.h
	$(CC) $(CFLAGS) -c main.c

morse.o: morse.c morse.h
	$(CC) $(CFLAGS) -c morse.c

io.o: io.c io.h
	$(CC) $(CFLAGS) -c io.c

clean:
	rm -f $(OBJS) $(TARGET) test_morse.txt test_decode.txt

test: $(TARGET)
	@echo "--- Кодирование: текст -> Морзе ---"
	./$(TARGET) -e -o test_morse.txt test_input.txt
	@cat test_morse.txt
	@echo "--- Декодирование: Морзе -> текст ---"
	./$(TARGET) -d -o test_decode.txt test_morse.txt
	@cat test_decode.txt
