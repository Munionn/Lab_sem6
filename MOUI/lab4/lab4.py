
from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable, Literal, Tuple

import numpy as np

# Подключение модулей из lab1/lab3
MOUI_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(MOUI_ROOT))

from lab3.simplex import simplex_main_phase


Status = Literal["optimal", "unbounded"]


def _banner(title: str) -> None:
    line = "=" * 60
    print(f"\n{line}\n{title}\n{line}")


def _fmt_int_list(values: Iterable[int]) -> str:
    return "[" + ", ".join(str(v) for v in values) + "]"


def simplex_main_phase_with_basis(
    c: np.ndarray,
    A: np.ndarray,
    x: np.ndarray,
    B: Iterable[int],
    *,
    verbose: bool = False,
    tol: float = 1e-10,
) -> Tuple[Status, np.ndarray, list[int]]:
    """
    Нужна только чтобы вернуть (status, x_opt, B_opt) в lab4.
    """
    status, x_opt, B_opt = simplex_main_phase(
        c, A, x, B, verbose=verbose, return_basis=True
    )
    return status, x_opt, B_opt


def simplex_initial_phase(
    c: np.ndarray,
    A: np.ndarray,
    b: np.ndarray,
    *,
    verbose: bool = True,
    tol: float = 1e-10,
) -> Tuple[Literal["feasible", "infeasible"], np.ndarray | None, list[int] | None, np.ndarray, np.ndarray]:

    c = np.asarray(c, dtype=float).flatten()
    A = np.asarray(A, dtype=float)
    b = np.asarray(b, dtype=float).flatten()

    if A.ndim != 2:
        raise ValueError("A должен быть двумерной матрицей.")
    m, n = A.shape
    if not (len(c) == n and len(b) == m):
        raise ValueError("Несовпадение размеров c, A, b.")

    A_cur = A.copy()
    b_cur = b.copy()

    if verbose:
        print("\nИсходная задача:")
        print(f"  c = {_fmt_int_list([int(v) for v in c])}")
        print("  A =")
        print(A.astype(int) if np.all(np.mod(A, 1) == 0) else A)
        print(f"  b = {_fmt_int_list([int(v) for v in b])}")

    _banner("ШАГ 1: Преобразование вектора b к неотрицательному виду") if verbose else None

    # Шаг 1: обеспечим b >= 0
    for i in range(m):
        if b_cur[i] < -tol:
            A_cur[i, :] *= -1
            b_cur[i] *= -1

    if verbose:
        print(f"b после преобразования: {b_cur}")
        print("A после преобразования:")
        print(A_cur)

    _banner("ШАГ 2: Составление вспомогательной задачи") if verbose else None
    # Шаг 2: вспомогательная задача
    eA = np.hstack([A_cur, np.eye(m)])
    ec = np.concatenate([np.zeros(n), -np.ones(m)])
    if verbose:
        print(f"Исходное n = {n}, m = {m}")
        print(f"Размер вспомогательной задачи: {n + m} переменных")
        print(f"c_aux = {ec}")
        print("A_aux =")
        print(eA)

    _banner("ШАГ 3: Построение начального БДП вспомогательной задачи") if verbose else None
    # Шаг 3: начальный базисный допустимый план для вспомогательной задачи
    ex0 = np.concatenate([np.zeros(n), b_cur.copy()])
    B_aux = list(range(n, n + m))  # (n+1..n+m) в 0-based

    if verbose:
        print(f"x_aux = {ex0}")
        print(f"B_aux = {[j + 1 for j in B_aux]} (искусственные переменные)")

    _banner("ШАГ 4: Решение вспомогательной задачи (основная фаза из Лаб 3)") if verbose else None
    # Шаг 4: решаем вспомогательную задачу основной фазой
    status, ex_opt, B_opt = simplex_main_phase_with_basis(
        ec, eA, ex0, B_aux, verbose=verbose, tol=tol
    )
    if status != "optimal" or ex_opt is None:
        # В теории фаза I ограничена сверху, но на всякий случай.
        return "infeasible", None, None, A_cur, b_cur

    if verbose:
        print("Достигнут оптимальный план\n")
        print(f"Оптимальный план вспомогательной задачи: x = {ex_opt}")
        print(f"Базисные индексы: B = {[bi + 1 for bi in B_opt]}")

    _banner("ШАГ 5: Проверка условий совместности") if verbose else None
    # Шаг 5: проверка совместности по искусственным переменным
    artificial = ex_opt[n : n + m]
    if not np.all(np.abs(artificial) <= 1e-7):
        if verbose:
            print("Шаг 5: искусственные переменные не равны нулю → задача несовместна.")
        return "infeasible", None, None, A_cur, b_cur
    if verbose:
        print("\nВсе искусственные переменные равны 0 - задача совместна")

    _banner("ШАГ 6: Формирование допустимого плана исходной задачи") if verbose else None
    # Шаг 6: формируем допустимый план x для исходной задачи
    x = ex_opt[:n].copy()
    if verbose:
        print(f"x (первые {n} компонент) = {x.tolist()}")

    _banner("ШАГ 7-9: Корректировка базисных индексов (удаление искусственных)") if verbose else None
    # Шаги 7–9: корректируем базис, убирая искусственные переменные
    B = B_opt.copy()  # упорядоченный базисный набор индексов (0-based)
    A_work = A_cur
    b_work = b_cur
    m_work = m

    # eA соответствует текущей A_work и текущему числу ограничений m_work
    eA_work = np.hstack([A_work, np.eye(m_work)])

    correction_iter = 0
    while True:
        correction_iter += 1
        if verbose:
            print(f"\n--- Итерация корректировки {correction_iter} ---")
        # Шаг 7: если B только из {0..n-1}, то ответ найден
        if all(j < n for j in B):
            AB = A_work[:, B]
            x_new = np.zeros(n, dtype=float)
            x_new[B] = np.linalg.solve(AB, b_work)
            x_new[np.abs(x_new) <= 1e-8] = 0.0
            x = x_new

            if verbose:
                print("В базисе нет искусственных переменных")
                _banner("РЕЗУЛЬТАТ НАЧАЛЬНОЙ ФАЗЫ СИМПЛЕКС-МЕТОДА")
                print(f"Базисный допустимый план: x = {x.tolist()}")
                print(f"Базисные индексы: B = {[bi + 1 for bi in B]} (1-based)")
                print("Матрица A:")
                print(A_work)
                print(f"Вектор b: {b_work}")
                print("=" * 60)
                print("\nУспешно найден начальный БДП!")
            return "feasible", x, B, A_work, b_work

        # Шаг 8: выбираем в B максимальный искусственный индекс
        artificial_positions = [(pos, B[pos]) for pos in range(len(B)) if B[pos] >= n]
        kpos, jk = max(artificial_positions, key=lambda t: t[1])
        if verbose:
            print(f"Искусственная переменная в базисе: x{jk + 1} (позиция {kpos + 1} в B)")

        # i — номер искусственной переменной в текущем нумеровании (0-based)
        i = jk - n

        # Вычислим eA_B^{-1} на текущем B
        eA_B = eA_work[:, B]
        try:
            eA_B_inv = np.linalg.inv(eA_B)
        except np.linalg.LinAlgError:
            # На практике при корректном плане это не должно происходить.
            # Если происходит — считаем, что задачу некорректно обработали базисом.
            if verbose:
                print("Предупреждение: базисная матрица вспомогательной задачи необратима.")
            return "infeasible", None, None, A_work, b_work

        replaced = False
        # Шаг 8 (продолжение): ищем j из {0..n-1}\B с (l(j))_k != 0
        B_set = set(B)
        for j in range(n):
            if j in B_set:
                continue
            l = eA_B_inv @ eA_work[:, j]
            if verbose:
                print(f"  Проверка x{j + 1}: l[{kpos}] = {l[kpos]}")
            if abs(l[kpos]) > tol:
                if verbose:
                    print(f"  Найдена замена -> меняем x{jk + 1} на x{j + 1}")
                B[kpos] = j
                replaced = True
                break

        if replaced:
            continue

        # Шаг 9: i-е основное ограничение линейно выражается → удаляем
        if verbose:
            print(f"  Не найдена замена -> удаляем ограничение {i + 1}")

        # Удаляем i-ю строку из A_work и b_work
        A_work = np.delete(A_work, i, axis=0)
        b_work = np.delete(b_work, i, axis=0)
        m_work -= 1
        if verbose:
            print(f"  Новое количество ограничений: m = {m_work}")

        # Удаляем индекс искусственной переменной jk из базиса (это элемент позиции kpos)
        del B[kpos]

        # После уменьшения числа ограничений искусственные переменные переиндексируются:
        # n + t (t > i) → n + (t - 1), то есть индекс искусственной переменной уменьшается на 1.
        for p in range(len(B)):
            if B[p] >= n:
                if B[p] > jk:
                    B[p] -= 1

        # Обновляем eA_work = [A_work, I_{m_work}]
        # При m_work = 0 искусственных переменных нет, поэтому eA_work имеет размер (0, n).
        if m_work > 0:
            eA_work = np.hstack([A_work, np.eye(m_work)])
        else:
            eA_work = A_work.copy()


