-- Lab 3 (reworked): schema compare + DDL generator
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

CREATE OR REPLACE PACKAGE schema_compare_pkg AUTHID CURRENT_USER AS
    TYPE t_varchar_tab IS TABLE OF VARCHAR2(4000);

    PROCEDURE compare_schemas(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2,
        p_ddl_script  OUT CLOB
    );
END schema_compare_pkg;
/

CREATE OR REPLACE PACKAGE BODY schema_compare_pkg AS
    g_dev_schema  VARCHAR2(128);
    g_prod_schema VARCHAR2(128);
    g_ddl         CLOB;

    PROCEDURE append_ddl(p_text IN VARCHAR2) IS
    BEGIN
        IF p_text IS NOT NULL THEN
            DBMS_LOB.WRITEAPPEND(g_ddl, LENGTH(p_text), p_text);
        END IF;
    END;

    PROCEDURE append_ddl_line(p_text IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        append_ddl(NVL(p_text, '') || CHR(10));
    END;

    FUNCTION table_exists(p_schema IN VARCHAR2, p_table IN VARCHAR2) RETURN BOOLEAN IS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_cnt
          FROM all_tables
         WHERE owner = UPPER(p_schema)
           AND table_name = p_table;
        RETURN v_cnt > 0;
    END;

    FUNCTION tables_differ(p_table IN VARCHAR2) RETURN BOOLEAN IS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_cnt
          FROM (
                SELECT column_name, data_type, data_length, data_precision, data_scale, nullable, column_id
                  FROM all_tab_columns
                 WHERE owner = UPPER(g_dev_schema)
                   AND table_name = p_table
                MINUS
                SELECT column_name, data_type, data_length, data_precision, data_scale, nullable, column_id
                  FROM all_tab_columns
                 WHERE owner = UPPER(g_prod_schema)
                   AND table_name = p_table
               );
        IF v_cnt > 0 THEN
            RETURN TRUE;
        END IF;

        SELECT COUNT(*)
          INTO v_cnt
          FROM (
                SELECT column_name, data_type, data_length, data_precision, data_scale, nullable, column_id
                  FROM all_tab_columns
                 WHERE owner = UPPER(g_prod_schema)
                   AND table_name = p_table
                MINUS
                SELECT column_name, data_type, data_length, data_precision, data_scale, nullable, column_id
                  FROM all_tab_columns
                 WHERE owner = UPPER(g_dev_schema)
                   AND table_name = p_table
               );
        RETURN v_cnt > 0;
    END;

    PROCEDURE topo_sort_tables(
        p_tables     IN t_varchar_tab,
        p_sorted     OUT t_varchar_tab,
        p_has_cycle  OUT BOOLEAN
    ) IS
        TYPE t_num_tab IS TABLE OF NUMBER INDEX BY VARCHAR2(128);
        TYPE t_str_tab IS TABLE OF VARCHAR2(128) INDEX BY PLS_INTEGER;

        v_indegree  t_num_tab;
        v_queue     t_str_tab;
        v_qhead     PLS_INTEGER := 1;
        v_qtail     PLS_INTEGER := 0;
        v_processed PLS_INTEGER := 0;
        v_tbl       VARCHAR2(128);
        v_exists    BOOLEAN;
    BEGIN
        p_sorted := t_varchar_tab();
        p_has_cycle := FALSE;

        FOR i IN 1 .. p_tables.COUNT LOOP
            v_indegree(p_tables(i)) := 0;
        END LOOP;

        FOR i IN 1 .. p_tables.COUNT LOOP
            FOR rec IN (
                SELECT c.table_name AS child, r.table_name AS parent
                  FROM all_constraints c
                  JOIN all_constraints r
                    ON c.r_constraint_name = r.constraint_name
                   AND c.r_owner = r.owner
                 WHERE c.owner = UPPER(g_dev_schema)
                   AND c.constraint_type = 'R'
                   AND c.table_name = p_tables(i)
                   AND r.table_name != c.table_name
            ) LOOP
                v_exists := FALSE;
                FOR j IN 1 .. p_tables.COUNT LOOP
                    IF p_tables(j) = rec.parent THEN
                        v_exists := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
                IF v_exists THEN
                    v_indegree(rec.child) := v_indegree(rec.child) + 1;
                END IF;
            END LOOP;
        END LOOP;

        FOR i IN 1 .. p_tables.COUNT LOOP
            IF v_indegree(p_tables(i)) = 0 THEN
                v_qtail := v_qtail + 1;
                v_queue(v_qtail) := p_tables(i);
            END IF;
        END LOOP;

        WHILE v_qhead <= v_qtail LOOP
            v_tbl := v_queue(v_qhead);
            v_qhead := v_qhead + 1;
            v_processed := v_processed + 1;
            p_sorted.EXTEND;
            p_sorted(p_sorted.COUNT) := v_tbl;

            FOR rec IN (
                SELECT DISTINCT c.table_name AS child
                  FROM all_constraints c
                  JOIN all_constraints r
                    ON c.r_constraint_name = r.constraint_name
                   AND c.r_owner = r.owner
                 WHERE r.owner = UPPER(g_dev_schema)
                   AND r.table_name = v_tbl
                   AND c.table_name != v_tbl
                   AND c.constraint_type = 'R'
                   AND c.owner = UPPER(g_dev_schema)
            ) LOOP
                v_exists := FALSE;
                FOR j IN 1 .. p_tables.COUNT LOOP
                    IF p_tables(j) = rec.child THEN
                        v_exists := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
                IF v_exists THEN
                    v_indegree(rec.child) := v_indegree(rec.child) - 1;
                    IF v_indegree(rec.child) = 0 THEN
                        v_qtail := v_qtail + 1;
                        v_queue(v_qtail) := rec.child;
                    END IF;
                END IF;
            END LOOP;
        END LOOP;

        IF v_processed < p_tables.COUNT THEN
            p_has_cycle := TRUE;
            FOR i IN 1 .. p_tables.COUNT LOOP
                v_exists := FALSE;
                FOR j IN 1 .. p_sorted.COUNT LOOP
                    IF p_sorted(j) = p_tables(i) THEN
                        v_exists := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
                IF NOT v_exists THEN
                    p_sorted.EXTEND;
                    p_sorted(p_sorted.COUNT) := p_tables(i);
                END IF;
            END LOOP;
        END IF;
    END topo_sort_tables;

    PROCEDURE process_tables IS
        v_tables_to_process t_varchar_tab := t_varchar_tab();
        v_sorted            t_varchar_tab;
        v_has_cycle         BOOLEAN;
        v_reason            VARCHAR2(20);
        v_col_list          VARCHAR2(32767);
        v_col_sep           VARCHAR2(2);
    BEGIN
        -- NEW in DEV
        FOR rec IN (
            SELECT table_name
              FROM all_tables
             WHERE owner = UPPER(g_dev_schema)
            MINUS
            SELECT table_name
              FROM all_tables
             WHERE owner = UPPER(g_prod_schema)
        ) LOOP
            v_tables_to_process.EXTEND;
            v_tables_to_process(v_tables_to_process.COUNT) := rec.table_name;
        END LOOP;

        -- MODIFIED structure
        FOR rec IN (
            SELECT table_name
              FROM all_tables
             WHERE owner = UPPER(g_dev_schema)
               AND table_name IN (
                   SELECT table_name FROM all_tables WHERE owner = UPPER(g_prod_schema)
               )
        ) LOOP
            IF tables_differ(rec.table_name) THEN
                v_tables_to_process.EXTEND;
                v_tables_to_process(v_tables_to_process.COUNT) := rec.table_name;
            END IF;
        END LOOP;

        IF v_tables_to_process.COUNT = 0 THEN
            append_ddl_line('-- No table differences found between schemas');
            RETURN;
        END IF;

        topo_sort_tables(v_tables_to_process, v_sorted, v_has_cycle);
        IF v_has_cycle THEN
            append_ddl_line('-- WARNING: Circular FK dependencies detected.');
            append_ddl_line('-- Manual fix may be required.');
            append_ddl_line('');
        END IF;

        append_ddl_line('-- ============================================================');
        append_ddl_line('-- TABLES: Differences between DEV and PROD');
        append_ddl_line('-- ============================================================');
        append_ddl_line('');

        FOR i IN 1 .. v_sorted.COUNT LOOP
            DECLARE
                v_tbl VARCHAR2(128) := v_sorted(i);
            BEGIN
                IF NOT table_exists(g_prod_schema, v_tbl) THEN
                    v_reason := 'NEW';
                ELSE
                    v_reason := 'MODIFIED';
                END IF;

                append_ddl_line('-- Table: ' || v_tbl || ' [' || v_reason || ']');

                IF v_reason = 'MODIFIED' THEN
                    append_ddl_line('-- Existing table in PROD will be dropped (data loss risk!)');
                    append_ddl_line('DROP TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl || ' CASCADE CONSTRAINTS;');
                END IF;

                v_col_list := '';
                v_col_sep := '';
                FOR col IN (
                    SELECT column_name, data_type, data_length, data_precision, data_scale, nullable, data_default
                      FROM all_tab_columns
                     WHERE owner = UPPER(g_dev_schema)
                       AND table_name = v_tbl
                     ORDER BY column_id
                ) LOOP
                    DECLARE
                        v_col_def VARCHAR2(1000);
                        v_dtype   VARCHAR2(200);
                    BEGIN
                        CASE col.data_type
                            WHEN 'NUMBER' THEN
                                IF col.data_precision IS NOT NULL THEN
                                    v_dtype := 'NUMBER(' || col.data_precision ||
                                               CASE WHEN col.data_scale IS NOT NULL THEN ',' || col.data_scale ELSE '' END || ')';
                                ELSE
                                    v_dtype := 'NUMBER';
                                END IF;
                            WHEN 'VARCHAR2' THEN v_dtype := 'VARCHAR2(' || col.data_length || ')';
                            WHEN 'NVARCHAR2' THEN v_dtype := 'NVARCHAR2(' || col.data_length || ')';
                            WHEN 'CHAR' THEN v_dtype := 'CHAR(' || col.data_length || ')';
                            ELSE v_dtype := col.data_type;
                        END CASE;

                        v_col_def := v_col_sep || '    ' || col.column_name || ' ' || v_dtype;
                        IF col.data_default IS NOT NULL THEN
                            v_col_def := v_col_def || ' DEFAULT ' || TRIM(col.data_default);
                        END IF;
                        IF col.nullable = 'N' THEN
                            v_col_def := v_col_def || ' NOT NULL';
                        END IF;
                        v_col_list := v_col_list || v_col_def;
                        v_col_sep := ',' || CHR(10);
                    END;
                END LOOP;

                append_ddl_line('CREATE TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl || ' (');
                append_ddl(v_col_list);
                append_ddl_line('');
                append_ddl_line(');');

                -- Constraints
                FOR con IN (
                    SELECT constraint_name, constraint_type, search_condition,
                           r_owner, r_constraint_name, delete_rule
                      FROM all_constraints
                     WHERE owner = UPPER(g_dev_schema)
                       AND table_name = v_tbl
                       AND constraint_type IN ('P','U','C','R')
                       AND generated = 'USER NAME'
                ) LOOP
                    DECLARE
                        v_col_names VARCHAR2(2000) := '';
                        v_ref_cols  VARCHAR2(2000) := '';
                        v_sep       VARCHAR2(2) := '';
                        v_ref_table VARCHAR2(128);
                    BEGIN
                        FOR cc IN (
                            SELECT column_name
                              FROM all_cons_columns
                             WHERE owner = UPPER(g_dev_schema)
                               AND constraint_name = con.constraint_name
                             ORDER BY position
                        ) LOOP
                            v_col_names := v_col_names || v_sep || cc.column_name;
                            v_sep := ',';
                        END LOOP;

                        IF con.constraint_type = 'P' THEN
                            append_ddl_line('ALTER TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl ||
                                            ' ADD CONSTRAINT ' || con.constraint_name ||
                                            ' PRIMARY KEY (' || v_col_names || ');');
                        ELSIF con.constraint_type = 'U' THEN
                            append_ddl_line('ALTER TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl ||
                                            ' ADD CONSTRAINT ' || con.constraint_name ||
                                            ' UNIQUE (' || v_col_names || ');');
                        ELSIF con.constraint_type = 'C' THEN
                            append_ddl_line('ALTER TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl ||
                                            ' ADD CONSTRAINT ' || con.constraint_name ||
                                            ' CHECK (' || con.search_condition || ');');
                        ELSIF con.constraint_type = 'R' THEN
                            v_sep := '';
                            SELECT table_name
                              INTO v_ref_table
                              FROM all_constraints
                             WHERE owner = con.r_owner
                               AND constraint_name = con.r_constraint_name;

                            FOR rc IN (
                                SELECT column_name
                                  FROM all_cons_columns
                                 WHERE owner = con.r_owner
                                   AND constraint_name = con.r_constraint_name
                                 ORDER BY position
                            ) LOOP
                                v_ref_cols := v_ref_cols || v_sep || rc.column_name;
                                v_sep := ',';
                            END LOOP;

                            append_ddl_line('ALTER TABLE ' || UPPER(g_prod_schema) || '.' || v_tbl ||
                                            ' ADD CONSTRAINT ' || con.constraint_name ||
                                            ' FOREIGN KEY (' || v_col_names || ')' ||
                                            ' REFERENCES ' || UPPER(g_prod_schema) || '.' || v_ref_table ||
                                            ' (' || v_ref_cols || ')' ||
                                            CASE con.delete_rule
                                                WHEN 'CASCADE' THEN ' ON DELETE CASCADE'
                                                ELSE ''
                                            END || ';');
                        END IF;
                    END;
                END LOOP;

                append_ddl_line('');
            END;
        END LOOP;

        -- Drop tables existing in PROD but absent in DEV
        FOR rec IN (
            SELECT table_name
              FROM all_tables
             WHERE owner = UPPER(g_prod_schema)
               AND table_name NOT IN (
                   SELECT table_name FROM all_tables WHERE owner = UPPER(g_dev_schema)
               )
        ) LOOP
            append_ddl_line('-- Table ' || rec.table_name || ' exists in PROD but not in DEV - dropping');
            append_ddl_line('DROP TABLE ' || UPPER(g_prod_schema) || '.' || rec.table_name || ' CASCADE CONSTRAINTS;');
            append_ddl_line('');
        END LOOP;
    END process_tables;

    PROCEDURE process_indexes IS
        v_col_list VARCHAR2(4000);
        v_sep      VARCHAR2(2);
    BEGIN
        append_ddl_line('-- ============================================================');
        append_ddl_line('-- INDEXES');
        append_ddl_line('-- ============================================================');
        append_ddl_line('');

        FOR rec IN (
            SELECT d.index_name, d.table_name, d.uniqueness
              FROM all_indexes d
             WHERE d.owner = UPPER(g_dev_schema)
               AND d.index_type NOT IN ('LOB')
               AND d.generated = 'N'
               AND d.index_name NOT LIKE 'SYS\_%' ESCAPE '\'
               AND d.index_name NOT IN (
                   SELECT constraint_name FROM all_constraints WHERE owner = UPPER(g_dev_schema)
               )
               AND (
                    NOT EXISTS (
                        SELECT 1 FROM all_indexes p
                         WHERE p.owner = UPPER(g_prod_schema)
                           AND p.index_name = d.index_name
                    )
                    OR EXISTS (
                        SELECT 1
                          FROM (
                                SELECT column_name, column_position, descend
                                  FROM all_ind_columns
                                 WHERE index_owner = UPPER(g_dev_schema)
                                   AND index_name = d.index_name
                                MINUS
                                SELECT column_name, column_position, descend
                                  FROM all_ind_columns
                                 WHERE index_owner = UPPER(g_prod_schema)
                                   AND index_name = d.index_name
                               )
                    )
               )
        ) LOOP
            DECLARE
                v_idx_exists NUMBER := 0;
            BEGIN
                SELECT COUNT(*)
                  INTO v_idx_exists
                  FROM all_indexes p
                 WHERE p.owner = UPPER(g_prod_schema)
                   AND p.index_name = rec.index_name;

                IF v_idx_exists > 0 THEN
                append_ddl_line('DROP INDEX ' || UPPER(g_prod_schema) || '.' || rec.index_name || ';');
                END IF;
            END;

            v_col_list := '';
            v_sep := '';
            FOR col IN (
                SELECT column_name, descend
                  FROM all_ind_columns
                 WHERE index_owner = UPPER(g_dev_schema)
                   AND index_name = rec.index_name
                 ORDER BY column_position
            ) LOOP
                v_col_list := v_col_list || v_sep || col.column_name ||
                              CASE WHEN col.descend = 'DESC' THEN ' DESC' ELSE '' END;
                v_sep := ', ';
            END LOOP;

            append_ddl_line(
                CASE rec.uniqueness WHEN 'UNIQUE' THEN 'CREATE UNIQUE INDEX ' ELSE 'CREATE INDEX ' END ||
                UPPER(g_prod_schema) || '.' || rec.index_name ||
                ' ON ' || UPPER(g_prod_schema) || '.' || rec.table_name ||
                ' (' || v_col_list || ');'
            );
            append_ddl_line('');
        END LOOP;
    END process_indexes;

    PROCEDURE process_code_objects IS
        v_dev_src  CLOB;
        v_prod_src CLOB;
    BEGIN
        append_ddl_line('-- ============================================================');
        append_ddl_line('-- PROCEDURES, FUNCTIONS, PACKAGES, TRIGGERS');
        append_ddl_line('-- ============================================================');
        append_ddl_line('');

        FOR rec IN (
            SELECT object_name, object_type
              FROM (
                    SELECT object_name, object_type
                      FROM all_objects
                     WHERE owner = UPPER(g_dev_schema)
                       AND object_type IN ('PACKAGE','PACKAGE BODY','TRIGGER')
                    UNION ALL
                    SELECT object_name, object_type
                      FROM all_procedures
                     WHERE owner = UPPER(g_dev_schema)
                       AND object_type IN ('PROCEDURE','FUNCTION')
                       AND procedure_name IS NULL
                   )
             GROUP BY object_name, object_type
             ORDER BY object_type, object_name
        ) LOOP
            DECLARE
                v_exists NUMBER;
                v_is_diff BOOLEAN := FALSE;
            BEGIN
                SELECT COUNT(*)
                  INTO v_exists
                  FROM all_objects
                 WHERE owner = UPPER(g_prod_schema)
                   AND object_name = rec.object_name
                   AND object_type = rec.object_type;

                IF v_exists > 0 THEN
                    v_dev_src := EMPTY_CLOB();
                    v_prod_src := EMPTY_CLOB();

                    FOR src IN (
                        SELECT text FROM all_source
                         WHERE owner = UPPER(g_dev_schema)
                           AND name = rec.object_name
                           AND type = rec.object_type
                         ORDER BY line
                    ) LOOP
                        v_dev_src := v_dev_src || src.text;
                    END LOOP;

                    FOR src IN (
                        SELECT text FROM all_source
                         WHERE owner = UPPER(g_prod_schema)
                           AND name = rec.object_name
                           AND type = rec.object_type
                         ORDER BY line
                    ) LOOP
                        v_prod_src := v_prod_src || src.text;
                    END LOOP;

                    IF DBMS_LOB.COMPARE(v_dev_src, v_prod_src) != 0 THEN
                        v_is_diff := TRUE;
                    END IF;
                ELSE
                    v_is_diff := TRUE;
                END IF;

                IF v_is_diff THEN
                    append_ddl_line('-- ' || rec.object_type || ': ' || rec.object_name ||
                                    CASE WHEN v_exists > 0 THEN ' [MODIFIED]' ELSE ' [NEW]' END);
                    BEGIN
                        append_ddl(DBMS_METADATA.GET_DDL(rec.object_type, rec.object_name, UPPER(g_dev_schema)));
                    EXCEPTION
                        WHEN OTHERS THEN
                            append_ddl_line('-- WARNING: failed to fetch DDL via DBMS_METADATA for ' ||
                                            rec.object_type || ' ' || rec.object_name || ': ' || SQLERRM);
                            append_ddl('CREATE OR REPLACE ');
                            FOR src IN (
                                SELECT text FROM all_source
                                 WHERE owner = UPPER(g_dev_schema)
                                   AND name = rec.object_name
                                   AND type = rec.object_type
                                 ORDER BY line
                            ) LOOP
                                append_ddl(src.text);
                            END LOOP;
                        END;
                    append_ddl_line('/');
                    append_ddl_line('');
                END IF;
            END;
        END LOOP;
    END process_code_objects;

    PROCEDURE compare_schemas(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2,
        p_ddl_script  OUT CLOB
    ) IS
        v_dev_exists   NUMBER := 0;
        v_prod_exists  NUMBER := 0;
        v_dev_tables   NUMBER := 0;
        v_prod_tables  NUMBER := 0;
    BEGIN
        g_dev_schema  := UPPER(p_dev_schema);
        g_prod_schema := UPPER(p_prod_schema);
        DBMS_LOB.CREATETEMPORARY(g_ddl, TRUE);

        -- Явная диагностика после reset/down -v:
        -- часто контейнер поднимают "с нуля", а DEV/PROD ещё не созданы/не заполнены.
        SELECT COUNT(*) INTO v_dev_exists FROM all_users WHERE username = g_dev_schema;
        SELECT COUNT(*) INTO v_prod_exists FROM all_users WHERE username = g_prod_schema;

        IF v_dev_exists = 0 OR v_prod_exists = 0 THEN
            append_ddl_line('-- ERROR: schemas not found.');
            append_ddl_line('-- DEV exists : ' || CASE WHEN v_dev_exists = 1 THEN 'YES' ELSE 'NO' END);
            append_ddl_line('-- PROD exists: ' || CASE WHEN v_prod_exists = 1 THEN 'YES' ELSE 'NO' END);
            append_ddl_line('-- Create schemas first (run reset/seed script as SYS/SYSTEM).');
            p_ddl_script := g_ddl;
            DBMS_LOB.FREETEMPORARY(g_ddl);
            RETURN;
        END IF;

        SELECT COUNT(*) INTO v_dev_tables FROM all_tables WHERE owner = g_dev_schema;
        SELECT COUNT(*) INTO v_prod_tables FROM all_tables WHERE owner = g_prod_schema;

        append_ddl_line('-- ===========================================================');
        append_ddl_line('-- DDL Migration Script');
        append_ddl_line('-- DEV schema  : ' || g_dev_schema);
        append_ddl_line('-- PROD schema : ' || g_prod_schema);
        append_ddl_line('-- Generated   : ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
        append_ddl_line('-- ===========================================================');
        append_ddl_line('');
        append_ddl_line('-- DEV tables : ' || v_dev_tables);
        append_ddl_line('-- PROD tables: ' || v_prod_tables);
        append_ddl_line('');

        process_tables;
        process_indexes;
        process_code_objects;

        p_ddl_script := g_ddl;
        DBMS_LOB.FREETEMPORARY(g_ddl);
    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_LOB.ISTEMPORARY(g_ddl) = 1 THEN
                DBMS_LOB.FREETEMPORARY(g_ddl);
            END IF;
            RAISE;
    END compare_schemas;
END schema_compare_pkg;
/

-- Print generated DDL as DBMS_OUTPUT
DECLARE
    v_ddl   CLOB;
    v_pos   PLS_INTEGER := 1;
    v_chunk VARCHAR2(32767);
BEGIN
    schema_compare_pkg.compare_schemas(
        p_dev_schema  => 'DEV_SCHEMA',
        p_prod_schema => 'PROD_SCHEMA',
        p_ddl_script  => v_ddl
    );

    WHILE v_pos <= DBMS_LOB.GETLENGTH(v_ddl) LOOP
        v_chunk := DBMS_LOB.SUBSTR(v_ddl, 32767, v_pos);
        DBMS_OUTPUT.PUT_LINE(v_chunk);
        v_pos := v_pos + 32767;
    END LOOP;
END;
/


CREATE OR REPLACE PACKAGE pkg_schema_compare AS
    PROCEDURE compare_tables(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    );

    PROCEDURE compare_all_objects(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    );

    PROCEDURE generate_sync_ddl(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    );
END pkg_schema_compare;
/

CREATE OR REPLACE PACKAGE BODY pkg_schema_compare AS
    PROCEDURE print_clob(p_text IN CLOB) IS
        v_pos   PLS_INTEGER := 1;
        v_chunk VARCHAR2(32767);
    BEGIN
        IF p_text IS NULL THEN
            RETURN;
        END IF;
        WHILE v_pos <= DBMS_LOB.GETLENGTH(p_text) LOOP
            v_chunk := DBMS_LOB.SUBSTR(p_text, 32767, v_pos);
            DBMS_OUTPUT.PUT_LINE(v_chunk);
            v_pos := v_pos + 32767;
        END LOOP;
    END print_clob;

    PROCEDURE compare_tables(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    ) IS
        v_ddl CLOB;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 76, '='));
        DBMS_OUTPUT.PUT_LINE('Сравнение таблиц (через schema_compare_pkg.compare_schemas)');
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 76, '='));

        schema_compare_pkg.compare_schemas(
            p_dev_schema  => p_dev_schema,
            p_prod_schema => p_prod_schema,
            p_ddl_script  => v_ddl
        );
        print_clob(v_ddl);
    END compare_tables;

    PROCEDURE compare_all_objects(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    ) IS
        v_ddl CLOB;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 76, '='));
        DBMS_OUTPUT.PUT_LINE('Сравнение всех объектов (через schema_compare_pkg.compare_schemas)');
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 76, '='));

        schema_compare_pkg.compare_schemas(
            p_dev_schema  => p_dev_schema,
            p_prod_schema => p_prod_schema,
            p_ddl_script  => v_ddl
        );
        print_clob(v_ddl);
    END compare_all_objects;

    PROCEDURE generate_sync_ddl(
        p_dev_schema  IN VARCHAR2,
        p_prod_schema IN VARCHAR2
    ) IS
        v_ddl CLOB;
    BEGIN
        schema_compare_pkg.compare_schemas(
            p_dev_schema  => p_dev_schema,
            p_prod_schema => p_prod_schema,
            p_ddl_script  => v_ddl
        );
        print_clob(v_ddl);
    END generate_sync_ddl;
END pkg_schema_compare;
/

