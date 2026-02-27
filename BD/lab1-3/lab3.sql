-- Лабораторная работа 3: Работа со схемами данных

-- Задание 1: Сравнение таблиц между схемами Dev и Prod
-- Учитываются FK-зависимости (топологическая сортировка)
CREATE OR REPLACE PROCEDURE compare_schemas(
    p_dev_schema  IN VARCHAR2,
    p_prod_schema IN VARCHAR2
) IS
    -- Тип для хранения имён таблиц
    TYPE t_name_list IS TABLE OF VARCHAR2(128) INDEX BY VARCHAR2(128);
    TYPE t_str_list  IS TABLE OF VARCHAR2(128);

    v_dev_tables  t_name_list;
    v_prod_tables t_name_list;
    v_diff_tables t_str_list := t_str_list();

    v_col_diff    NUMBER;
    v_dev_upper   VARCHAR2(128) := UPPER(p_dev_schema);
    v_prod_upper  VARCHAR2(128) := UPPER(p_prod_schema);

    -- Для топологической сортировки
    TYPE t_edge_list IS TABLE OF VARCHAR2(261); -- "parent~child"
    v_edges        t_edge_list := t_edge_list();
    v_sorted       t_str_list  := t_str_list();
    v_in_sorted    t_name_list;
    v_changed      BOOLEAN;
    v_can_add      BOOLEAN;
    v_has_cycle    BOOLEAN := FALSE;
    v_dep_table    VARCHAR2(128);
    v_dep_found    BOOLEAN;