def run_example_from_pdf(verbose: bool = True) -> None:
    """
    Пример из конца методички к Lab 4.
    """
    # (P) из примера в PDF:
    # x1 → max
    # x1 + x2 + x3 = 0
    # 2x1 + 2x2 + 2x3 = 0
    # x >= 0
    c = np.array([1.0, 0.0, 0.0])
    A = np.array(
        [
            [1.0, 1.0, 1.0],
            [2.0, 2.0, 2.0],
        ]
    )
    b = np.array([-10.0, 0.0])

    if verbose:
        _banner("ЛАБОРАТОРНАЯ РАБОТА №4\nНачальная фаза симплекс-метода")
        _banner("ПРИМЕР 1: Задача из lab4.pdf")

    status, x, B, A_red, b_red = simplex_initial_phase(c, A, b, verbose=verbose)
    if status != "feasible":
        print("Задача по примеру из PDF оказалась несовместной (что противоречит ожиданию).")
        return

    # Ожидаемо: x = (0,0,0), B = {1}
    print("\n=== Проверка ожидаемого результата ===")
    print(f"Получено: x = {x}, B = {[bi + 1 for bi in B]}")
    print(f"Ожидается: x = (0,0,0), B = [1]")
    print("A_red и b_red также выведены выше.")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Лабораторная работа 4: начальная фаза симплекс-метода")
    parser.add_argument("--quiet", action="store_true", help="Минимум вывода")
    parser.add_argument("--example", action="store_true", help="Запустить пример из PDF")
    args = parser.parse_args()

    verbose = not args.quiet
    if args.example:
        run_example_from_pdf(verbose=verbose)
    else:
        # Небольшой дружелюбный вывод о том, что нужно передать.
        print("Используйте флаг `--example` для проверки на примере из PDF.")


if __name__ == "__main__":
    main()

