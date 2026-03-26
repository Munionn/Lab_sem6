-- Лабораторная работа 2: Триггеры

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

-- Автоинкремент ID для GROUPS
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

            -- Если последняя операция не DELETE — восстанавливаем запись
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

    -- Включаем триггер обратно
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

-- Задание 6: Триггер обновления C_VAL в GROUPS
-- при изменении данных в STUDENTS
--
-- Чтобы избежать ORA-04091 (mutating table) при каскадном удалении
-- (DELETE FROM GROUPS -> trg_groups_cascade_delete -> DELETE FROM STUDENTS ->
--  trg_update_group_cval пытается UPDATE GROUPS), обновление C_VAL перенесено
--  в AFTER STATEMENT: в FOR EACH ROW только накапливаем дельты в пакете.

CREATE OR REPLACE PACKAGE pkg_group_cval AS
    TYPE t_group_delta IS TABLE OF NUMBER INDEX BY PLS_INTEGER;  -- group_id -> delta
    g_deltas t_group_delta;
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
        v_group_id := g_deltas.FIRST;
        WHILE v_group_id IS NOT NULL LOOP
            UPDATE GROUPS
            SET C_VAL = GREATEST(C_VAL + g_deltas(v_group_id), 0)
            WHERE ID = v_group_id;
            v_group_id := g_deltas.NEXT(v_group_id);
        END LOOP;
        g_deltas.DELETE;
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

-- Применяем дельты после DML по STUDENTS (для обычного INSERT/UPDATE/DELETE по студентам).
-- При каскадном DELETE из GROUPS таблица GROUPS мутирует -> ORA-04091, ловим и не падаем;
-- тогда дельты применит TRG_GROUPS_CVAL_AFTER_STMT после завершения DELETE FROM GROUPS.
CREATE OR REPLACE TRIGGER trg_update_group_cval_stmt
AFTER INSERT OR UPDATE OF GROUP_ID OR DELETE ON STUDENTS
BEGIN
    BEGIN
        pkg_group_cval.apply_deltas;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -4091 THEN  -- ORA-04091: mutating table
                NULL;  -- применит триггер на GROUPS после завершения операций по GROUPS
            ELSE
                RAISE;
            END IF;
    END;
END trg_update_group_cval_stmt;
/

-- Применяем накопленные дельты C_VAL после операций по GROUPS (в т.ч. после каскадного DELETE).
CREATE OR REPLACE TRIGGER trg_groups_cval_after_stmt
AFTER INSERT OR UPDATE OR DELETE ON GROUPS
FOR EACH STATEMENT
BEGIN
    pkg_group_cval.apply_deltas;
END trg_groups_cval_after_stmt;
/


-- ------------------------------------------------------------
-- Триггер: trg_groups_autoinc  (автоинкремент ID у GROUPS)
-- Триггер: trg_groups_unique_name (уникальность NAME у GROUPS)
-- ------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_groups_autoinc');
    DBMS_OUTPUT.PUT_LINE('  INSERT без указания ID — ID назначается автоматически');
END;
/
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-21', 0);
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-22', 0);

-- Показываем назначенные ID
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_groups_unique_name');
    DBMS_OUTPUT.PUT_LINE('  Попытка вставить дубликат имени "ПМ-21":');
    INSERT INTO GROUPS (NAME) VALUES ('ПМ-21');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  [ОЖИДАЕМАЯ ОШИБКА] ' || SQLERRM);
END;
/

-- ------------------------------------------------------------
-- Триггер: trg_students_autoinc  (автоинкремент ID у STUDENTS)
-- Триггер: trg_students_fk_check (FK: GROUP_ID должен существовать)
-- Триггер: trg_update_group_cval (C_VAL обновляется при INSERT)
-- ------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_students_autoinc + trg_update_group_cval');
    DBMS_OUTPUT.PUT_LINE('  Добавляем студентов — C_VAL в GROUPS должен расти');
    DBMS_OUTPUT.PUT_LINE('  C_VAL до добавления студентов:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Иванов Иван', 1);
BEGIN
    DBMS_OUTPUT.PUT_LINE('  [trg_update_group_cval] INSERT Иванов Иван -> ПМ-21');
    DBMS_OUTPUT.PUT_LINE('  C_VAL после добавления Иванов Иван:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Петров Пётр', 1);
