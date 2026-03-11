#ifndef IO_H
#define IO_H

#include <stddef.h>
#include <stdio.h>

#define MAX_LINE 2048

size_t read_line(char *buf, size_t max_size, FILE *fp);

#endif
