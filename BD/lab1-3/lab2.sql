
BEGIN
    FOR t IN (SELECT trigger_name FROM user_triggers
              WHERE trigger_name IN (
                  'TRG_GROUPS_CVAL_AFTER_STMT','TRG_UPDATE_GROUP_CVAL_STMT','TRG_UPDATE_GROUP_CVAL','TRG_STUDENTS_AUDIT',
                  'TRG_STUDENTS_FK_CHECK','TRG_STUDENTS_UNIQUE_ID',
                  'TRG_STUDENTS_AUTOINC','TRG_GROUPS_CASCADE_DELETE',
                  'TRG_GROUPS_UNIQUE_NAME','TRG_GROUPS_UNIQUE_ID',
                  'TRG_GROUPS_AUTOINC')) LOOP
        EXECUTE IMMEDIATE 'DROP TRIGGER ' || t.trigger_name;
    END LOOP;
    FOR tb IN (SELECT table_name FROM user_tables
               WHERE table_name IN ('STUDENTS_LOG','STUDENTS','GROUPS')) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || tb.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;
    FOR sq IN (SELECT sequence_name FROM user_sequences
               WHERE sequence_name IN ('SEQ_GROUPS_ID','SEQ_STUDENTS_ID')) LOOP
        EXECUTE IMMEDIATE 'DROP SEQUENCE ' || sq.sequence_name;
    END LOOP;
END;
/

-- Задание 1: Создание таблиц STUDENTS и GROUPS
CREATE TABLE GROUPS (
    ID     NUMBER       NOT NULL,
    NAME   VARCHAR2(50) NOT NULL,
    C_VAL  NUMBER       DEFAULT 0 NOT NULL,
    CONSTRAINT PK_GROUPS PRIMARY KEY (ID)
);

CREATE TABLE STUDENTS (
    ID       NUMBER        NOT NULL,
    NAME     VARCHAR2(100) NOT NULL,
    GROUP_ID NUMBER        NOT NULL,
    CONSTRAINT PK_STUDENTS PRIMARY KEY (ID)
);

-- Последовательности для автоинкремента
CREATE SEQUENCE SEQ_GROUPS_ID  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_STUDENTS_ID START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- Задание 2: Триггеры — уникальность ID, автоинкремент,
--            уникальность GROUPS.NAME

CREATE OR REPLACE TRIGGER trg_groups_autoinc
BEFORE INSERT ON GROUPS
FOR EACH ROW
BEGIN
    IF :NEW.ID IS NULL THEN
        :NEW.ID := SEQ_GROUPS_ID.NEXTVAL;
    END IF;
END trg_groups_autoinc;
/

-- Проверка уникальности ID для GROUPS (только при INSERT; PRIMARY KEY защищает UPDATE)
CREATE OR REPLACE TRIGGER trg_groups_unique_id
BEFORE INSERT ON GROUPS
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM GROUPS WHERE ID = :NEW.ID;
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'ID=' || :NEW.ID || ' уже существует в GROUPS.');
    END IF;
END trg_groups_unique_id;
/

-- Уникальность GROUPS.NAME
CREATE OR REPLACE TRIGGER trg_groups_unique_name
BEFORE INSERT OR UPDATE OF NAME ON GROUPS
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    IF INSERTING THEN
        SELECT COUNT(*) INTO v_count FROM GROUPS WHERE NAME = :NEW.NAME;
    ELSE
        SELECT COUNT(*) INTO v_count FROM GROUPS WHERE NAME = :NEW.NAME AND ID != :OLD.ID;
    END IF;

    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20011, 'Группа с именем "' || :NEW.NAME || '" уже существует.');
    END IF;
END trg_groups_unique_name;
/

-- Автоинкремент ID для STUDENTS
CREATE OR REPLACE TRIGGER trg_students_autoinc
BEFORE INSERT ON STUDENTS
FOR EACH ROW
BEGIN
    IF :NEW.ID IS NULL THEN
        :NEW.ID := SEQ_STUDENTS_ID.NEXTVAL;
    END IF;
END trg_students_autoinc;
/

-- Проверка уникальности ID для STUDENTS (только при INSERT; PRIMARY KEY защищает UPDATE)
CREATE OR REPLACE TRIGGER trg_students_unique_id
BEFORE INSERT ON STUDENTS
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM STUDENTS WHERE ID = :NEW.ID;
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20012, 'ID=' || :NEW.ID || ' уже существует в STUDENTS.');
    END IF;
END trg_students_unique_id;
/

-- Задание 3: Триггер Foreign Key с каскадным удалением
-- STUDENTS -> GROUPS (при удалении группы удаляются студенты)

