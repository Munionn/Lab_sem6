SET SERVEROUTPUT ON SIZE UNLIMITED;

BEGIN pkg_schema_compare.compare_tables('DEV_SCHEMA', 'PROD_SCHEMA'); END;
/
BEGIN pkg_schema_compare.compare_all_objects('DEV_SCHEMA', 'PROD_SCHEMA'); END;
/
BEGIN pkg_schema_compare.generate_sync_ddl('DEV_SCHEMA', 'PROD_SCHEMA'); END;
/
