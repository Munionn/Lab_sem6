-- Только сравнение схем (без вывода DDL).
-- Процедуры compare_schemas и compare_schemas_extended должны быть созданы (запустите lab3.sql один раз).
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    compare_schemas('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/

BEGIN
    compare_schemas_extended('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/
