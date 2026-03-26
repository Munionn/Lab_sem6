#!/usr/bin/env bash
# ============================================================
# Управление Oracle DB для лабораторных работ по PL/SQL
# ============================================================

set -euo pipefail

CONTAINER="oracle-xe"
DB_USER="labuser"
DB_PASS="labuser"
DB_SERVICE="FREEPDB1"
CONN="${DB_USER}/${DB_PASS}@//${CONTAINER}:1521/${DB_SERVICE}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# Ожидание готовности Oracle
wait_for_oracle() {
    info "Ожидание готовности Oracle (может занять 3-5 минут при первом запуске)..."
    local attempts=0
    local max=40

    while [ $attempts -lt $max ]; do
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "not_found")

        if [ "$health" = "healthy" ]; then
            success "Oracle готов!"
            return 0
        fi

        attempts=$((attempts + 1))
        echo -ne "\r  Попытка $attempts/$max — статус: $health..."
        sleep 10
    done

    echo ""
    error "Oracle не стал healthy за отведённое время. Проверьте: docker logs $CONTAINER"
}

# Выполнение SQL через sqlplus внутри контейнера
run_sql() {
    local label="$1"
    local sql_file="$2"

    info "Запускаю ${label}..."

    docker exec -i "$CONTAINER" sqlplus -S "$CONN" <<SQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON
SET ECHO ON
SET LINESIZE 200
SET PAGESIZE 50000
SET TRIMOUT ON
SET TRIMSPOOL ON
WHENEVER SQLERROR CONTINUE
@/labs/${sql_file}
EXIT
SQL

    success "${label} выполнен."
}

# Команды
cmd_start() {
    info "Запуск Oracle DB..."
    docker compose up -d
    wait_for_oracle
    echo ""
    success "Oracle запущен."
    echo ""
    echo "  Подключение: ./run.sh connect"
    echo "  Запуск лаб:  ./run.sh lab1 / lab2 / lab3"
}

cmd_stop() {
    info "Остановка Oracle DB..."
    docker compose stop
    success "Oracle остановлен (данные сохранены)."
}

cmd_down() {
    warn "Удаление контейнера и всех данных..."
    read -rp "Вы уверены? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker compose down -v
        success "Контейнер и volumes удалены."
    else
        info "Отменено."
    fi
}

cmd_status() {
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "не запущен")
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "—")
    echo ""
    echo "  Контейнер : $CONTAINER"
    echo "  Состояние : $state"
    echo "  Health    : $health"
    echo "  Порт      : 1521"
    echo "  Пользов.  : $DB_USER / $DB_PASS"
    echo "  Сервис    : $DB_SERVICE"
    echo ""
}

cmd_connect() {
    info "Открываю sqlplus сессию (labuser@FREEPDB1)..."
    echo "  Введите SQL или PL/SQL. Для выхода: EXIT"
    echo ""
    docker exec -it "$CONTAINER" sqlplus "$CONN"
}

cmd_connect_sys() {
    info "Открываю sqlplus сессию (SYSTEM)..."
    docker exec -it "$CONTAINER" sqlplus "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1"
}

cmd_lab1() {
    run_sql "Лабораторная работа 1" "lab1.sql"
}

cmd_lab2() {
    run_sql "Лабораторная работа 2" "lab2.sql"
}

cmd_all() {
    info "Запуск всех лабораторных: lab1 → lab2 → lab3"
    cmd_lab1
    echo ""
    cmd_lab2
    echo ""
    cmd_lab3
    echo ""
    success "Все лабораторные выполнены."
}

