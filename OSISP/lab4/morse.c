#include "morse.h"
#include <string.h>

static const struct {
    char c;
    const char *code;
} morse_table[] = {
    {'A', ".-"},    {'B', "-..."},   {'C', "-.-."},   {'D', "-.."},    {'E', "."},
    {'F', "..-."},  {'G', "--."},    {'H', "...."},   {'I', ".."},     {'J', ".---"},
    {'K', "-.-"},   {'L', ".-.."},   {'M', "--"},     {'N', "-."},     {'O', "---"},
    {'P', ".--."},  {'Q', "--.-"},   {'R', ".-."},    {'S', "..."},    {'T', "-"},
    {'U', "..-"},   {'V', "...-"},   {'W', ".--"},    {'X', "-..-"},   {'Y', "-.--"},
    {'Z', "--.."},
    {'0', "-----"}, {'1', ".----"}, {'2', "..---"}, {'3', "...--"}, {'4', "....-"},
    {'5', "....."}, {'6', "-...."}, {'7', "--..."}, {'8', "---.."}, {'9', "----."},
    {'.', ".-.-.-"}, {',', "--..--"}, {'?', "..--.."}, {'/', "-..-."},
    {' ', " "},  /* пробел между словами */
    {0, NULL}
};

size_t morse_encode_char(char c, char *buf, size_t buf_size) {
    if (buf_size == 0 || !buf) return 0;
    if (c == '\n') {
        buf[0] = '\n';
        buf[1] = '\0';
        return 1;
    }
    if (c >= 'a' && c <= 'z') c = (char)(c - 32);
    for (size_t i = 0; morse_table[i].code != NULL; i++) {
        if (morse_table[i].c == c) {
            size_t len = strlen(morse_table[i].code);
            if (len >= buf_size) return 0;
            memcpy(buf, morse_table[i].code, len + 1);
            return len;
        }
    }
    return 0; /* непреобразуемый — отбрасываем */
}

char morse_decode(const char *morse) {
    if (!morse) return '\0';
    for (size_t i = 0; morse_table[i].code != NULL; i++) {
        if (strcmp(morse_table[i].code, morse) == 0)
            return morse_table[i].c;
    }
    return '\0';
}
