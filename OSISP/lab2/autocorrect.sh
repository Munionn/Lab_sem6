#!/usr/bin/env bash
#
# OSISP Lab2 — «Автокорректор» (заглавные буквы).
# Замена строчных на заглавные в начале предложений:
# - в начале документа;
# - после точки, восклицательного или вопросительного знака (не внутри числа, например 3.14);
# - после переноса строки, если предыдущая строка заканчивалась на . ! ?
#
# Использование: ./autocorrect.sh [ФАЙЛ...]
# Без аргументов — чтение из stdin.
# Вывод — в stdout; при ошибках — сообщения в stderr.
#

set -u
AWK_SCRIPT="$(dirname "$0")/autocorrect.awk"

usage() {
    echo "Использование: $0 [ФАЙЛ ...]"
    echo "  Читает файл(ы) или stdin, выводит текст с заглавными буквами в начале предложений."
    echo "  Предложение: начало файла или после . ! ? (не после цифры, напр. 3.14)."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

run_awk() {
    if [[ ! -f "$AWK_SCRIPT" ]]; then
        echo "Ошибка: не найден скрипт $AWK_SCRIPT" >&2
        return 1
    fi
    awk -f "$AWK_SCRIPT" "$@"
    return $?
}

    if [[ $# -eq 0 ]]; then
        run_awk
        exit $?
    fi

exit_code=0
for f in "$@"; do
    if [[ "$f" == "-" ]]; then
        run_awk || exit_code=1
    elif [[ ! -e "$f" ]]; then
        echo "Ошибка: файл не найден: $f" >&2
        exit_code=1
    elif [[ -d "$f" ]]; then
        echo "Ошибка: это директория, не файл: $f" >&2
        exit_code=1
    elif [[ ! -r "$f" ]]; then
        echo "Ошибка: нет прав на чтение: $f" >&2
        exit_code=1
    else
        run_awk "$f" || exit_code=1
    fi
done
exit $exit_code
