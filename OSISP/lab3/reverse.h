#ifndef REVERSE_H
#define REVERSE_H

#include <stddef.h>

/* Разворачивает порядок символов в буфере [buf, buf+len) на месте. */
void reverse_chars(char *buf, size_t len);

#endif
