-- ============================================================
-- Лабораторная работа 1: Простые процедуры и функции PL/SQL
-- ============================================================

-- ============================================================
-- Задание 1: Создание таблицы MyTable
-- ============================================================
CREATE TABLE MyTable (
    id  NUMBER,
    val NUMBER
);

-- ============================================================
-- Задание 2: Анонимный блок — запись 10 000 случайных записей
-- ============================================================
BEGIN
    FOR i IN 1..10000 LOOP
        INSERT INTO MyTable (id, val)
        VALUES (i, TRUNC(DBMS_RANDOM.VALUE(1, 1000)));
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Вставлено 10 000 записей в MyTable');
END;
/

-- ============================================================
-- Задание 3: Функция сравнения количества чётных и нечётных val
-- Возвращает VARCHAR2: 'TRUE', 'FALSE' или 'EQUAL'
-- ============================================================
CREATE OR REPLACE FUNCTION check_even_odd
RETURN VARCHAR2 IS
    v_even_count NUMBER := 0;
    v_odd_count  NUMBER := 0;
BEGIN
    SELECT COUNT(*) INTO v_even_count
    FROM MyTable
    WHERE MOD(val, 2) = 0;

    SELECT COUNT(*) INTO v_odd_count
    FROM MyTable
    WHERE MOD(val, 2) != 0;

    IF v_even_count > v_odd_count THEN
        RETURN 'TRUE';
    ELSIF v_odd_count > v_even_count THEN
        RETURN 'FALSE';
    ELSE
        RETURN 'EQUAL';
    END IF;
END check_even_odd;
/

-- Тест функции:
BEGIN
    DBMS_OUTPUT.PUT_LINE('Результат check_even_odd: ' || check_even_odd());
END;
/

-- ============================================================
-- Задание 4: Функция генерации текста INSERT-команды по ID
-- ============================================================
CREATE OR REPLACE FUNCTION generate_insert(p_id IN NUMBER)
RETURN VARCHAR2 IS
    v_val  MyTable.val%TYPE;
    v_sql  VARCHAR2(500);
BEGIN
    SELECT val INTO v_val
    FROM MyTable
    WHERE id = p_id;

    v_sql := 'INSERT INTO MyTable (id, val) VALUES (' ||
             TO_CHAR(p_id) || ', ' ||
             TO_CHAR(v_val) || ');';

    DBMS_OUTPUT.PUT_LINE(v_sql);
    RETURN v_sql;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Запись с ID=' || p_id || ' не найдена.');
        RETURN NULL;
END generate_insert;
/

-- Тест функции:
DECLARE
    v_result VARCHAR2(500);
BEGIN
    v_result := generate_insert(1);
END;
/

-- ============================================================
-- Задание 5: Процедуры DML (INSERT, UPDATE, DELETE)
-- ============================================================

-- INSERT
CREATE OR REPLACE PROCEDURE mytable_insert(
    p_id  IN MyTable.id%TYPE,
    p_val IN MyTable.val%TYPE
) IS
BEGIN
    INSERT INTO MyTable (id, val) VALUES (p_id, p_val);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Вставлена запись: id=' || p_id || ', val=' || p_val);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: запись с id=' || p_id || ' уже существует.');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка при INSERT: ' || SQLERRM);
        RAISE;
END mytable_insert;
/

-- UPDATE
CREATE OR REPLACE PROCEDURE mytable_update(
    p_id      IN MyTable.id%TYPE,
    p_new_val IN MyTable.val%TYPE
) IS
BEGIN
    UPDATE MyTable
    SET val = p_new_val
    WHERE id = p_id;

    IF SQL%ROWCOUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Запись с id=' || p_id || ' не найдена.');
    ELSE
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Обновлена запись: id=' || p_id || ', новый val=' || p_new_val);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка при UPDATE: ' || SQLERRM);
        RAISE;
END mytable_update;
/

-- DELETE
CREATE OR REPLACE PROCEDURE mytable_delete(
    p_id IN MyTable.id%TYPE
) IS
BEGIN
    DELETE FROM MyTable WHERE id = p_id;

    IF SQL%ROWCOUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Запись с id=' || p_id || ' не найдена.');
    ELSE
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Удалена запись с id=' || p_id);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка при DELETE: ' || SQLERRM);
        RAISE;
END mytable_delete;
/

-- Тесты DML процедур:
BEGIN
    mytable_insert(10001, 42);
    mytable_update(10001, 99);
    mytable_delete(10001);
END;
/

-- ============================================================
-- Задание 6: Функция расчёта годового вознаграждения
-- Аргументы: месячная зарплата (NUMBER), процент премии (INTEGER)
-- Формула: (1 + процент/100) * 12 * зарплата
-- ============================================================
CREATE OR REPLACE FUNCTION calc_annual_reward(
    p_monthly_salary IN NUMBER,
    p_bonus_percent  IN INTEGER
) RETURN NUMBER IS
    v_bonus_rate NUMBER;
    v_result     NUMBER;
BEGIN
    -- Проверка корректности входных данных
    IF p_monthly_salary IS NULL OR p_bonus_percent IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Параметры не могут быть NULL.');
    END IF;

    IF p_monthly_salary < 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Месячная зарплата не может быть отрицательной.');
    END IF;

    IF p_bonus_percent < 0 OR p_bonus_percent > 10000 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Процент премиальных должен быть в диапазоне 0–10000.');
    END IF;

    -- Преобразование целого процента к дробному коэффициенту
    v_bonus_rate := p_bonus_percent / 100.0;

    -- Расчёт годового вознаграждения
    v_result := (1 + v_bonus_rate) * 12 * p_monthly_salary;

    RETURN v_result;

EXCEPTION
    WHEN VALUE_ERROR THEN
        RAISE_APPLICATION_ERROR(-20004, 'Некорректный тип данных для параметров.');
    WHEN OTHERS THEN
        RAISE;
END calc_annual_reward;
/

-- Тесты функции:
BEGIN
    -- Нормальный случай: зарплата 5000, премия 20%
    DBMS_OUTPUT.PUT_LINE('Годовое вознаграждение (5000, 20%): ' ||
        TO_CHAR(calc_annual_reward(5000, 20)));

    -- Нулевая премия
    DBMS_OUTPUT.PUT_LINE('Годовое вознаграждение (3000, 0%): ' ||
        TO_CHAR(calc_annual_reward(3000, 0)));
END;
/

-- Тест с некорректными данными:
BEGIN
    DBMS_OUTPUT.PUT_LINE(TO_CHAR(calc_annual_reward(-100, 10)));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ожидаемая ошибка: ' || SQLERRM);
END;
/