CREATE OR REPLACE TRIGGER trg_students_fk_check
BEFORE INSERT OR UPDATE OF GROUP_ID ON STUDENTS
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM GROUPS WHERE ID = :NEW.GROUP_ID;
    IF v_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20020,
            'Группа с ID=' || :NEW.GROUP_ID || ' не существует.');
    END IF;
END trg_students_fk_check;
/

-- Каскадное удаление студентов при удалении группы
CREATE OR REPLACE TRIGGER trg_groups_cascade_delete
BEFORE DELETE ON GROUPS
FOR EACH ROW
BEGIN
    DELETE FROM STUDENTS WHERE GROUP_ID = :OLD.ID;
    DBMS_OUTPUT.PUT_LINE('Каскадно удалены студенты группы ID=' || :OLD.ID);
END trg_groups_cascade_delete;
/

-- Задание 4: Триггер журналирования действий над STUDENTS

-- Таблица журнала
CREATE TABLE STUDENTS_LOG (
    LOG_ID      NUMBER GENERATED ALWAYS AS IDENTITY,
    OPERATION   VARCHAR2(10)  NOT NULL, 
    STUDENT_ID  NUMBER,
    OLD_NAME    VARCHAR2(100),
    NEW_NAME    VARCHAR2(100),
    OLD_GROUP   NUMBER,
    NEW_GROUP   NUMBER,
    CHANGED_BY  VARCHAR2(100) DEFAULT USER,
    CHANGED_AT  TIMESTAMP     DEFAULT SYSTIMESTAMP,
    CONSTRAINT PK_STUDENTS_LOG PRIMARY KEY (LOG_ID)
);

-- Триггер журналирования
CREATE OR REPLACE TRIGGER trg_students_audit
AFTER INSERT OR UPDATE OR DELETE ON STUDENTS
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        INSERT INTO STUDENTS_LOG (OPERATION, STUDENT_ID, NEW_NAME, NEW_GROUP)
        VALUES (v_operation, :NEW.ID, :NEW.NAME, :NEW.GROUP_ID);

    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        INSERT INTO STUDENTS_LOG (OPERATION, STUDENT_ID, OLD_NAME, NEW_NAME, OLD_GROUP, NEW_GROUP)
        VALUES (v_operation, :NEW.ID, :OLD.NAME, :NEW.NAME, :OLD.GROUP_ID, :NEW.GROUP_ID);

    ELSIF DELETING THEN
        v_operation := 'DELETE';
        INSERT INTO STUDENTS_LOG (OPERATION, STUDENT_ID, OLD_NAME, OLD_GROUP)
        VALUES (v_operation, :OLD.ID, :OLD.NAME, :OLD.GROUP_ID);
    END IF;
END trg_students_audit;
/

-- Задание 5: Процедура восстановления данных STUDENTS
-- по указанному временному моменту или смещению
CREATE OR REPLACE PROCEDURE restore_students(
    p_target_time    IN TIMESTAMP DEFAULT NULL,  
    p_offset_minutes IN NUMBER    DEFAULT NULL   
) IS
    v_restore_time TIMESTAMP;
    v_count_deleted  NUMBER := 0;
    v_count_restored NUMBER := 0;
BEGIN
    -- Определяем целевой момент восстановления
    IF p_target_time IS NOT NULL THEN
        v_restore_time := p_target_time;
    ELSIF p_offset_minutes IS NOT NULL THEN
        IF p_offset_minutes < 0 THEN
            RAISE_APPLICATION_ERROR(-20030,
                'Смещение должно быть положительным числом минут.');
        END IF;
        v_restore_time := SYSTIMESTAMP - NUMTODSINTERVAL(p_offset_minutes, 'MINUTE');
    ELSE
        RAISE_APPLICATION_ERROR(-20031,
            'Необходимо указать p_target_time или p_offset_minutes.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Восстановление на момент: ' ||
        TO_CHAR(v_restore_time, 'YYYY-MM-DD HH24:MI:SS'));

    -- Удаляем текущих студентов (без записи в журнал — отключаем триггер)
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_students_audit DISABLE';

    DELETE FROM STUDENTS;
    SELECT COUNT(*) INTO v_count_deleted FROM STUDENTS_LOG
    WHERE CHANGED_AT <= v_restore_time;

    -- Восстанавливаем состояние из журнала:
    -- Берём последнее состояние каждой записи до целевого момента
    FOR rec IN (
        SELECT DISTINCT sl.STUDENT_ID
        FROM STUDENTS_LOG sl
        WHERE sl.CHANGED_AT <= v_restore_time
    ) LOOP
        DECLARE
            v_last_op   VARCHAR2(10);
            v_last_name VARCHAR2(100);
            v_last_grp  NUMBER;
            v_log_time  TIMESTAMP;
        BEGIN
            SELECT OPERATION, NEW_NAME, NEW_GROUP, CHANGED_AT
            INTO v_last_op, v_last_name, v_last_grp, v_log_time
            FROM STUDENTS_LOG
            WHERE STUDENT_ID = rec.STUDENT_ID
              AND CHANGED_AT <= v_restore_time
              AND LOG_ID = (
                  SELECT MAX(LOG_ID) FROM STUDENTS_LOG
                  WHERE STUDENT_ID = rec.STUDENT_ID
                    AND CHANGED_AT <= v_restore_time
              );

            IF v_last_op != 'DELETE' THEN
                INSERT INTO STUDENTS (ID, NAME, GROUP_ID)
                VALUES (rec.STUDENT_ID, v_last_name, v_last_grp);
                v_count_restored := v_count_restored + 1;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL; 
        END;
    END LOOP;

    COMMIT;

    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_students_audit ENABLE';

    DBMS_OUTPUT.PUT_LINE('Восстановлено записей: ' || v_count_restored);

