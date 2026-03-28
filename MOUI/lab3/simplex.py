"""
Лабораторная работа 3. Основная фаза симплекс-метода.

Реализация основной фазы симплекс-метода для задачи ЛП в канонической форме:
  c^T x -> max
  Ax = b
  x >= 0

На второй и последующих итерациях обратная матрица к базисной вычисляется
методом из лабораторной работы №1 (обращение матрицы с изменённым столбцом).
"""

import sys
from pathlib import Path
import numpy as np

# Подключение модуля из lab1 для обновления обратной матрицы
MOUI_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(MOUI_ROOT))
from lab1.matrix import invert_matrix_with_replaced_column


def simplex_main_phase(c, A, x, B, verbose=True, return_basis=False):
    """
    Основная фаза симплекс-метода.

    Вход:
        c : np.ndarray (n,) — вектор коэффициентов целевой функции
        A : np.ndarray (m, n) — матрица ограничений Ax = b
        x : np.ndarray (n,) — начальный допустимый план
        B : list of int — упорядоченный список базисных индексов (индексы от 0 до n-1)

    Выход:
        По умолчанию: (status, x_opt), где:
            status == 'optimal' и x_opt — оптимальный план
            status == 'unbounded' — целевой функционал не ограничен сверху
        Если return_basis=True: (status, x_opt, B_opt)
    """
    c = np.asarray(c, dtype=float).flatten()
    A = np.asarray(A, dtype=float)
    x = np.asarray(x, dtype=float).flatten()
    B = list(B)

    m, n = A.shape
    assert len(c) == n and len(x) == n and len(B) == m

    # Текущий базис: матрица A_B из столбцов с индексами B
    A_B = A[:, B].copy()
    A_B_inv = np.linalg.inv(A_B)
    iteration = 0

    while True:
        iteration += 1
        if verbose:
            print(f"\n--- Итерация {iteration} ---")
            print(f"Базис B = {[b + 1 for b in B]} (индексы 1..n)")
            print(f"План x = {x}")
            print(f"Значение целевой функции c^T x = {c @ x:.4f}")
            print("Матрица A:")
            print(A)
            print("Базисная матрица A_B:")
            print(A_B)
            print("Обратная матрица A_B^{-1}:")
            print(A_B_inv)

        # ШАГ 2: вектор c_B
        c_B = c[B]

        # ШАГ 3: вектор потенциалов u^T = c_B^T A_B^{-1}
        u = (c_B @ A_B_inv).reshape(-1)

        # ШАГ 4: вектор оценок Δ^T = c^T - u^T A
        delta = c - u @ A

        if verbose:
            print(f"Вектор оценок Δ = {delta}")

        # ШАГ 5: проверка оптимальности (для задачи на max: все Δ <= 0)
        if np.all(delta <= 1e-10):  # с учётом численной погрешности
            if verbose:
                print("Δ ≤ 0 → текущий план оптимален.")
            if return_basis:
                return 'optimal', x.copy(), B.copy()
            return 'optimal', x.copy()

        # ШАГ 6: первая положительная компонента в Δ (индекс вводимой переменной j0)
        j0 = None
        for j in range(n):
            if delta[j] > 1e-10:
                j0 = j
                break
        if j0 is None:
            if return_basis:
                return 'optimal', x.copy(), B.copy()
            return 'optimal', x.copy()

        if verbose:
            print(f"Вводимая переменная: индекс j0 = {j0 + 1} (Δ_{j0 + 1} = {delta[j0]:.4f} > 0)")

        # ШАГ 7: z = A_B^{-1} A_{j0}
        A_j0 = A[:, j0].reshape(-1, 1)
        z = (A_B_inv @ A_j0).flatten()

        if verbose:
            print(f"Вектор z = A_B^{{-1}} A_{{j0}} = {z}")

        # ШАГ 8: θ_i = x_{j_i} / z_i при z_i > 0, иначе ∞
        theta = np.full(m, np.inf)
        for i in range(m):
            if z[i] > 1e-10:
                j_i = B[i]
                theta[i] = x[j_i] / z[i]

        # ШАГ 9: θ0 = min θ_i
        theta0 = np.min(theta)
        print(theta)
        # ШАГ 10: неограниченность
        if np.isinf(theta0) or theta0 >= 1e15:
            if verbose:
                print("θ0 = ∞ → целевой функционал не ограничен сверху на множестве допустимых планов.")
            if return_basis:
                return 'unbounded', None, B.copy()
            return 'unbounded', None

        # ШАГ 11: индекс k, на котором достигается минимум (при равенстве — минимальный)
        theta0 = np.min(theta)
        k = np.argmin(theta)  # первый минимум уже даёт минимальный индекс при равенстве
        j_star = B[k]  # выводимый базисный индекс

        if verbose:
            print(f"θ = {theta}, θ0 = {theta0}, k = {k + 1}, j* = {j_star + 1} (выводимая переменная)")

        # ШАГ 12: в B заменяем B[k] на j0
        B_new = B.copy()
        B_new[k] = j0

        # ШАГ 13: обновление плана x
        x_new = x.copy()
        x_new[j0] = theta0
        for i in range(m):
            if i != k:
                j_i = B[i]
                x_new[j_i] = x[j_i] - theta0 * z[i]
        x_new[j_star] = 0

        x = x_new
        B = B_new

        # Обновление A_B и A_B_inv для следующей итерации (метод из lab1)
        invertible, A_B_inv_new = invert_matrix_with_replaced_column(
            A_B, A_B_inv, A[:, j0], k + 1
        )
        if not invertible:
            A_B = A[:, B].copy()
            A_B_inv = np.linalg.inv(A_B)
            if verbose:
                print("(Базисная матрица пересобрана через np.linalg.inv)")
        else:
            A_B_inv = A_B_inv_new
            A_B = A[:, B].copy()


