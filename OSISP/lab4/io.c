#include "io.h"

size_t read_line(char *buf, size_t max_size, FILE *fp) {
    if (max_size == 0 || !buf || !fp) return (size_t)-1;
    size_t i = 0;
    int c;
    while (i < max_size - 1) {
        c = fgetc(fp);
        if (c == EOF) { buf[i] = '\0'; return i; }
        if (c == '\n') { buf[i] = '\0'; return i; }
        buf[i++] = (char)c;
    }
    buf[i] = '\0';
    while ((c = fgetc(fp)) != EOF && c != '\n')
        ;
    return i;
}