EXCEPTION
    WHEN OTHERS THEN
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_students_audit ENABLE';
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка восстановления: ' || SQLERRM);
        RAISE;
END restore_students;
/

-- Задание 6: обновление GROUPS.C_VAL при изменениях в STUDENTS.
--   - ORA-00036: рекурсия, т.к. apply_deltas делает UPDATE GROUPS, а значит срабатывает trg_groups_cval_after_stmt
--     -> исправлено добавлением защиты `g_is_applying_deltas` в pkg_group_cval.apply_deltas.

CREATE OR REPLACE PACKAGE pkg_group_cval AS
    TYPE t_group_delta IS TABLE OF NUMBER INDEX BY PLS_INTEGER;  -- group_id -> delta
    g_deltas t_group_delta;
    g_is_applying_deltas BOOLEAN := FALSE;
    PROCEDURE add_delta(p_group_id NUMBER, p_delta NUMBER);
    PROCEDURE apply_deltas;
END pkg_group_cval;
/
CREATE OR REPLACE PACKAGE BODY pkg_group_cval AS
    PROCEDURE add_delta(p_group_id NUMBER, p_delta NUMBER) IS
    BEGIN
        IF NOT g_deltas.EXISTS(p_group_id) THEN
            g_deltas(p_group_id) := 0;
        END IF;
        g_deltas(p_group_id) := g_deltas(p_group_id) + p_delta;
    END add_delta;

    PROCEDURE apply_deltas IS
        v_group_id NUMBER;
    BEGIN
        IF g_is_applying_deltas THEN
            RETURN;
        END IF;
        g_is_applying_deltas := TRUE;

        v_group_id := g_deltas.FIRST;
        BEGIN
            WHILE v_group_id IS NOT NULL LOOP
                UPDATE GROUPS
                SET C_VAL = GREATEST(C_VAL + g_deltas(v_group_id), 0)
                WHERE ID = v_group_id;
                v_group_id := g_deltas.NEXT(v_group_id);
            END LOOP;
            g_deltas.DELETE;
        EXCEPTION
            WHEN OTHERS THEN
                g_is_applying_deltas := FALSE;
                RAISE;
        END;

        g_is_applying_deltas := FALSE;
    END apply_deltas;
END pkg_group_cval;
/

CREATE OR REPLACE TRIGGER trg_update_group_cval
AFTER INSERT OR UPDATE OF GROUP_ID OR DELETE ON STUDENTS
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        pkg_group_cval.add_delta(:NEW.GROUP_ID, 1);
    ELSIF DELETING THEN
        pkg_group_cval.add_delta(:OLD.GROUP_ID, -1);
    ELSIF UPDATING AND :OLD.GROUP_ID != :NEW.GROUP_ID THEN
        pkg_group_cval.add_delta(:OLD.GROUP_ID, -1);
        pkg_group_cval.add_delta(:NEW.GROUP_ID, 1);
    END IF;
END trg_update_group_cval;
/


CREATE OR REPLACE TRIGGER trg_update_group_cval_stmt
AFTER INSERT OR UPDATE OF GROUP_ID OR DELETE ON STUDENTS
BEGIN
    BEGIN
        pkg_group_cval.apply_deltas;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -4091 THEN 
                NULL;  
            ELSE
                RAISE;
            END IF;
    END;
END trg_update_group_cval_stmt;
/

CREATE OR REPLACE TRIGGER trg_groups_cval_after_stmt
AFTER INSERT OR UPDATE OR DELETE ON GROUPS
BEGIN
    pkg_group_cval.apply_deltas;
END trg_groups_cval_after_stmt;
/


BEGIN
    NULL;
END;
/
SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_groups_autoinc' AS msg FROM dual;
SELECT '  INSERT без указания ID — ID назначается автоматически' AS msg FROM dual;
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-21', 0);
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-22', 0);

SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_groups_unique_name' AS msg FROM dual;
SELECT '  Попытка вставить дубликат имени "ПМ-21":' AS msg FROM dual;
BEGIN
    INSERT INTO GROUPS (NAME) VALUES ('ПМ-21');
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END;
/


SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_students_autoinc + trg_update_group_cval' AS msg FROM dual;
SELECT '  Добавляем студентов — C_VAL в GROUPS должен расти' AS msg FROM dual;
SELECT '  C_VAL до добавления студентов:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Иванов Иван', 1);
SELECT '  [trg_update_group_cval] INSERT Иванов Иван -> ПМ-21' AS msg FROM dual;
SELECT '  C_VAL после добавления Иванов Иван:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Петров Пётр', 1);
SELECT '  [trg_update_group_cval] INSERT Петров Пётр -> ПМ-21' AS msg FROM dual;
SELECT '  C_VAL после добавления Петров Пётр:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Сидоров Семён', 2);
SELECT '  [trg_update_group_cval] INSERT Сидоров Семён -> ПМ-22' AS msg FROM dual;
SELECT '  C_VAL после добавления Сидоров Семён:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

SELECT '  Итоговый список студентов (ID назначены автоматически):' AS msg FROM dual;
SELECT S.ID, S.NAME, S.GROUP_ID, G.NAME AS GROUP_NAME
FROM STUDENTS S
JOIN GROUPS G ON S.GROUP_ID = G.ID
ORDER BY S.ID;

BEGIN
    INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Тестов Тест', 99);
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END;
/
SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_students_fk_check' AS msg FROM dual;
SELECT '  Попытка добавить студента в несуществующую группу ID=99:' AS msg FROM dual;


BEGIN
    NULL;
END;
/
SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_update_group_cval при UPDATE GROUP_ID' AS msg FROM dual;
SELECT '  Переводим Иванов Иван из ПМ-21 (ID=1) в ПМ-22 (ID=2)' AS msg FROM dual;
SELECT '  C_VAL ДО перевода: ПМ-21 должна быть 2, ПМ-22 = 1' AS msg FROM dual;
UPDATE STUDENTSOU SET GRP_ID = 2 WHERE NAME = 'Иванов Иван';
SELECT '  [trg_update_group_cval] ПМ-21.C_VAL -= 1, ПМ-22.C_VAL += 1' AS msg FROM dual;
SELECT '  C_VAL ПОСЛЕ перевода:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_update_group_cval при DELETE' AS msg FROM dual;
SELECT '  Удаляем Петров Пётр из ПМ-21' AS msg FROM dual;
SELECT '  C_VAL ДО удаления:' AS msg FROM dual;
DELETE FROM STUDENTS WHERE NAME = 'Петров Пётр';
SELECT '  [trg_update_group_cval] ПМ-21.C_VAL -= 1' AS msg FROM dual;
SELECT '  C_VAL ПОСЛЕ удаления:' AS msg FROM dual;
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

BEGIN
    NULL;
END;
/
SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_students_audit — журнал всех операций' AS msg FROM dual;
SELECT
    LOG_ID,
    OPERATION,
    STUDENT_ID,
    OLD_NAME,
    NEW_NAME,
    OLD_GROUP,
    NEW_GROUP,
    TO_CHAR(CHANGED_AT,'HH24:MI:SS') AS AT_TIME
FROM STUDENTS_LOG
ORDER BY LOG_ID;

BEGIN
    NULL;
END;
/
SELECT '' AS msg FROM dual;
SELECT '  ТРИГГЕР: trg_groups_cascade_delete' AS msg FROM dual;
SELECT '  Удаляем группу ПМ-22 — студенты должны удалиться каскадно' AS msg FROM dual;
SELECT '  Студенты ПМ-22 ДО удаления группы:' AS msg FROM dual;
SELECT S.ID, S.NAME FROM STUDENTS S WHERE S.GROUP_ID = 2;
DELETE FROM GROUPS WHERE NAME = 'ПМ-22';
BEGIN
    NULL;
END;
/
SELECT '  Студенты ПОСЛЕ удаления группы ПМ-22 (ожидается 0 строк):' AS msg FROM dual;
SELECT S.ID, S.NAME FROM STUDENTS S WHERE S.GROUP_ID = 2;

BEGIN
    NULL;
END;
/
SELECT '  Итоговый журнал (включая каскадные DELETE):' AS msg FROM dual;
SELECT
    LOG_ID,
    OPERATION,
    STUDENT_ID,
    NVL(OLD_NAME, NEW_NAME) AS NAME,
    OLD_GROUP,
    NEW_GROUP,
    TO_CHAR(CHANGED_AT,'HH24:MI:SS') AS AT_TIME
FROM STUDENTS_LOG
ORDER BY LOG_ID;

COMMIT;
