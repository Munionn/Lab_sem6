"""
Лабораторная работа 6.
Защищённый сервер с защитой от SQL-инъекций.

Протокол (текстовый, CRLF):
    LOGIN <user> <pass>    — авторизация
    SEARCH <name>          — поиск товара по имени
    GETUSER <id>           — получить пользователя по ID
    REGISTER <user> <pass> — регистрация нового пользователя
    LIST                   — список всех товаров
    QUIT                   — завершить соединение

Защиты:
    1. Параметризованные запросы (никакой конкатенации строк)
    2. Валидация типов (ID — только целое число)
    3. Ограничение длины входных данных
    4. Белый список допустимых команд
    5. Обработка исключений БД без раскрытия деталей
    6. Ограничение прав: только admin может использовать GETUSER
"""

import socket
import threading
import sqlite3
import logging

HOST = "127.0.0.1"
PORT = 9997

MAX_INPUT_LEN  = 256
SOCKET_TIMEOUT = 30.0

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("server6")

ALLOWED_COMMANDS = {"LOGIN", "SEARCH", "GETUSER", "REGISTER", "LIST", "QUIT"}

# ---------------------------------------------------------------------------
# База данных (одна на сервер, thread-safe через check_same_thread=False)
# ---------------------------------------------------------------------------

def init_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.executescript("""
        CREATE TABLE users (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            role     TEXT DEFAULT 'user'
        );
        CREATE TABLE products (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            price REAL,
            stock INTEGER
        );
        INSERT INTO users (username, password, role) VALUES ('admin', 'secret123', 'admin');
        INSERT INTO users (username, password, role) VALUES ('alice', 'pass456',   'user');
        INSERT INTO users (username, password, role) VALUES ('bob',   'qwerty',    'user');
        INSERT INTO products VALUES (1, 'Laptop', 999.99, 10);
        INSERT INTO products VALUES (2, 'Phone',  499.99, 25);
        INSERT INTO products VALUES (3, 'Tablet', 299.99, 15);
    """)
    conn.commit()
    return conn


DB_LOCK = threading.Lock()
DB: sqlite3.Connection = None


# ---------------------------------------------------------------------------
# Защищённые запросы к БД
# ---------------------------------------------------------------------------

def db_login(username: str, password: str):
    """Параметризованный запрос авторизации."""
    with DB_LOCK:
        row = DB.execute(
            "SELECT id, username, role FROM users WHERE username=? AND password=?",
            (username, password)
        ).fetchone()
    return dict(row) if row else None


def db_search(name: str):
    """Параметризованный поиск товара."""
    with DB_LOCK:
        rows = DB.execute(
            "SELECT id, name, price, stock FROM products WHERE name LIKE ?",
            (f"%{name}%",)
        ).fetchall()
    return [dict(r) for r in rows]


def db_get_user(user_id: str):
    """Параметризованный запрос пользователя по ID с валидацией типа."""
    try:
        uid = int(user_id)
    except ValueError:
        return None, "Invalid ID format"
    with DB_LOCK:
        row = DB.execute(
            "SELECT id, username, role FROM users WHERE id=?",
            (uid,)
        ).fetchone()
    return (dict(row) if row else None), None


def db_register(username: str, password: str):
    """Параметризованная регистрация пользователя."""
    if not username or not password:
        return False, "Username and password required"
    if len(username) > 32 or len(password) > 64:
        return False, "Username/password too long"
    try:
        with DB_LOCK:
            DB.execute(
                "INSERT INTO users (username, password, role) VALUES (?, ?, 'user')",
                (username, password)
            )
            DB.commit()
        return True, "Registered"
    except sqlite3.IntegrityError:
        return False, "Username already exists"


def db_list_products():
    with DB_LOCK:
        rows = DB.execute("SELECT id, name, price, stock FROM products").fetchall()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Обработчик клиента
# ---------------------------------------------------------------------------

