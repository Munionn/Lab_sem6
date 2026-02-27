"""
Лабораторная работа 2.
Приведение задачи линейного программирования
к нормальной и канонической формам.

Алгоритмы реализованы по методичке:
  - Нормальная форма:  max c^T x,  Ax <= b,  x >= 0
  - Каноническая форма: max c^T x,  Ax  = b,  x >= 0
"""

from fractions import Fraction
from copy import deepcopy

# ---------------------------------------------------------------------------
# Константы для знаков
# ---------------------------------------------------------------------------
LEQ = "<="     # ограничение типа <=
GEQ = ">="     # ограничение типа >=
EQ  = "="      # ограничение типа =

GEQ0 = ">=0"   # переменная >= 0
LEQ0 = "<=0"   # переменная <= 0
FREE = "free"  # переменная без ограничений на знак


# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

def _to_frac(lst):
    """Конвертировать список чисел в Fraction."""
    return [Fraction(x) for x in lst]


def _matrix_to_frac(matrix):
    return [[Fraction(x) for x in row] for row in matrix]


def _fmt_val(v):
    """Форматировать дробь: целые — без знаменателя."""
    f = Fraction(v)
    if f.denominator == 1:
        return str(f.numerator)
    return str(f)


def _fmt_vec(v):
    return "[" + ", ".join(_fmt_val(x) for x in v) + "]"


def _fmt_matrix(A):
    if not A:
        return "  []"
    lines = []
    for row in A:
        lines.append("  [" + ", ".join(_fmt_val(x) for x in row) + "]")
    return "\n".join(lines)


def _fmt_objective(c, direction="max"):
    """Строка вида '2x1 - x2 + 3x3 → max'."""
    terms = []
    for j, cj in enumerate(c):
        cj = Fraction(cj)
        var = f"x{j + 1}"
        if cj == 0:
            continue
        if cj == 1:
            terms.append(f"+{var}")
        elif cj == -1:
            terms.append(f"-{var}")
        elif cj > 0:
            terms.append(f"+{_fmt_val(cj)}{var}")
        else:
            terms.append(f"{_fmt_val(cj)}{var}")
    s = " ".join(terms).lstrip("+").replace("+-", "-") if terms else "0"
    return f"  f(x) = {s} → {direction}"


def _fmt_constraint(row, sign, bi):
    """Строка вида 'x1 + 2x2 - x3 <= 5'."""
    terms = []
    for j, aij in enumerate(row):
        aij = Fraction(aij)
        var = f"x{j + 1}"
        if aij == 0:
            continue
        if aij == 1:
            terms.append(f"+{var}")
        elif aij == -1:
            terms.append(f"-{var}")
        elif aij > 0:
            terms.append(f"+{_fmt_val(aij)}{var}")
        else:
            terms.append(f"{_fmt_val(aij)}{var}")
    lhs = " ".join(terms).lstrip("+").replace("+-", "-") if terms else "0"
    return f"  {lhs} {sign} {_fmt_val(bi)}"


def print_lp_full(c, d, A, b, r, sigma, title=""):
    """Красивый вывод ЗЛП в полной форме (с ограничениями на знаки)."""
    if title:
        print(f"\n{'='*55}")
        print(f"  {title}")
        print(f"{'='*55}")
    print(_fmt_objective(c, d))
    print("  Ограничения:")
    for i, (row, sign, bi) in enumerate(zip(A, r, b)):
        print(_fmt_constraint(row, sign, bi))
    print("  Ограничения на знаки переменных:")
    for j, s in enumerate(sigma):
        print(f"  x{j + 1} {s}")


def print_lp_result(c, A, b, direction="max", title=""):
    """Вывод результата (матричные c, A, b)."""
    if title:
        print(f"\n{'='*55}")
        print(f"  {title}")
        print(f"{'='*55}")
    print(_fmt_objective(c, direction))
    print(f"  c = {_fmt_vec(c)}")
    print(f"  A =\n{_fmt_matrix(A)}")
    print(f"  b = {_fmt_vec(b)}")


# ---------------------------------------------------------------------------
# Нормальная форма
# ---------------------------------------------------------------------------

