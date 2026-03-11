# OSISP Lab3 — Инвертирующий фильтр (для символов)
# Сборка: make
# Очистка: make clean
# Тест:    make test

CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -pedantic
TARGET = invert_chars
OBJS = main.o reverse.o io.o

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJS)

main.o: main.c reverse.h io.h
	$(CC) $(CFLAGS) -c main.c

reverse.o: reverse.c reverse.h
	$(CC) $(CFLAGS) -c reverse.c

io.o: io.c io.h
	$(CC) $(CFLAGS) -c io.c

clean:
	rm -f $(OBJS) $(TARGET) test_output.txt

test: $(TARGET)
	./$(TARGET) -o test_output.txt test_input.txt
	@echo "--- test_input.txt ---"
	@cat test_input.txt
	@echo "--- test_output.txt (инверсия символов в строках) ---"
	@cat test_output.txt
