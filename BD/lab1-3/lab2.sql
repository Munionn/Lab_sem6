-- ============================================================
-- Лабораторная работа 2: Триггеры
-- ============================================================

-- ============================================================
-- Задание 1: Создание таблиц STUDENTS и GROUPS
-- ============================================================
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

-- ============================================================
-- Задание 2: Триггеры — уникальность ID, автоинкремент,
--            уникальность GROUPS.NAME
-- ============================================================

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

-- ============================================================
-- Задание 3: Триггер Foreign Key с каскадным удалением
-- STUDENTS -> GROUPS (при удалении группы удаляются студенты)
-- ============================================================

-- Проверка FK при INSERT/UPDATE в STUDENTS: GROUP_ID должен существовать
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

-- ============================================================
-- Задание 4: Триггер журналирования действий над STUDENTS
-- ============================================================

-- Таблица журнала
CREATE TABLE STUDENTS_LOG (
    LOG_ID      NUMBER GENERATED ALWAYS AS IDENTITY,
    OPERATION   VARCHAR2(10)  NOT NULL,  -- INSERT / UPDATE / DELETE
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

-- ============================================================
-- Задание 5: Процедура восстановления данных STUDENTS
-- по указанному временному моменту или смещению
-- ============================================================
CREATE OR REPLACE PROCEDURE restore_students(
    p_target_time    IN TIMESTAMP DEFAULT NULL,  -- конкретный момент
    p_offset_minutes IN NUMBER    DEFAULT NULL   -- смещение в минутах назад
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
            -- Берём последнюю операцию для данного студента
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
                NULL; -- пропускаем
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

-- ============================================================
-- Задание 6: Триггер обновления C_VAL в GROUPS
-- при изменении данных в STUDENTS
-- ============================================================
CREATE OR REPLACE TRIGGER trg_update_group_cval
AFTER INSERT OR UPDATE OF GROUP_ID OR DELETE ON STUDENTS
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        -- Увеличиваем счётчик для новой группы
        UPDATE GROUPS
        SET C_VAL = C_VAL + 1
        WHERE ID = :NEW.GROUP_ID;

    ELSIF DELETING THEN
        -- Уменьшаем счётчик группы удалённого студента
        UPDATE GROUPS
        SET C_VAL = GREATEST(C_VAL - 1, 0)
        WHERE ID = :OLD.GROUP_ID;

    ELSIF UPDATING THEN
        -- Если студент сменил группу
        IF :OLD.GROUP_ID != :NEW.GROUP_ID THEN
            UPDATE GROUPS
            SET C_VAL = GREATEST(C_VAL - 1, 0)
            WHERE ID = :OLD.GROUP_ID;

            UPDATE GROUPS
            SET C_VAL = C_VAL + 1
            WHERE ID = :NEW.GROUP_ID;
        END IF;
    END IF;
END trg_update_group_cval;
/

-- ============================================================
-- Тестовые данные
-- ============================================================
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-21', 0);
INSERT INTO GROUPS (NAME, C_VAL) VALUES ('ПМ-22', 0);

INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Иванов Иван', 1);
INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Петров Пётр', 1);
INSERT INTO STUDENTS (NAME, GROUP_ID) VALUES ('Сидоров Семён', 2);

-- Проверка C_VAL
SELECT G.NAME, G.C_VAL FROM GROUPS G;

-- Перевод студента
UPDATE STUDENTS SET GROUP_ID = 2 WHERE NAME = 'Иванов Иван';
SELECT G.NAME, G.C_VAL FROM GROUPS G;

-- Удаление студента
DELETE FROM STUDENTS WHERE NAME = 'Петров Пётр';
SELECT G.NAME, G.C_VAL FROM GROUPS G;

-- Журнал
SELECT * FROM STUDENTS_LOG ORDER BY LOG_ID;

COMMIT;
