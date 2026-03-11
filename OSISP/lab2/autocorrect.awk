#
# Автокорректор: замена строчных на заглавные в начале предложений.
# Начало предложения = начало файла, либо после . ! ? (не внутри числа, напр. 3.14).
# Обрабатывает перенос: точка в одной строке, буква в следующей.
# Поддерживается латиница (a-z). Для кириллицы см. README.
#

function capitalize_first_letter(s,   i, c) {
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c ~ /[a-z]/) {
            return substr(s, 1, i-1) toupper(c) substr(s, i+1)
        }
        if (c ~ /[A-Za-z0-9]/) return s
    }
    return s
}

BEGIN {
    sent_start = 1
}

{
    line = $0

    if (sent_start && line ~ /[a-z]/) {     
        line = capitalize_first_letter(line)
    }
    sent_start = 0

    while (match(line, /[^0-9][.!?][ \t]*[a-z]/)) {
        pos = RSTART + RLENGTH - 1
        c = substr(line, pos, 1)
        line = substr(line, 1, pos-1) toupper(c) substr(line, pos+1)
    }

    if (line ~ /[.!?][ \t]*$/) {
        if (line !~ /[0-9]\.[ \t]*$/) sent_start = 1
    }

    print line
}