cmd_lab3() {
    warn "Для lab3 нужны две схемы (DEV и PROD)."

    # Схемы пересоздаём только если DEV_SCHEMA ещё нет (после применения DDL не трогаем)
    local need_setup
    need_setup=$(docker exec "$CONTAINER" sqlplus -S "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM all_users WHERE username = 'DEV_SCHEMA';
EXIT
SQL
)
    need_setup=$(echo "$need_setup" | tr -d '[:space:]')
    if [ "$need_setup" = "0" ] || [ -z "$need_setup" ]; then
        info "Создаю схему DEV_SCHEMA и PROD_SCHEMA с тестовыми данными..."
        docker exec -i "$CONTAINER" sqlplus -S "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1" <<'SQL'
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE
BEGIN EXECUTE IMMEDIATE 'DROP USER dev_schema CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP USER prod_schema CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER dev_schema  IDENTIFIED BY dev123  DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
CREATE USER prod_schema IDENTIFIED BY prod123 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW TO dev_schema;
GRANT CONNECT, RESOURCE, CREATE VIEW TO prod_schema;
GRANT SELECT ANY TABLE TO labuser;
GRANT SELECT ANY DICTIONARY TO labuser;
CREATE TABLE dev_schema.products ( id NUMBER PRIMARY KEY, name VARCHAR2(100) NOT NULL, price NUMBER(10,2), category VARCHAR2(50) );
CREATE TABLE prod_schema.products ( id NUMBER PRIMARY KEY, name VARCHAR2(100) NOT NULL, price NUMBER(10,2) );
CREATE TABLE dev_schema.orders ( id NUMBER PRIMARY KEY, product_id NUMBER, quantity NUMBER, CONSTRAINT fk_orders_prod FOREIGN KEY (product_id) REFERENCES dev_schema.products(id) );
CREATE TABLE prod_schema.legacy_log ( id NUMBER PRIMARY KEY, message VARCHAR2(500) );
CREATE OR REPLACE PROCEDURE dev_schema.get_product(p_id IN NUMBER) IS BEGIN NULL; END;
/
EXIT
SQL
    else
        info "Схемы DEV_SCHEMA и PROD_SCHEMA уже есть — создание пропущено (применённый DDL сохраняется)."
    fi

    run_sql "Лабораторная работа 3" "lab3.sql"
}

# Только сгенерировать отчёт и DDL (схемы не пересоздаются)
cmd_lab3_gen() {
    info "Генерация сравнения и DDL (lab3.sql без пересоздания схем)..."
    run_sql "Лабораторная работа 3 (только генерация)" "lab3.sql"
}

# Сгенерировать DDL, применить к PROD, затем показать только сравнение (без вывода DDL в консоль)
cmd_lab3_sync() {
    local outfile="sync_auto.sql"
    info "Генерирую DDL (вывод не показываю)..."
    docker exec -i "$CONTAINER" sqlplus -S "$CONN" <<'SQL' > "/tmp/lab3_full_$$.txt" 2>&1
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK OFF
SET ECHO OFF
WHENEVER SQLERROR CONTINUE
@/labs/lab3.sql
EXIT
SQL
    sed -n '/-- ---- ТАБЛИЦЫ ----/,/-- Конец DDL-скрипта синхронизации/p' "/tmp/lab3_full_$$.txt" > "$outfile"
    rm -f "/tmp/lab3_full_$$.txt"
    if [ ! -s "$outfile" ]; then
        warn "DDL-блок не найден в выводе (схемы уже синхронны?). Показываю сравнение:"
        docker exec -i "$CONTAINER" sqlplus -S "$CONN" <<'SQL'
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
@/labs/lab3_compare_only.sql
EXIT
SQL
        return
    fi
    info "Применяю DDL к PROD_SCHEMA..."
    docker exec -i "$CONTAINER" sqlplus -S "prod_schema/prod123@//localhost:1521/FREEPDB1" <<SQL
SET DEFINE OFF
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE
@/labs/$outfile
EXIT
SQL
    success "DDL применён."
    info "Проверка сравнения (без вывода DDL):"
    docker exec -i "$CONTAINER" sqlplus -S "$CONN" <<'SQL'
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
@/labs/lab3_compare_only.sql
EXIT
SQL
    success "Готово."
}