def to_normal_form(c, d, A, b, r, sigma, verbose=True):
    """
    Привести ЗЛП к нормальной форме: max c^T x, Ax <= b, x >= 0.

    Параметры
    ---------
    c     : list  — коэффициенты целевого функционала
    d     : str   — 'min' или 'max'
    A     : list of lists — матрица ограничений
    b     : list  — правые части ограничений
    r     : list  — знаки ограничений ('<=' / '>=' / '=')
    sigma : list  — ограничения на знаки переменных ('>=0' / '<=0' / 'free')
    verbose: bool — печатать шаги

    Возвращает
    ----------
    (c, A, b) — нормальная форма (max, Ax <= b, x >= 0)
    """
    c     = _to_frac(c)
    A     = _matrix_to_frac(A)
    b     = _to_frac(b)
    r     = list(r)
    sigma = list(sigma)

    def log(msg):
        if verbose:
            print(msg)

    # Шаг 1. min → max
    if d == "min":
        c = [-ci for ci in c]
        d = "max"
        log("Шаг 1: d=min → умножаем c на -1, d=max")
        log(f"  c = {_fmt_vec(c)}")

    # Шаг 2. '=' → пара '<=' и '>='
    i = 0
    while i < len(r):
        if r[i] == EQ:
            log(f"Шаг 2: ограничение {i+1} '=' → заменяем на '<=' и '>='")
            A.insert(i + 1, A[i][:])
            b.insert(i + 1, b[i])
            r[i] = LEQ
            r.insert(i + 1, GEQ)
            i += 2
        else:
            i += 1

    # Шаг 3. '>=' → умножить на -1
    for i in range(len(r)):
        if r[i] == GEQ:
            log(f"Шаг 3: ограничение {i+1} '>=' → умножаем строку и b[{i+1}] на -1")
            A[i] = [-aij for aij in A[i]]
            b[i] = -b[i]
            r[i] = LEQ

    # Шаг 4. σ_i = '<=0' → умножить столбец на -1
    i = 0
    while i < len(sigma):
        if sigma[i] == LEQ0:
            log(f"Шаг 4: переменная x{i+1} '<=0' → умножаем столбец {i+1} и c[{i+1}] на -1")
            for row in A:
                row[i] = -row[i]
            c[i] = -c[i]
            sigma[i] = GEQ0
        i += 1

    # Шаг 5. σ_i = 'free' → xi = xi+ - xi-
    i = 0
    while i < len(sigma):
        if sigma[i] == FREE:
            log(f"Шаг 5: переменная x{i+1} свободная → xi = xi+ - xi-, добавляем столбец")
            for row in A:
                row.insert(i + 1, -row[i])
            c.insert(i + 1, -c[i])
            sigma[i]  = GEQ0
            sigma.insert(i + 1, GEQ0)
            i += 2
        else:
            i += 1

    return c, A, b

# ---------------------------------------------------------------------------
# Каноническая форма
# ---------------------------------------------------------------------------

def to_canonical_form(c, d, A, b, r, sigma, verbose=True):
    """
    Привести ЗЛП к канонической форме: max c^T x, Ax = b, x >= 0.

    Параметры — те же, что у to_normal_form.

    Возвращает
    ----------
    (c, A, b) — каноническая форма (max, Ax = b, x >= 0)
    """
    c     = _to_frac(c)
    A     = _matrix_to_frac(A)
    b     = _to_frac(b)
    r     = list(r)
    sigma = list(sigma)

    def log(msg):
        if verbose:
            print(msg)

    # Шаг 1. min → max
    if d == "min":
        c = [-ci for ci in c]
        d = "max"
        log("Шаг 1: d=min → умножаем c на -1, d=max")
        log(f"  c = {_fmt_vec(c)}")

    # Шаги 2 и 3. Добавляем балансирующие переменные
    for i in range(len(r)):
        m = len(A)
        if r[i] == LEQ:
            log(f"Шаг 2: ограничение {i+1} '<=' → добавляем slack-переменную (столбец e{i+1})")
            for j in range(m):
                A[j].append(Fraction(1) if j == i else Fraction(0))
            c.append(Fraction(0))
            sigma.append(GEQ0)
            r[i] = EQ
        elif r[i] == GEQ:
            log(f"Шаг 3: ограничение {i+1} '>=' → добавляем surplus-переменную (столбец -e{i+1})")
            for j in range(m):
                A[j].append(Fraction(-1) if j == i else Fraction(0))
            c.append(Fraction(0))
            sigma.append(GEQ0)
            r[i] = EQ

    # Шаг 4. σ_i = '<=0' → умножить столбец на -1
    i = 0
    while i < len(sigma):
        if sigma[i] == LEQ0:
            log(f"Шаг 4: переменная x{i+1} '<=0' → умножаем столбец {i+1} и c[{i+1}] на -1")
            for row in A:
                row[i] = -row[i]
            c[i] = -c[i]
            sigma[i] = GEQ0
        i += 1

    # Шаг 5. σ_i = 'free' → xi = xi+ - xi-
    i = 0
    while i < len(sigma):
        if sigma[i] == FREE:
            log(f"Шаг 5: переменная x{i+1} свободная → xi = xi+ - xi-, добавляем столбец")
            for row in A:
                row.insert(i + 1, -row[i])
            c.insert(i + 1, -c[i])
            sigma[i]  = GEQ0
            sigma.insert(i + 1, GEQ0)
            i += 2
        else:
            i += 1

    return c, A, b