BEGIN
    DBMS_OUTPUT.PUT_LINE('  [trg_update_group_cval] INSERT Петров Пётр -> ПМ-21');
    DBMS_OUTPUT.PUT_LINE('  C_VAL после добавления Петров Пётр:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Сидоров Семён', 2);
BEGIN
    DBMS_OUTPUT.PUT_LINE('  [trg_update_group_cval] INSERT Сидоров Семён -> ПМ-22');
    DBMS_OUTPUT.PUT_LINE('  C_VAL после добавления Сидоров Семён:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

-- Таблица студентов
BEGIN
    DBMS_OUTPUT.PUT_LINE('  Итоговый список студентов (ID назначены автоматически):');
END;
/
SELECT S.ID, S.NAME, S.GROUP_ID, G.NAME AS GROUP_NAME
FROM STUDENTS S
JOIN GROUPS G ON S.GROUP_ID = G.ID
ORDER BY S.ID;

BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_students_fk_check');
    DBMS_OUTPUT.PUT_LINE('  Попытка добавить студента в несуществующую группу ID=99:');
    INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Тестов Тест', 99);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  [ОЖИДАЕМАЯ ОШИБКА] ' || SQLERRM);
END;
/

-- ------------------------------------------------------------
-- Триггер: trg_update_group_cval при UPDATE (смена группы)
-- Триггер: trg_students_audit (журнал)
-- ------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_update_group_cval при UPDATE GROUP_ID');
    DBMS_OUTPUT.PUT_LINE('  Переводим Иванов Иван из ПМ-21 (ID=1) в ПМ-22 (ID=2)');
    DBMS_OUTPUT.PUT_LINE('  C_VAL ДО перевода: ПМ-21 должна быть 2, ПМ-22 = 1');
END;
/
UPDATE STUDENTS SET GROUP_ID = 2 WHERE NAME = 'Иванов Иван';
BEGIN
    DBMS_OUTPUT.PUT_LINE('  [trg_update_group_cval] ПМ-21.C_VAL -= 1, ПМ-22.C_VAL += 1');
    DBMS_OUTPUT.PUT_LINE('  C_VAL ПОСЛЕ перевода:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

-- Триггер: trg_update_group_cval при DELETE
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_update_group_cval при DELETE');
    DBMS_OUTPUT.PUT_LINE('  Удаляем Петров Пётр из ПМ-21');
    DBMS_OUTPUT.PUT_LINE('  C_VAL ДО удаления:');
END;
/
DELETE FROM STUDENTS WHERE NAME = 'Петров Пётр';
BEGIN
    DBMS_OUTPUT.PUT_LINE('  [trg_update_group_cval] ПМ-21.C_VAL -= 1');
    DBMS_OUTPUT.PUT_LINE('  C_VAL ПОСЛЕ удаления:');
END;
/
SELECT ID, NAME, C_VAL FROM GROUPS ORDER BY ID;

-- ------------------------------------------------------------
-- Журнал аудита (trg_students_audit)
-- ------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_students_audit — журнал всех операций');
END;
/
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

-- ------------------------------------------------------------
-- Триггер: trg_groups_cascade_delete
-- ------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ТРИГГЕР: trg_groups_cascade_delete');
    DBMS_OUTPUT.PUT_LINE('  Удаляем группу ПМ-22 — студенты должны удалиться каскадно');
    DBMS_OUTPUT.PUT_LINE('  Студенты ПМ-22 ДО удаления группы:');
END;
/
SELECT S.ID, S.NAME FROM STUDENTS S WHERE S.GROUP_ID = 2;
DELETE FROM GROUPS WHERE NAME = 'ПМ-22';
BEGIN
    DBMS_OUTPUT.PUT_LINE('  Студенты ПОСЛЕ удаления группы ПМ-22 (ожидается 0 строк):');
END;
/
SELECT S.ID, S.NAME FROM STUDENTS S WHERE S.GROUP_ID = 2;

-- Итоговый журнал (включая удалённых при каскаде)
BEGIN
    DBMS_OUTPUT.PUT_LINE('  Итоговый журнал (включая каскадные DELETE):');
END;
/
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