BEGIN
    -- 1. Собрать список таблиц Dev
    FOR rec IN (
        SELECT TABLE_NAME FROM ALL_TABLES
        WHERE OWNER = v_dev_upper
        ORDER BY TABLE_NAME
    ) LOOP
        v_dev_tables(rec.TABLE_NAME) := rec.TABLE_NAME;
    END LOOP;

    -- 2. Собрать список таблиц Prod
    FOR rec IN (
        SELECT TABLE_NAME FROM ALL_TABLES
        WHERE OWNER = v_prod_upper
        ORDER BY TABLE_NAME
    ) LOOP
        v_prod_tables(rec.TABLE_NAME) := rec.TABLE_NAME;
    END LOOP;

    -- 3. Найти таблицы, которые есть в Dev, но отсутствуют или
    --    отличаются в Prod
    DECLARE
        v_tname VARCHAR2(128);
    BEGIN
        v_tname := v_dev_tables.FIRST;
        WHILE v_tname IS NOT NULL LOOP

            IF NOT v_prod_tables.EXISTS(v_tname) THEN
                v_diff_tables.EXTEND;
                v_diff_tables(v_diff_tables.LAST) := v_tname;
            ELSE
                SELECT COUNT(*) INTO v_col_diff
                FROM (
                    SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
                           DATA_PRECISION, DATA_SCALE, NULLABLE
                    FROM ALL_TAB_COLUMNS
                    WHERE OWNER = v_dev_upper AND TABLE_NAME = v_tname
                    MINUS
                    SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
                           DATA_PRECISION, DATA_SCALE, NULLABLE
                    FROM ALL_TAB_COLUMNS
                    WHERE OWNER = v_prod_upper AND TABLE_NAME = v_tname
                ) diff_cols;

                IF v_col_diff > 0 THEN
                    v_diff_tables.EXTEND;
                    v_diff_tables(v_diff_tables.LAST) := v_tname;
                END IF;
            END IF;

            v_tname := v_dev_tables.NEXT(v_tname);
        END LOOP;
    END;

    IF v_diff_tables.COUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Схемы идентичны по таблицам.');
        RETURN;
    END IF;

    -- 4. Собрать FK-зависимости между различающимися таблицами
    --    (только в рамках Dev-схемы)
    FOR i IN 1..v_diff_tables.COUNT LOOP
        FOR dep IN (
            SELECT DISTINCT uc2.TABLE_NAME AS PARENT_TABLE
            FROM ALL_CONSTRAINTS uc1
            JOIN ALL_CONSTRAINTS uc2
              ON uc1.R_CONSTRAINT_NAME = uc2.CONSTRAINT_NAME
               AND uc1.R_OWNER        = uc2.OWNER
            WHERE uc1.CONSTRAINT_TYPE = 'R'
              AND uc1.OWNER      = v_dev_upper
              AND uc1.TABLE_NAME = v_diff_tables(i)
              AND uc2.TABLE_NAME != v_diff_tables(i)
        ) LOOP
            -- Ребро: parent~child (child зависит от parent)
            v_edges.EXTEND;
            v_edges(v_edges.LAST) := dep.PARENT_TABLE || '~' || v_diff_tables(i);
        END LOOP;
    END LOOP;

    -- 5. Топологическая сортировка (Kahn's algorithm)
    -- Начинаем с таблиц без входящих зависимостей
    v_changed := TRUE;
    WHILE v_changed AND v_sorted.COUNT < v_diff_tables.COUNT LOOP
        v_changed := FALSE;
        FOR i IN 1..v_diff_tables.COUNT LOOP
            IF NOT v_in_sorted.EXISTS(v_diff_tables(i)) THEN
                v_can_add := TRUE;
                -- Проверяем: есть ли нераскрытые зависимости
                FOR j IN 1..v_edges.COUNT LOOP
                    DECLARE
                        v_parent VARCHAR2(128);
                        v_child  VARCHAR2(128);
                        v_delim  PLS_INTEGER;
                    BEGIN
                        v_delim := INSTR(v_edges(j), '~');
                        v_parent := SUBSTR(v_edges(j), 1, v_delim - 1);
                        v_child  := SUBSTR(v_edges(j), v_delim + 1);

                        IF v_child = v_diff_tables(i)
                           AND NOT v_in_sorted.EXISTS(v_parent)
                        THEN
                            -- Проверяем, входит ли parent в список различий
                            v_dep_found := FALSE;
                            FOR k IN 1..v_diff_tables.COUNT LOOP
                                IF v_diff_tables(k) = v_parent THEN
                                    v_dep_found := TRUE;
                                    EXIT;
                                END IF;
                            END LOOP;
                            IF v_dep_found THEN
                                v_can_add := FALSE;
                            END IF;
                        END IF;
                    END;
                END LOOP;

                IF v_can_add THEN
                    v_sorted.EXTEND;
                    v_sorted(v_sorted.LAST)          := v_diff_tables(i);
                    v_in_sorted(v_diff_tables(i))    := v_diff_tables(i);
                    v_changed := TRUE;
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    IF v_sorted.COUNT < v_diff_tables.COUNT THEN
        v_has_cycle := TRUE;
    END IF;

    -- 6. Вывод результата
    DBMS_OUTPUT.PUT_LINE('=== Таблицы Dev->Prod (отсутствуют или отличаются) ===');
    DBMS_OUTPUT.PUT_LINE('Порядок создания (с учётом FK):');
    DBMS_OUTPUT.PUT_LINE('');

    FOR i IN 1..v_sorted.COUNT LOOP
        IF v_prod_tables.EXISTS(v_sorted(i)) THEN
            DBMS_OUTPUT.PUT_LINE(LPAD(i,3) || '. [ИЗМЕНЕНА]   ' || v_sorted(i));
        ELSE
            DBMS_OUTPUT.PUT_LINE(LPAD(i,3) || '. [ОТСУТСТВУЕТ] ' || v_sorted(i));
        END IF;
    END LOOP;

    -- Таблицы с циклическими зависимостями
    IF v_has_cycle THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Обнаружены закольцованные FK-зависимости для таблиц:');
        FOR i IN 1..v_diff_tables.COUNT LOOP
            IF NOT v_in_sorted.EXISTS(v_diff_tables(i)) THEN
                DBMS_OUTPUT.PUT_LINE('  - ' || v_diff_tables(i));
            END IF;
        END LOOP;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка compare_schemas: ' || SQLERRM);
        RAISE;
END compare_schemas;
/

-- Задание 2: Расширенное сравнение — таблицы, процедуры,
-- функции, индексы, пакеты
CREATE OR REPLACE PROCEDURE compare_schemas_extended(
    p_dev_schema  IN VARCHAR2,
    p_prod_schema IN VARCHAR2
) IS
    v_dev_upper  VARCHAR2(128) := UPPER(p_dev_schema);
    v_prod_upper VARCHAR2(128) := UPPER(p_prod_schema);
    v_diff_count NUMBER := 0;

    PROCEDURE print_section(p_title IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 60, '='));
        DBMS_OUTPUT.PUT_LINE(p_title);
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 60, '='));
    END;

