#!/usr/bin/env bash
#
# OSISP Lab1 — поиск файлов с обходом дерева каталогов (аналог find).
# Режимы: по регулярному выражению (имя) или по списку имён.
# Действия: листинг с номерами строк (для файлов с заданным заголовком),
#           подсчёт суммы байтов по файлам и общей суммы.
#
# Использование:
#   ./find_files.sh --regex "PATTERN" [--listing] [--sum] [OUTPUT_FILE]
#   ./find_files.sh --names NAME1 NAME2 ... [--listing] [--sum] [OUTPUT_FILE]
#

set -u

FIXED_HEADER="#!/"
OUTPUT_FILE="${OUTPUT_FILE:-find_results.txt}"
SEARCH_DIR="${SEARCH_DIR:-.}"
TMP_LIST=$(mktemp)
trap 'rm -f "$TMP_LIST"' EXIT

usage() {
    echo "Использование:"
    echo "  $0 --regex PATTERN [--listing] [--sum] [OUTPUT_FILE]"
    echo "  $0 --names NAME1 [NAME2 ...] [--listing] [--sum] [OUTPUT_FILE]"
    echo ""
    echo "  --regex PATTERN   поиск по регулярному выражению (имя файла)"
    echo "  --names N1 N2 ... поиск по списку имён (совпадение с любым)"
    echo "  --listing         действие: листинг с номерами строк (файлы с заголовком)"
    echo "  --sum             действие: сумма байтов по файлам и общая сумма"
    echo "  OUTPUT_FILE       файл результатов (по умолчанию: find_results.txt)"
}

MODE=""
PATTERN=""
NAMES=()
DO_LISTING=false
DO_SUM=false
CUSTOM_OUTPUT=""

# Разбор аргументов
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    a="${args[$i]}"
    case "$a" in
        --regex)
            MODE="regex"
            PATTERN="${args[$((i+1))]}"
            ((i+=2)) || true
            ;;
        --names)
            MODE="names"
            ((i++)) || true
            while [[ $i -lt ${#args[@]} ]]; do
                n="${args[$i]}"
                [[ "$n" == --* ]] && break
                NAMES+=("$n")
                ((i++)) || true
            done
            ;;
        --listing)
            DO_LISTING=true
            ((i++)) || true
            ;;
        --sum)
            DO_SUM=true
            ((i++)) || true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$MODE" ]]; then
                echo "Ошибка: укажите --regex PATTERN или --names NAME1 NAME2 ..." >&2
                usage >&2
                exit 1
            fi
            if [[ "$a" == */* || "$a" == *.txt ]]; then
                CUSTOM_OUTPUT="$a"
            fi
            ((i++)) || true
            ;;
    esac
done

[[ -n "$CUSTOM_OUTPUT" ]] && OUTPUT_FILE="$CUSTOM_OUTPUT"

if [[ "$MODE" == "names" && ${#NAMES[@]} -eq 0 ]]; then
    echo "Ошибка: для --names укажите хотя бы одно имя файла." >&2
    exit 1
fi

if [[ -z "$MODE" ]]; then
    echo "Ошибка: укажите --regex PATTERN или --names NAME1 NAME2 ..." >&2
    usage >&2
    exit 1
fi

if ! "$DO_LISTING" && ! "$DO_SUM"; then
    DO_LISTING=true
    DO_SUM=true
fi

# Поиск файлов в дереве каталогов
if [[ "$MODE" == "regex" ]]; then
    find "$SEARCH_DIR" -type f 2>/dev/null | while IFS= read -r f; do
        basename "$f" | grep -qE "$PATTERN" && echo "$f"
    done > "$TMP_LIST"
else
    find "$SEARCH_DIR" -type f 2>/dev/null | while IFS= read -r f; do
        base=$(basename "$f")
        for n in "${NAMES[@]}"; do
            if [[ "$base" == "$n" ]]; then
                echo "$f"
                break
            fi
        done
    done > "$TMP_LIST"
fi

# Перенаправление вывода в файл
exec 3>&1
exec > "$OUTPUT_FILE"

echo "=============================================="
echo "Результаты поиска файлов"
echo "Дата: $(date)"
echo "Директория поиска: $SEARCH_DIR"
echo "Режим: $MODE"
[[ "$MODE" == "regex" ]] && echo "Шаблон: $PATTERN"
[[ "$MODE" == "names" ]] && echo "Список имён: ${NAMES[*]}"
echo "=============================================="
echo ""

# В режиме --names: показать, какие имена найдены, какие нет
if [[ "$MODE" == "names" && ${#NAMES[@]} -gt 0 ]]; then
    echo "--- Соответствие списку имён ---"
    found_names=()
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        base=$(basename "$path")
        found_names+=("$base")
    done < "$TMP_LIST"
    for n in "${NAMES[@]}"; do
        found=false
        for f in "${found_names[@]}"; do
            if [[ "$f" == "$n" ]]; then found=true; break; fi
        done
        if $found; then
            echo "  Найдено:    $n"
        else
            echo "  Не найдено: $n (нет в дереве $SEARCH_DIR)"
        fi
    done
    echo ""
fi

# Действие: листинг с номерами строк для файлов с заданным заголовком
if "$DO_LISTING"; then
    echo "--- Листинг файлов с заголовком \"$FIXED_HEADER\" (построчно с номерами) ---"
    count=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
            if [[ -f "$path" ]]; then
                first=$(head -n 1 "$path" 2>/dev/null || true)
                if [[ "$first" == "$FIXED_HEADER"* ]]; then
                    echo ""
                    echo ">>> $path"
                    awk '{ printf "  %6d  %s\n", NR, $0 }' "$path" 2>/dev/null || true
                    count=$((count + 1))
                fi
            fi
    done < "$TMP_LIST"
    echo ""
    echo "Всего файлов с заданным заголовком: $count"
    echo ""
fi

# Действие: сумма байтов по каждому файлу и общая сумма
if "$DO_SUM"; then
    echo "--- Сумма байтов (размер) по файлам ---"
    total=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ -f "$path" ]]; then
            bytes=$(wc -c < "$path" 2>/dev/null || echo 0)
            printf "  %10d  %s\n" "$bytes" "$path"
            total=$((total + bytes))
        fi
    done < "$TMP_LIST"
    echo "-------------------------------------------"
    printf "  %10d  ИТОГО (байт)\n" "$total"
    echo ""
fi

echo "Результаты записаны в файл: $OUTPUT_FILE"
exec 1>&3 3>&-

echo "Готово. Результаты в $OUTPUT_FILE" >&2