# ---------------------------------------------------------------------------
# Демонстрация — задача (3) из методички
# ---------------------------------------------------------------------------

def demo():
    """
    Задача (3) из методички:

        -x1 + x2 - 2x3  →  min
        x1 + x3         <= 1
        x1 - x3         >= 2
        x1 + x2          = 10
        x1 >= 0,  x2 <= 0,  x3 — свободная
    """
    c     = [-1,  1, -2]
    d     = "min"
    A     = [[1, 0,  1],
             [1, 0, -1],
             [1, 1,  0]]
    b     = [1, 2, 10]
    r     = [LEQ, GEQ, EQ]
    sigma = [GEQ0, LEQ0, FREE]

    print_lp_full(c, d, A, b, r, sigma, title="Исходная задача (3)")

    # --- Нормальная форма ---
    print("\n" + "="*55)
    print("  АЛГОРИТМ → НОРМАЛЬНАЯ ФОРМА")
    print("="*55)
    c_n, A_n, b_n = to_normal_form(c, d, A, b, r, sigma, verbose=True)
    print_lp_result(c_n, A_n, b_n, direction="max",
                    title="Результат: нормальная форма (max, Ax<=b, x>=0)")

    # Ожидаемый результат из методички:
    # c = [1, 1, 2, -2]
    # A = [[1,0,1,-1], [-1,0,1,-1], [1,-1,0,0], [-1,1,0,0]]
    # b = [1, -2, 10, -10]

    # --- Каноническая форма ---
    print("\n" + "="*55)
    print("  АЛГОРИТМ → КАНОНИЧЕСКАЯ ФОРМА")
    print("="*55)
    c_k, A_k, b_k = to_canonical_form(c, d, A, b, r, sigma, verbose=True)
    print_lp_result(c_k, A_k, b_k, direction="max",
                    title="Результат: каноническая форма (max, Ax=b, x>=0)")

    # Ожидаемый результат из методички:
    # c = [1, 1, 2, -2, 0, 0]
    # A = [[1,0,1,-1,1,0], [1,0,-1,1,0,-1], [1,-1,0,0,0,0]]
    # b = [1, 2, 10]


# ---------------------------------------------------------------------------
# Интерактивный ввод
# ---------------------------------------------------------------------------

def input_lp():
    """Интерактивный ввод задачи ЛП."""
    print("\n" + "="*55)
    print("  ВВОД СВОЕЙ ЗАДАЧИ")
    print("="*55)

    n = int(input("Количество переменных n: "))
    m = int(input("Количество ограничений m: "))

    print(f"\nКоэффициенты целевого функционала c (через пробел, {n} чисел):")
    c = list(map(Fraction, input().split()))

    print("Направление оптимизации (min / max):")
    d = input().strip().lower()

    A, b, r = [], [], []
    print("\nВведите ограничения в формате: a1 a2 ... an  знак  b")
    print("  знак: <= / >= / =")
    for i in range(m):
        print(f"  Ограничение {i+1}: ", end="")
        parts = input().split()
        row  = list(map(Fraction, parts[:n]))
        sign = parts[n]
        bi   = Fraction(parts[n + 1])
        A.append(row)
        r.append(sign)
        b.append(bi)

    sigma = []
    print("\nОграничения на знаки переменных (>=0 / <=0 / free):")
    for j in range(n):
        print(f"  x{j+1}: ", end="")
        sigma.append(input().strip())

    print_lp_full(c, d, A, b, r, sigma, title="Введённая задача")

    print("\nВыберите преобразование:")
    print("  1 — нормальная форма")
    print("  2 — каноническая форма")
    print("  3 — обе формы")
    choice = input("Ваш выбор: ").strip()

    if choice in ("1", "3"):
        print("\n" + "="*55)
        print("  АЛГОРИТМ → НОРМАЛЬНАЯ ФОРМА")
        print("="*55)
        c_n, A_n, b_n = to_normal_form(c, d, A, b, r, sigma, verbose=True)
        print_lp_result(c_n, A_n, b_n, direction="max",
                        title="Результат: нормальная форма")

    if choice in ("2", "3"):
        print("\n" + "="*55)
        print("  АЛГОРИТМ → КАНОНИЧЕСКАЯ ФОРМА")
        print("="*55)
        c_k, A_k, b_k = to_canonical_form(c, d, A, b, r, sigma, verbose=True)
        print_lp_result(c_k, A_k, b_k, direction="max",
                        title="Результат: каноническая форма")



if __name__ == "__main__":
    demo()