BEGIN
    --  Таблицы (структура + наличие)
    print_section('ТАБЛИЦЫ');

    FOR rec IN (
        SELECT d.TABLE_NAME,
               CASE WHEN p.TABLE_NAME IS NULL THEN 'ОТСУТСТВУЕТ в Prod'
                    ELSE 'ИЗМЕНЕНА структура'
               END AS STATUS
        FROM (SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = v_dev_upper) d
        LEFT JOIN (SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = v_prod_upper) p
          ON d.TABLE_NAME = p.TABLE_NAME
        WHERE p.TABLE_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
                   FROM ALL_TAB_COLUMNS WHERE OWNER = v_dev_upper AND TABLE_NAME = d.TABLE_NAME
                   MINUS
                   SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
                   FROM ALL_TAB_COLUMNS WHERE OWNER = v_prod_upper AND TABLE_NAME = d.TABLE_NAME
               ) diff
           )
        ORDER BY d.TABLE_NAME
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  [' || RPAD(rec.STATUS, 22) || '] ' || rec.TABLE_NAME);
        v_diff_count := v_diff_count + 1;
    END LOOP;

    IF SQL%ROWCOUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  Различий не найдено.');
    END IF;

    --  Процедуры и функции (по тексту исходного кода)
    print_section('ПРОЦЕДУРЫ И ФУНКЦИИ');

    FOR rec IN (
        SELECT d.OBJECT_NAME, d.OBJECT_TYPE,
               CASE WHEN p.OBJECT_NAME IS NULL THEN 'ОТСУТСТВУЕТ в Prod'
                    ELSE 'ИЗМЕНЁН исходный код'
               END AS STATUS
        FROM (
            SELECT OBJECT_NAME, OBJECT_TYPE
            FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper
              AND OBJECT_TYPE IN ('PROCEDURE', 'FUNCTION')
        ) d
        LEFT JOIN (
            SELECT OBJECT_NAME, OBJECT_TYPE
            FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper
              AND OBJECT_TYPE IN ('PROCEDURE', 'FUNCTION')
        ) p ON d.OBJECT_NAME = p.OBJECT_NAME AND d.OBJECT_TYPE = p.OBJECT_TYPE
        WHERE p.OBJECT_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_dev_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
                   MINUS
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_prod_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
               ) src_diff
           )
        ORDER BY d.OBJECT_TYPE, d.OBJECT_NAME
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  [' || RPAD(rec.STATUS, 22) || '] '
            || rec.OBJECT_TYPE || ': ' || rec.OBJECT_NAME);
        v_diff_count := v_diff_count + 1;
    END LOOP;

    --  Индексы
    print_section('ИНДЕКСЫ');

    FOR rec IN (
        SELECT d.INDEX_NAME, d.TABLE_NAME,
               CASE WHEN p.INDEX_NAME IS NULL THEN 'ОТСУТСТВУЕТ в Prod'
                    ELSE 'ИЗМЕНЁН'
               END AS STATUS
        FROM (
            SELECT INDEX_NAME, TABLE_NAME, INDEX_TYPE, UNIQUENESS
            FROM ALL_INDEXES WHERE OWNER = v_dev_upper
        ) d
        LEFT JOIN (
            SELECT INDEX_NAME, TABLE_NAME, INDEX_TYPE, UNIQUENESS
            FROM ALL_INDEXES WHERE OWNER = v_prod_upper
        ) p ON d.INDEX_NAME = p.INDEX_NAME
        WHERE p.INDEX_NAME IS NULL
           OR d.INDEX_TYPE != p.INDEX_TYPE
           OR d.UNIQUENESS  != p.UNIQUENESS
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT COLUMN_NAME, COLUMN_POSITION, DESCEND
                   FROM ALL_IND_COLUMNS
                   WHERE INDEX_OWNER = v_dev_upper AND INDEX_NAME = d.INDEX_NAME
                   MINUS
                   SELECT COLUMN_NAME, COLUMN_POSITION, DESCEND
                   FROM ALL_IND_COLUMNS
                   WHERE INDEX_OWNER = v_prod_upper AND INDEX_NAME = d.INDEX_NAME
               ) idx_diff
           )
        ORDER BY d.TABLE_NAME, d.INDEX_NAME
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  [' || RPAD(rec.STATUS, 22) || '] '
            || rec.INDEX_NAME || ' (on ' || rec.TABLE_NAME || ')');
        v_diff_count := v_diff_count + 1;
    END LOOP;

    -- --------------------------------------------------------
    -- 2.4 Пакеты
    -- --------------------------------------------------------
    print_section('ПАКЕТЫ');

    FOR rec IN (
        SELECT d.OBJECT_NAME,
               CASE WHEN p.OBJECT_NAME IS NULL THEN 'ОТСУТСТВУЕТ в Prod'
                    ELSE 'ИЗМЕНЁН'
               END AS STATUS
        FROM (
            SELECT DISTINCT OBJECT_NAME FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper AND OBJECT_TYPE IN ('PACKAGE', 'PACKAGE BODY')
        ) d
        LEFT JOIN (
            SELECT DISTINCT OBJECT_NAME FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper AND OBJECT_TYPE IN ('PACKAGE', 'PACKAGE BODY')
        ) p ON d.OBJECT_NAME = p.OBJECT_NAME
        WHERE p.OBJECT_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_dev_upper AND NAME = d.OBJECT_NAME
                     AND TYPE IN ('PACKAGE', 'PACKAGE BODY')
                   MINUS
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_prod_upper AND NAME = d.OBJECT_NAME
                     AND TYPE IN ('PACKAGE', 'PACKAGE BODY')
               ) pkg_diff
           )
        ORDER BY d.OBJECT_NAME
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  [' || RPAD(rec.STATUS, 22) || '] PACKAGE: ' || rec.OBJECT_NAME);
        v_diff_count := v_diff_count + 1;
    END LOOP;

    -- Итог
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Итого различий: ' || v_diff_count);

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка compare_schemas_extended: ' || SQLERRM);
        RAISE;