# Применить DDL-скрипт к PROD (подключение от prod_schema)
# Файл должен быть в каталоге lab1-3 (монтируется в контейнер как /labs)
cmd_lab3_apply() {
    local ddl_file="${1:-}"
    if [ -z "$ddl_file" ]; then
        error "Укажите файл с DDL: ./run.sh lab3-apply <файл.sql>"
    fi
    if [ ! -f "$ddl_file" ]; then
        error "Файл не найден: $ddl_file"
    fi
    info "Применяю DDL к PROD_SCHEMA: $ddl_file"
    docker exec -i "$CONTAINER" sqlplus -S "prod_schema/prod123@//localhost:1521/FREEPDB1" <<SQL
SET DEFINE OFF
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE
@/labs/$ddl_file
EXIT
SQL
    success "DDL применён (проверьте вывод на ошибки)."
}

cmd_reset() {
    warn "Сброс данных лабораторных (пересоздание пользователя labuser)..."
    read -rp "Вы уверены? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker exec -i "$CONTAINER" sqlplus -S "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1" <<SQL
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE
BEGIN
    FOR s IN (SELECT sid, serial# FROM v\$session WHERE username = 'LABUSER') LOOP
        EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    END LOOP;
END;
/
DROP USER labuser CASCADE;
CREATE USER labuser IDENTIFIED BY labuser DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE TABLE, CREATE PROCEDURE, CREATE SEQUENCE,
      CREATE TRIGGER, CREATE VIEW TO labuser;
EXIT
SQL
        success "Пользователь labuser пересоздан. Можно запускать лабы заново."
    else
        info "Отменено."
    fi
}

cmd_logs() {
    docker logs -f "$CONTAINER"
}

cmd_help() {
    echo ""
    echo "  Использование: ./run.sh <команда>"
    echo ""
    echo "  Управление контейнером:"
    echo "    start      — запустить Oracle (с ожиданием готовности)"
    echo "    stop       — остановить (данные сохраняются)"
    echo "    down       — удалить контейнер и все данные"
    echo "    status     — показать статус"
    echo "    logs       — показать логи контейнера"
    echo ""
    echo "  Подключение:"
    echo "    connect    — открыть sqlplus (labuser)"
    echo "    connect-sys — открыть sqlplus (SYSTEM)"
    echo ""
  echo "  Запуск лабораторных:"
  echo "    lab1         — выполнить lab1.sql"
  echo "    lab2         — выполнить lab2.sql"
  echo "    lab3         — создать схемы DEV/PROD (если нет) и выполнить lab3.sql"
  echo "    lab3-gen     — только сгенерировать сравнение и DDL (схемы не трогать)"
  echo "    lab3-apply F — применить DDL-файл F к PROD (подключение prod_schema)"
  echo "    lab3-sync    — сгенерировать DDL, применить к PROD, показать только сравнение (DDL не выводится)"
  echo "    all          — выполнить lab1, lab2 и lab3 подряд"
  echo ""
  echo "  Пример: ./run.sh lab3-sync   — применить сгенерированный DDL и перепроверить без вывода DDL"
  echo "          ./run.sh lab3-apply sync.sql  — применить свой файл"
  echo ""
    echo "  Утилиты:"
    echo "    reset      — удалить всё из labuser и начать заново"
    echo ""
    echo "  DBeaver (GUI):"
    echo "    Host: localhost | Port: 1521 | Service: FREEPDB1"
    echo "    User: labuser   | Password: labuser"
    echo ""
}

# ============================================================
# Диспетчер команд
# ============================================================
case "${1:-help}" in
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    down)        cmd_down ;;
    status)      cmd_status ;;
    connect)     cmd_connect ;;
    connect-sys) cmd_connect_sys ;;
    lab1)        cmd_lab1 ;;
    lab2)        cmd_lab2 ;;
    lab3)        cmd_lab3 ;;
    lab3-gen)    cmd_lab3_gen ;;
    lab3-apply)  cmd_lab3_apply "$2" ;;
    lab3-sync)   cmd_lab3_sync ;;
    all)         cmd_all ;;
    reset)       cmd_reset ;;
    logs)        cmd_logs ;;
    help|--help|-h) cmd_help ;;
    *) error "Неизвестная команда: ${1}. Используй ./run.sh help" ;;
esac
