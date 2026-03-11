#include "reverse.h"

void reverse_chars(char *buf, size_t len) {
    if (len == 0) return;
    size_t i = 0;
    size_t j = len - 1;
    while (i < j) {
        char t = buf[i];
        buf[i] = buf[j];
        buf[j] = t;
        i++;
        j--;
    }
}
