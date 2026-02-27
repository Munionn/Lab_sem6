# Презентация лабораторных работ по PL/SQL (Oracle 23c Free)

---

## Подготовка перед презентацией

```bash
cd BD/lab1-3
docker compose up -d          # запустить контейнер
./run.sh status               # убедиться что healthy
```

Дождись статуса `healthy` — занимает ~2 минуты при первом запуске.

---

## Лабораторная работа 1 — Процедуры и функции PL/SQL

### Что показывать

**Задание 1–2 — Создание таблицы и анонимный блок**

Запустить и показать вывод:
```bash
    ./run.sh lab1
```

Объяснить: анонимный PL/SQL-блок вставляет 10 000 строк с random-значениями через `DBMS_RANDOM.VALUE`.

---

**Задание 3 — Функция `check_even_odd`**

Подключиться интерактивно и запустить вручную:
```bash
./run.sh connect
```
```sql
SELECT check_even_odd() FROM DUAL;
```
Объяснить: функция считает чётные/нечётные значения в `val` и возвращает `'TRUE'` / `'FALSE'` / `'EQUAL'`.

---

**Задание 4 — Функция `generate_insert`**

```sql
SELECT generate_insert(1)  FROM DUAL;
SELECT generate_insert(999) FROM DUAL;
SELECT generate_insert(99999) FROM DUAL;   -- несуществующий ID
```
Показать: последний вызов вернёт `NULL` и выведет сообщение об ошибке через `DBMS_OUTPUT`.

---

**Задание 5 — DML-процедуры INSERT / UPDATE / DELETE**

```sql
SET SERVEROUTPUT ON
EXEC mytable_insert(20000, 777);
EXEC mytable_update(20000, 888);
EXEC mytable_delete(20000);
EXEC mytable_delete(20000);    -- повторное — покажет "не найдена"
```

---

**Задание 6 — Функция годового вознаграждения**

```sql
SET SERVEROUTPUT ON
-- нормальный случай
SELECT calc_annual_reward(5000, 20) FROM DUAL;   -- 72000

-- нулевая премия
SELECT calc_annual_reward(3000, 0) FROM DUAL;    -- 36000

-- ошибка: отрицательная зарплата
BEGIN
    DBMS_OUTPUT.PUT_LINE(calc_annual_reward(-100, 10));
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
/
```

---

## Лабораторная работа 2 — Триггеры

### Что показывать

**Запустить лабу:**
```bash
./run.sh lab2
```

Открыть интерактивную сессию:
```bash
./run.sh connect
```

---

**Задание 2 — Автоинкремент и уникальность**

```sql
SET SERVEROUTPUT ON
-- автоинкремент: ID назначается автоматически
INSERT INTO GROUPS (NAME) VALUES ('ПМ-23');
SELECT * FROM GROUPS;

-- проверка уникальности NAME
INSERT INTO GROUPS (NAME) VALUES ('ПМ-21');   
```

---

**Задание 3 — FK и каскадное удаление**

```sql
-- попытка вставить студента в несуществующую группу
INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Тест', 999);

-- каскадное удаление: удаляем группу — студенты удаляются автоматически
SELECT * FROM STUDENTS;
DELETE FROM GROUPS WHERE NAME = 'ПМ-22';
SELECT * FROM STUDENTS;    -- Сидоров Семён исчез
```

---

**Задание 4 — Журнал `STUDENTS_LOG`**

```sql
SELECT LOG_ID, OPERATION, STUDENT_ID,
       OLD_GROUP, NEW_GROUP, CHANGED_AT
FROM STUDENTS_LOG
ORDER BY LOG_ID;
```
Показать: все INSERT / UPDATE / DELETE отражены в журнале с временными метками.

---

**Задание 5 — Восстановление данных**

```sql
SET SERVEROUTPUT ON

-- запомнить текущее время
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') AS NOW FROM DUAL;

-- удалить всех студентов
DELETE FROM STUDENTS;
COMMIT;
SELECT COUNT(*) FROM STUDENTS;    -- 0

-- восстановить состояние 2 минуты назад
BEGIN
    restore_students(p_offset_minutes => 2);
END;
/
SELECT * FROM STUDENTS;    -- данные вернулись
```

---

**Задание 6 — Счётчик `C_VAL` в GROUPS**

```sql
-- текущее состояние
SELECT NAME, C_VAL FROM GROUPS;

-- перевести студента
UPDATE STUDENTS SET GROUP_ID = 2 WHERE NAME = 'Иванов Иван';
SELECT NAME, C_VAL FROM GROUPS;    -- C_VAL изменился в обеих группах

-- добавить студента
INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Новый студент', 1);
SELECT NAME, C_VAL FROM GROUPS;
```

---

## Лабораторная работа 3 — Работа со схемами

### Что показывать

**Запустить лабу (создаёт схемы DEV_SCHEMA и PROD_SCHEMA):**
```bash
./run.sh lab3
```

Подключиться:
```bash
./run.sh connect
```

---

**Задание 1 — Базовое сравнение `compare_schemas`**

Сначала сделать схемы разными — добавить таблицу только в DEV:
```bash
./run.sh connect-sys
```
```sql
-- создать таблицу только в DEV
CREATE TABLE dev_schema.orders (
    id     NUMBER PRIMARY KEY,
    amount NUMBER
);
EXIT
```

Вернуться в labuser и сравнить:
```bash
./run.sh connect
```
```sql
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC compare_schemas('DEV_SCHEMA', 'PROD_SCHEMA');
```
Показать: процедура выводит список отсутствующих/изменённых таблиц с учётом FK-зависимостей.

---

**Задание 2 — Расширенное сравнение `compare_schemas_extended`**

Добавить процедуру в DEV:
```bash
./run.sh connect-sys
```
```sql
CREATE OR REPLACE PROCEDURE dev_schema.hello IS
BEGIN DBMS_OUTPUT.PUT_LINE('Hello from DEV'); END;
/
EXIT
```

```bash
./run.sh connect
```
```sql
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC compare_schemas_extended('DEV_SCHEMA', 'PROD_SCHEMA');
```
Показать: разделы ТАБЛИЦЫ / ПРОЦЕДУРЫ И ФУНКЦИИ / ИНДЕКСЫ / ПАКЕТЫ.

---

**Задание 3 — Генерация DDL-скрипта синхронизации**

```sql
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC generate_sync_ddl('DEV_SCHEMA', 'PROD_SCHEMA');
```
Показать: готовый SQL-скрипт с `CREATE TABLE`, `CREATE OR REPLACE PROCEDURE` и `DROP` для лишних объектов.

---

## Быстрые команды для презентации

| Команда | Что делает |
|---|---|
| `./run.sh status` | статус контейнера |
| `./run.sh connect` | интерактивный sqlplus (labuser) |
| `./run.sh connect-sys` | интерактивный sqlplus (SYSTEM) |
| `./run.sh lab1` | выполнить lab1.sql |
| `./run.sh lab2` | выполнить lab2.sql |
| `./run.sh lab3` | создать схемы + выполнить lab3.sql |
| `./run.sh reset` | сбросить все данные labuser |
| `./run.sh logs` | логи контейнера |

---

## Если что-то пошло не так

**Полный сброс данных:**
```bash
./run.sh reset     # пересоздаёт пользователя labuser
./run.sh lab1
./run.sh lab2
./run.sh lab3
```

**Перезапуск контейнера:**
```bash
docker compose down
docker compose up -d
./run.sh status
```
