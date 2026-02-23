import numpy as np


def invert_matrix_with_replaced_column(A, A_inv, x, i):
    """
    Обращение матрицы с измененным столбцом.

    Параметры:
    A - исходная обратимая матрица (n x n)
    A_inv - обратная матрица к A (n x n)
    x - вектор-столбец для замены (n x 1)
    i - индекс столбца для замены (нумерация с 1!)

    Возвращает:
    (invertible, A_bar_inv) - кортеж:
        invertible - булево значение (обратима ли новая матрица)
        A_bar_inv - обратная матрица (или None если необратима)
    """
    n = A.shape[0]
    i_idx = i - 1

    # Шаг 1
    l = A_inv @ x

    if l[i_idx] == 0:
        print(f"Матрица A̅ необратима (ℓ[{i}] = 0)")
        return False, None

    print(f"Матрица A̅ обратима (ℓ[{i}] = {l[i_idx]:.4f} ≠ 0)")

    # Шаг 2
    l_tilde = l.copy()
    l_tilde[i_idx] = -1

    # Шаг 3
    l_hat = (-1 / l[i_idx]) * l_tilde

    # Шаг 4
    Q = np.eye(n)
    Q[:, i_idx] = l_hat

    # Шаг 5
    A_bar_inv = efficient_multiply_Q_by_matrix(Q, A_inv, i_idx)

    return True, A_bar_inv


def efficient_multiply_Q_by_matrix(Q, M, i_idx):
    """
    Эффективное умножение матрицы Q на матрицу M.
    Матрица Q имеет специальную структуру: каждая строка содержит
    не более двух ненулевых элементов.

    Сложность: O(n²)
    """
    n = Q.shape[0]
    result = np.zeros((n, n))

    for j in range(n):
        for k in range(n):
            if j == i_idx:
                result[j, k] = Q[j, j] * M[j, k]
            else:
                result[j, k] = Q[j, j] * M[j, k] + Q[j, i_idx] * M[i_idx, k]

    return result


def main():
    # Пример из документа
    print("=" * 30)
    print("Пример из лабораторной работы")
    print("=" * 30)

    A = np.array([
        [1, -1, 0],
        [0, 1, 0],
        [0, 0, 1]
    ], dtype=float)

    A_inv = np.array([
        [1, 1, 0],
        [0, 1, 0],
        [0, 0, 1]
    ], dtype=float)

    x = np.array([1, 0, 1], dtype=float)

    i = 3

    print("\nИсходная матрица A:")
    print(A)
    print("\nОбратная матрица A^(-1):")
    print(A_inv)
    print("\nВектор x:")
    print(x)
    print(f"\nЗаменяем столбец {i} на вектор x")

    # Создаем матрицу A с чертой 
    A_bar = A.copy()
    A_bar[:, i-1] = x
    print("\nПолученная матрица A̅:")
    print(A_bar)

    # Применяем алгоритм
    print("\n" + "-" * 30)
    print("Применение алгоритма:")
    print("-" * 30)

    invertible, A_bar_inv = invert_matrix_with_replaced_column(A, A_inv, x, i)

    if invertible:
        print("\nОбратная матрица (A̅)^(-1):")
        print(A_bar_inv)

        # Проверка
        print("\nПроверка: A̅ * (A̅)^(-1) =")
        identity_check = A_bar @ A_bar_inv
        print(identity_check)
        print("\nОшибка (отклонение от единичной матрицы):")
        error = np.max(np.abs(identity_check - np.eye(A.shape[0])))
        print(f"{error:.2e}")

        print("\n" + "-" * 60)
        print("Проверка с помощью numpy.linalg.inv:")
        print("-" * 60)
        A_bar_inv_numpy = np.linalg.inv(A_bar)
        print("\nОбратная матрица по numpy:")
        print(A_bar_inv_numpy)
        print("\nРазница между методами:")
        diff = np.max(np.abs(A_bar_inv - A_bar_inv_numpy))
        print(f"{diff:.2e}")

    print("\n" + "=" * 60)
    print("Дополнительный тест: необратимая матрица")
    print("=" * 60)

    # Тест на необратимую матрицу
    # Подберем такой вектор x, что ℓ[i] = 0
    x2 = np.array([0, 0, 0], dtype=float)
    print("\nВектор x для получения необратимой матрицы:")
    print(x2)

    invertible2, _ = invert_matrix_with_replaced_column(A, A_inv, x2, i)

    

if __name__ == "__main__":
    main()