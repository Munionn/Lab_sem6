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

cmd_lab3() {
    warn "Для lab3 нужны две схемы (DEV и PROD)."
    info "Создаю схему DEV_SCHEMA и PROD_SCHEMA..."

    docker exec -i "$CONTAINER" sqlplus -S "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1" <<SQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

-- Создаём пользователей как схемы (в Oracle схема = пользователь)
BEGIN
    EXECUTE IMMEDIATE 'DROP USER dev_schema CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER prod_schema CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE USER dev_schema  IDENTIFIED BY dev123  DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
CREATE USER prod_schema IDENTIFIED BY prod123 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW TO dev_schema;
GRANT CONNECT, RESOURCE, CREATE VIEW TO prod_schema;

-- Даём labuser права видеть ALL_TABLES/ALL_OBJECTS обоих схем
GRANT SELECT ANY TABLE TO labuser;
GRANT SELECT ANY DICTIONARY TO labuser;

EXIT
SQL

    run_sql "Лабораторная работа 3" "lab3.sql"

    info "Тестовый вызов compare_schemas('DEV_SCHEMA', 'PROD_SCHEMA'):"
    docker exec -i "$CONTAINER" sqlplus -S "$CONN" <<SQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
BEGIN
    compare_schemas('DEV_SCHEMA', 'PROD_SCHEMA');
END;
/
EXIT
SQL
}

cmd_reset() {
    warn "Сброс данных лабораторных (пересоздание пользователя labuser)..."
    read -rp "Вы уверены? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker exec -i "$CONTAINER" sqlplus -S "system/MyStrongPassw0rd@//localhost:1521/FREEPDB1" <<SQL
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE
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
    echo "    lab1       — выполнить lab1.sql"
    echo "    lab2       — выполнить lab2.sql"
    echo "    lab3       — создать схемы DEV/PROD и выполнить lab3.sql"
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
    reset)       cmd_reset ;;
    logs)        cmd_logs ;;
    help|--help|-h) cmd_help ;;
    *) error "Неизвестная команда: ${1}. Используй ./run.sh help" ;;
esac