END compare_schemas_extended;
/

-- Задание 3: Генерация DDL-скрипта для синхронизации Prod с Dev
-- Включает: ALTER/CREATE для изменённых объектов,
--           DROP для объектов отсутствующих в Dev
CREATE OR REPLACE PROCEDURE generate_sync_ddl(
    p_dev_schema  IN VARCHAR2,
    p_prod_schema IN VARCHAR2
) IS
    v_dev_upper  VARCHAR2(128) := UPPER(p_dev_schema);
    v_prod_upper VARCHAR2(128) := UPPER(p_prod_schema);
    v_ddl        CLOB;
    v_line       VARCHAR2(32767);

    PROCEDURE out(p_text IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_text);
    END;

    -- Получить DDL объекта через DBMS_METADATA
    FUNCTION get_ddl_safe(p_type IN VARCHAR2, p_name IN VARCHAR2, p_schema IN VARCHAR2)
    RETURN CLOB IS
        v_result CLOB;
    BEGIN
        DBMS_METADATA.SET_TRANSFORM_PARAM(
            DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(
            DBMS_METADATA.SESSION_TRANSFORM, 'TABLESPACE', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(
            DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(
            DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);

        v_result := DBMS_METADATA.GET_DDL(p_type, p_name, p_schema);
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN '-- Не удалось получить DDL для ' || p_type || ' ' || p_name
                   || ': ' || SQLERRM || CHR(10);
    END get_ddl_safe;

BEGIN
    out('-- ================================================');
    out('-- DDL-скрипт синхронизации: ' || v_dev_upper || ' -> ' || v_prod_upper);
    out('-- Сгенерировано: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    out('-- ================================================');
    out('');

    --  Таблицы: CREATE для новых, ALTER для изменённых
    out('-- ---- ТАБЛИЦЫ ----');
    out('');

    FOR rec IN (
        SELECT d.TABLE_NAME,
               CASE WHEN p.TABLE_NAME IS NULL THEN 'CREATE' ELSE 'ALTER' END AS ACTION
        FROM (SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = v_dev_upper) d
        LEFT JOIN (SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = v_prod_upper) p
          ON d.TABLE_NAME = p.TABLE_NAME
        WHERE p.TABLE_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
                   FROM ALL_TAB_COLUMNS WHERE OWNER = v_dev_upper AND TABLE_NAME = d.TABLE_NAME
                   MINUS
                   SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
                   FROM ALL_TAB_COLUMNS WHERE OWNER = v_prod_upper AND TABLE_NAME = d.TABLE_NAME
               ) diff
           )
        ORDER BY d.TABLE_NAME
    ) LOOP
        IF rec.ACTION = 'CREATE' THEN
            out('-- CREATE TABLE ' || rec.TABLE_NAME);
            v_ddl := get_ddl_safe('TABLE', rec.TABLE_NAME, v_dev_upper);
            -- Заменяем схему Dev на Prod в DDL
            v_ddl := REPLACE(v_ddl, '"' || v_dev_upper || '"', '"' || v_prod_upper || '"');
            DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, 32000, 1));
        ELSE
            out('-- ALTER TABLE ' || rec.TABLE_NAME || ' (добавление новых столбцов)');
            -- Генерируем ALTER ADD для новых столбцов
            FOR col IN (
                SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
                       DATA_PRECISION, DATA_SCALE, NULLABLE, DATA_DEFAULT
                FROM ALL_TAB_COLUMNS
                WHERE OWNER = v_dev_upper AND TABLE_NAME = rec.TABLE_NAME
                  AND COLUMN_NAME NOT IN (
                      SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS
                      WHERE OWNER = v_prod_upper AND TABLE_NAME = rec.TABLE_NAME
                  )
                ORDER BY COLUMN_ID
            ) LOOP
                DECLARE
                    v_col_def VARCHAR2(500);
                BEGIN
                    v_col_def := 'ALTER TABLE ' || v_prod_upper || '.' || rec.TABLE_NAME
                        || ' ADD (' || col.COLUMN_NAME || ' ' || col.DATA_TYPE;
                    IF col.DATA_TYPE IN ('VARCHAR2','CHAR','NVARCHAR2','NCHAR') THEN
                        v_col_def := v_col_def || '(' || col.DATA_LENGTH || ')';
                    ELSIF col.DATA_TYPE = 'NUMBER' AND col.DATA_PRECISION IS NOT NULL THEN
                        v_col_def := v_col_def || '(' || col.DATA_PRECISION;
                        IF col.DATA_SCALE IS NOT NULL THEN
                            v_col_def := v_col_def || ',' || col.DATA_SCALE;
                        END IF;
                        v_col_def := v_col_def || ')';
                    END IF;
                    IF col.DATA_DEFAULT IS NOT NULL THEN
                        v_col_def := v_col_def || ' DEFAULT ' || TRIM(col.DATA_DEFAULT);
                    END IF;
                    IF col.NULLABLE = 'N' THEN
                        v_col_def := v_col_def || ' NOT NULL';
                    END IF;
                    v_col_def := v_col_def || ');';
                    out(v_col_def);
                END;
            END LOOP;
        END IF;
        out('');
    END LOOP;

    --  Процедуры/Функции: CREATE OR REPLACE для изменённых
    out('-- ---- ПРОЦЕДУРЫ И ФУНКЦИИ ----');
    out('');

    FOR rec IN (
        SELECT d.OBJECT_NAME, d.OBJECT_TYPE
        FROM (
            SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper AND OBJECT_TYPE IN ('PROCEDURE','FUNCTION')
        ) d
        LEFT JOIN (
            SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper AND OBJECT_TYPE IN ('PROCEDURE','FUNCTION')
        ) p ON d.OBJECT_NAME = p.OBJECT_NAME AND d.OBJECT_TYPE = p.OBJECT_TYPE
        WHERE p.OBJECT_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_dev_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
                   MINUS
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_prod_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
               ) src_diff
           )
        ORDER BY d.OBJECT_TYPE, d.OBJECT_NAME
    ) LOOP
        out('-- CREATE OR REPLACE ' || rec.OBJECT_TYPE || ' ' || rec.OBJECT_NAME);
        v_ddl := get_ddl_safe(rec.OBJECT_TYPE, rec.OBJECT_NAME, v_dev_upper);
        v_ddl := REPLACE(v_ddl, '"' || v_dev_upper || '"', '"' || v_prod_upper || '"');
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, 32000, 1));
        out('/');
        out('');
    END LOOP;

    --  Пакеты: CREATE OR REPLACE
    out('-- ---- ПАКЕТЫ ----');
    out('');

    FOR rec IN (
        SELECT d.OBJECT_NAME, d.OBJECT_TYPE
        FROM (
            SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper AND OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
        ) d
        LEFT JOIN (
            SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper AND OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
        ) p ON d.OBJECT_NAME = p.OBJECT_NAME AND d.OBJECT_TYPE = p.OBJECT_TYPE
        WHERE p.OBJECT_NAME IS NULL
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_dev_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
                   MINUS
                   SELECT LINE, TEXT FROM ALL_SOURCE
                   WHERE OWNER = v_prod_upper AND NAME = d.OBJECT_NAME AND TYPE = d.OBJECT_TYPE
               ) pkg_diff
           )
        ORDER BY d.OBJECT_TYPE, d.OBJECT_NAME
    ) LOOP
        out('-- CREATE OR REPLACE ' || rec.OBJECT_TYPE || ' ' || rec.OBJECT_NAME);
        v_ddl := get_ddl_safe(rec.OBJECT_TYPE, rec.OBJECT_NAME, v_dev_upper);
        v_ddl := REPLACE(v_ddl, '"' || v_dev_upper || '"', '"' || v_prod_upper || '"');
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, 32000, 1));
        out('/');
        out('');
    END LOOP;

    --  Индексы: CREATE для новых / отличающихся
    out('-- ---- ИНДЕКСЫ ----');
    out('');

    FOR rec IN (
        SELECT d.INDEX_NAME, d.TABLE_NAME,
               CASE WHEN p.INDEX_NAME IS NULL THEN 'CREATE' ELSE 'RECREATE' END AS ACTION
        FROM (
            SELECT INDEX_NAME, TABLE_NAME, INDEX_TYPE, UNIQUENESS
            FROM ALL_INDEXES WHERE OWNER = v_dev_upper
        ) d
        LEFT JOIN (
            SELECT INDEX_NAME, INDEX_TYPE, UNIQUENESS
            FROM ALL_INDEXES WHERE OWNER = v_prod_upper
        ) p ON d.INDEX_NAME = p.INDEX_NAME
        WHERE p.INDEX_NAME IS NULL
           OR d.INDEX_TYPE != p.INDEX_TYPE
           OR d.UNIQUENESS  != p.UNIQUENESS
           OR EXISTS (
               SELECT 1 FROM (
                   SELECT COLUMN_NAME, COLUMN_POSITION, DESCEND
                   FROM ALL_IND_COLUMNS
                   WHERE INDEX_OWNER = v_dev_upper AND INDEX_NAME = d.INDEX_NAME
                   MINUS
                   SELECT COLUMN_NAME, COLUMN_POSITION, DESCEND
                   FROM ALL_IND_COLUMNS
                   WHERE INDEX_OWNER = v_prod_upper AND INDEX_NAME = d.INDEX_NAME
               ) idx_diff
           )
        ORDER BY d.TABLE_NAME, d.INDEX_NAME
    ) LOOP
        IF rec.ACTION = 'RECREATE' THEN
            out('DROP INDEX ' || v_prod_upper || '.' || rec.INDEX_NAME || ';');
        END IF;
        v_ddl := get_ddl_safe('INDEX', rec.INDEX_NAME, v_dev_upper);
        v_ddl := REPLACE(v_ddl, '"' || v_dev_upper || '"', '"' || v_prod_upper || '"');
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, 32000, 1));
        out('');
    END LOOP;

    -- --------------------------------------------------------
    -- 3.5 DROP объектов, которые есть в Prod, но нет в Dev
    -- --------------------------------------------------------
    out('-- ---- УДАЛЕНИЕ ОБЪЕКТОВ (есть в Prod, нет в Dev) ----');
    out('');

    -- Таблицы
    FOR rec IN (
        SELECT p.TABLE_NAME
        FROM (SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = v_prod_upper) p
        WHERE NOT EXISTS (
            SELECT 1 FROM ALL_TABLES WHERE OWNER = v_dev_upper AND TABLE_NAME = p.TABLE_NAME
        )
        ORDER BY p.TABLE_NAME
    ) LOOP
        out('DROP TABLE ' || v_prod_upper || '.' || rec.TABLE_NAME || ' CASCADE CONSTRAINTS;');
    END LOOP;

    -- Процедуры, функции
    FOR rec IN (
        SELECT p.OBJECT_NAME, p.OBJECT_TYPE
        FROM (
            SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper AND OBJECT_TYPE IN ('PROCEDURE','FUNCTION')
        ) p
        WHERE NOT EXISTS (
            SELECT 1 FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper
              AND OBJECT_NAME = p.OBJECT_NAME
              AND OBJECT_TYPE = p.OBJECT_TYPE
        )
        ORDER BY p.OBJECT_TYPE, p.OBJECT_NAME
    ) LOOP
        out('DROP ' || rec.OBJECT_TYPE || ' ' || v_prod_upper || '.' || rec.OBJECT_NAME || ';');
    END LOOP;

    -- Пакеты
    FOR rec IN (
        SELECT DISTINCT p.OBJECT_NAME
        FROM (
            SELECT OBJECT_NAME FROM ALL_OBJECTS
            WHERE OWNER = v_prod_upper AND OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
        ) p
        WHERE NOT EXISTS (
            SELECT 1 FROM ALL_OBJECTS
            WHERE OWNER = v_dev_upper
              AND OBJECT_NAME = p.OBJECT_NAME
              AND OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
        )
        ORDER BY p.OBJECT_NAME
    ) LOOP
        out('DROP PACKAGE ' || v_prod_upper || '.' || rec.OBJECT_NAME || ';');
    END LOOP;

    -- Индексы
    FOR rec IN (
        SELECT p.INDEX_NAME
        FROM (SELECT INDEX_NAME FROM ALL_INDEXES WHERE OWNER = v_prod_upper) p
        WHERE NOT EXISTS (
            SELECT 1 FROM ALL_INDEXES WHERE OWNER = v_dev_upper AND INDEX_NAME = p.INDEX_NAME
        )
        ORDER BY p.INDEX_NAME
    ) LOOP
        out('DROP INDEX ' || v_prod_upper || '.' || rec.INDEX_NAME || ';');
    END LOOP;

    out('');
    out('-- Конец DDL-скрипта синхронизации');

EXCEPTION
    WHEN OTHERS THEN
        out('Ошибка generate_sync_ddl: ' || SQLERRM);
        RAISE;
END generate_sync_ddl;
/

-- ============================================================
-- Задание 1: Базовое сравнение таблиц (с FK-сортировкой)
-- ============================================================
BEGIN
    compare_schemas('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/

-- ============================================================
-- Задание 2: Расширенное сравнение (таблицы + процедуры + индексы + пакеты)
-- ============================================================
BEGIN
    compare_schemas_extended('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/

-- ============================================================
-- Задание 3: Генерация DDL-скрипта синхронизации
-- ============================================================
BEGIN
    generate_sync_ddl('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/