def handle_client(conn: socket.socket, addr):
    ip, port = addr
    log.info(f"[CONNECT] {ip}:{port}")
    conn.settimeout(SOCKET_TIMEOUT)
    session_user = None
    session_role = None

    try:
        conn.sendall(b"220 SQLSecureServer. Commands: LOGIN SEARCH GETUSER REGISTER LIST QUIT\r\n")

        while True:
            try:
                raw = conn.recv(MAX_INPUT_LEN + 1)
            except socket.timeout:
                conn.sendall(b"421 Timeout.\r\n")
                break

            if not raw:
                break

            # Защита: ограничение длины пакета
            if len(raw) > MAX_INPUT_LEN:
                conn.sendall(b"400 Input too long.\r\n")
                log.warning(f"[LONG INPUT] {ip}:{port} — {len(raw)} б")
                break

            line = raw.decode(errors="replace").strip()
            if not line:
                continue

            parts = line.split(None, 2)
            cmd   = parts[0].upper()

            # Белый список команд
            if cmd not in ALLOWED_COMMANDS:
                conn.sendall(f"501 Unknown: {cmd}\r\n".encode())
                continue

            # --- LOGIN ---
            if cmd == "LOGIN":
                if len(parts) < 3:
                    conn.sendall(b"501 Syntax: LOGIN <user> <pass>\r\n")
                    continue
                user, pwd = parts[1], parts[2]
                result = db_login(user, pwd)
                if result:
                    session_user = result["username"]
                    session_role = result["role"]
                    conn.sendall(f"200 Welcome {session_user} [{session_role}]\r\n".encode())
                    log.info(f"[AUTH OK] {ip}:{port} → {session_user}")
                else:
                    conn.sendall(b"401 Invalid credentials.\r\n")
                    log.warning(f"[AUTH FAIL] {ip}:{port} user={parts[1]!r}")

            # --- REGISTER ---
            elif cmd == "REGISTER":
                if len(parts) < 3:
                    conn.sendall(b"501 Syntax: REGISTER <user> <pass>\r\n")
                    continue
                ok, msg = db_register(parts[1], parts[2])
                code = "200" if ok else "400"
                conn.sendall(f"{code} {msg}\r\n".encode())

            # --- SEARCH ---
            elif cmd == "SEARCH":
                if len(parts) < 2:
                    conn.sendall(b"501 Syntax: SEARCH <name>\r\n")
                    continue
                results = db_search(parts[1])
                if results:
                    lines = "; ".join(
                        f"{r['name']} ${r['price']} (stock:{r['stock']})" for r in results
                    )
                    conn.sendall(f"200 {lines}\r\n".encode())
                else:
                    conn.sendall(b"404 No products found.\r\n")

            # --- GETUSER (только admin) ---
            elif cmd == "GETUSER":
                if session_role != "admin":
                    conn.sendall(b"403 Admin only.\r\n")
                    continue
                if len(parts) < 2:
                    conn.sendall(b"501 Syntax: GETUSER <id>\r\n")
                    continue
                user_data, err = db_get_user(parts[1])
                if err:
                    conn.sendall(f"400 {err}\r\n".encode())
                elif user_data:
                    conn.sendall(
                        f"200 id={user_data['id']} user={user_data['username']} role={user_data['role']}\r\n".encode()
                    )
                else:
                    conn.sendall(b"404 User not found.\r\n")

            # --- LIST ---
            elif cmd == "LIST":
                products = db_list_products()
                lines = "; ".join(f"{p['name']} ${p['price']}" for p in products)
                conn.sendall(f"200 {lines}\r\n".encode())

            # --- QUIT ---
            elif cmd == "QUIT":
                conn.sendall(b"221 Bye.\r\n")
                break

    except ConnectionResetError:
        log.info(f"[RESET] {ip}:{port}")
    except Exception as e:
        log.error(f"[ERROR] {ip}:{port} → {e}")
    finally:
        conn.close()
        log.info(f"[DISCONNECT] {ip}:{port}")


# ---------------------------------------------------------------------------
# Основной цикл
# ---------------------------------------------------------------------------

def main():
    global DB
    DB = init_db()
    log.info("База данных инициализирована.")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(10)
    log.info(f"Сервер запущен на {HOST}:{PORT}")

    try:
        while True:
            try:
                conn, addr = server.accept()
            except KeyboardInterrupt:
                break
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    finally:
        server.close()
        DB.close()
        log.info("Сервер остановлен.")


if __name__ == "__main__":
    main()
