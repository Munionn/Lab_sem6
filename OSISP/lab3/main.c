/*
 * Инвертирующий фильтр (для символов).
 * Разворачивает порядок символов в каждой строке; порядок строк не меняется.
 * Использование: invert_chars [ -o выходной_файл ] [ входной_файл ]
 */

#include "reverse.h"
#include "io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *out_path = NULL;
static const char *in_path = NULL;

static void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Ошибка: после -o укажите имя файла\n");
                exit(EXIT_FAILURE);
            }
            out_path = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Использование: %s [ -o выходной_файл ] [ входной_файл ]\n", argv[0]);
            printf("  Разворачивает символы в каждой строке. Без файлов: stdin -> stdout.\n");
            exit(EXIT_SUCCESS);
        } else if (in_path == NULL) {
            in_path = argv[i];
        } else {
            fprintf(stderr, "Ошибка: лишний аргумент '%s'\n", argv[i]);
            exit(EXIT_FAILURE);
        }
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);

    FILE *in = stdin;
    if (in_path) {
        in = fopen(in_path, "r");
        if (!in) {
            perror(in_path);
            return EXIT_FAILURE;
        }
    }

    FILE *out = stdout;
    if (out_path) {
        out = fopen(out_path, "w");
        if (!out) {
            perror(out_path);
            if (in != stdin) fclose(in);
            return EXIT_FAILURE;
        }
    }

    char line[MAX_LINE];
    size_t n;
    while ((n = read_line(line, sizeof line, in)) != (size_t)-1) {
        if (n > 0)
            reverse_chars(line, n);
        fprintf(out, "%s\n", line);
        if (n == 0 && feof(in))
            break;
    }

    if (ferror(in)) {
        perror("Чтение");
        if (in != stdin) fclose(in);
        if (out != stdout) fclose(out);
        return EXIT_FAILURE;
    }

    if (in != stdin) fclose(in);
    if (out != stdout) fclose(out);
    return EXIT_SUCCESS;
}
