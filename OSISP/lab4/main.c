/*
 * Фильтр морзянки: прямое (текст -> Морзе) и обратное (Морзе -> текст) преобразование.
 * Использование: morse_filter -e [ -o out ] [ input ]   (encode)
 *               morse_filter -d [ -o out ] [ input ]   (decode)
 */

#include "morse.h"
#include "io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MODE_NONE 0
#define MODE_ENCODE 1
#define MODE_DECODE 2

static int mode = MODE_NONE;
static const char *out_path = NULL;
static const char *in_path = NULL;

static void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-e") == 0) {
            mode = MODE_ENCODE;
        } else if (strcmp(argv[i], "-d") == 0) {
            mode = MODE_DECODE;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Ошибка: после -o укажите файл\n");
                exit(EXIT_FAILURE);
            }
            out_path = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Использование: %s -e | -d [ -o выходной_файл ] [ входной_файл ]\n", argv[0]);
            printf("  -e  текст -> азбука Морзе (непреобразуемые символы отбрасываются)\n");
            printf("  -d  азбука Морзе -> текст (нераспознанные комбинации: [?код])\n");
            exit(EXIT_SUCCESS);
        } else if (in_path == NULL) {
            in_path = argv[i];
        } else {
            fprintf(stderr, "Лишний аргумент: %s\n", argv[i]);
            exit(EXIT_FAILURE);
        }
    }
}

static void do_encode(FILE *in, FILE *out) {
    int c;
    char buf[MORSE_CODE_MAX];
    int need_space = 0;  /* пробел перед следующей буквой */
    while ((c = fgetc(in)) != EOF) {
        if (c == '\n') {
            fprintf(out, "\n");
            need_space = 0;
            continue;
        }
        size_t n = morse_encode_char((char)c, buf, sizeof buf);
        if (n == 0) continue;
        if (buf[0] == '\n') {
            fputc('\n', out);
            need_space = 0;
            continue;
        }
        if (buf[0] == ' ') {
            fprintf(out, " / ");
            need_space = 0;
            continue;
        }
        if (need_space) fprintf(out, " ");
        fprintf(out, "%s", buf);
        need_space = 1;
    }
}

static void do_decode(FILE *in, FILE *out) {
    char line[MAX_LINE];
    char token[128];
    size_t j;
    int after_letter = 0;
    while (read_line(line, sizeof line, in) != (size_t)-1) {
        after_letter = 0;
        for (size_t i = 0; line[i]; ) {
            if (line[i] == ' ' || line[i] == '\t') {
                size_t start = i;
                int saw_slash = 0;
                while (line[i] == ' ' || line[i] == '\t') {
                    if (i + 2 < sizeof line && line[i] == ' ' && line[i+1] == '/' && line[i+2] == ' ') {
                        saw_slash = 1;
                        i += 3;
                        break;
                    }
                    i++;
                }
                if (after_letter && (saw_slash || (i - start) > 1))
                    fputc(' ', out);
                after_letter = 0;
                continue;
            }
            j = 0;
            while (line[i] && line[i] != ' ' && line[i] != '\t' && j < sizeof token - 1) {
                if (line[i] == '.' || line[i] == '-')
                    token[j++] = line[i];
                i++;
            }
            token[j] = '\0';
            if (j == 0) continue;
            char dec = morse_decode(token);
            if (dec)
                fputc(dec, out);
            else
                fprintf(out, "[?%s]", token);
            after_letter = 1;
        }
        fprintf(out, "\n");
        if (feof(in)) break;
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    if (mode == MODE_NONE) {
        fprintf(stderr, "Укажите режим: -e (кодировать) или -d (декодировать)\n");
        return EXIT_FAILURE;
    }

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

    if (mode == MODE_ENCODE)
        do_encode(in, out);
    else
        do_decode(in, out);

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
