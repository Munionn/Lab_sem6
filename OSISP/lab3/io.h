#ifndef IO_H
#define IO_H

#include <stddef.h>
#include <stdio.h>

#define MAX_LINE 4096

/*
 * Читает одну строку (до '\n' или EOF) в buf, не более max_size-1 символов.
 * Добавляет '\0'. Пропускает символ новой строки.
 * Возвращает длину прочитанной строки (без '\0'), 0 при EOF, (size_t)-1 при ошибке.
 */
size_t read_line(char *buf, size_t max_size, FILE *fp);

#endif