def run_example_1(verbose=True):
    """Пример из методички: задача с оптимальным планом (стр. 6–10, 14–17)."""
    print("=" * 60)
    print("Пример 1: x1 + x2 → max при ограничениях")
    print("-x1 + x2 + x3 = 1,  x1 + x4 = 3,  x2 + x5 = 2,  x >= 0")
    print("=" * 60)

    c = np.array([1, 1, 0, 0, 0])
    A = np.array([
        [-1, 1, 1, 0, 0],
        [1, 0, 0, 1, 0],
        [0, 1, 0, 0, 1]
    ])
    x0 = np.array([0, 0, 1, 3, 2])
    B0 = [2, 3, 4]  # индексы 3, 4, 5 в 1-based → 2, 3, 4 в 0-based

    status, x_opt = simplex_main_phase(c, A, x0, B0, verbose=verbose)

    if status == 'optimal':
        print(f"\n>>> Оптимальный план: x = {x_opt}")
        print(f">>> Значение целевой функции: {c @ x_opt}")
        print("Ожидается: x = [3, 2, 2, 0, 0], c^T x = 5")
    else:
        print(">>> Задача неограничена сверху")


def run_example_2(verbose=True):
    """Пример из методички: неограниченный сверху целевой функционал (стр. 11, 18–19)."""
    print("\n" + "=" * 60)
    print("Пример 2: x1 → max при ограничениях")
    print("x1 - x2 + x3 = 1,  -x1 + x2 + x4 = 2,  x >= 0")
    print("=" * 60)

    c = np.array([1, 0, 0, 0])
    A = np.array([
        [1, -1, 1, 0],
        [-1, 1, 0, 1]
    ])
    x0 = np.array([1, 0, 0, 3])
    B0 = [0, 3]  # j1=1, j2=4 в 1-based

    status, x_opt = simplex_main_phase(c, A, x0, B0, verbose=verbose)

    if status == 'unbounded':
        print("\n>>> Целевой функционал не ограничен сверху на множестве допустимых планов.")
    else:
        print(f"\n>>> Оптимальный план: x = {x_opt}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Основная фаза симплекс-метода")
    parser.add_argument("--quiet", action="store_true", help="Минимум вывода")
    args = parser.parse_args()
    verbose = not args.quiet

    run_example_1(verbose=verbose)
    run_example_2(verbose=verbose)


if __name__ == "__main__":
    main()
