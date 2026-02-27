"""
Лабораторная работа 6.
Защита от атаки методом внедрения SQL-кода (SQL Injection).

Демонстрирует 10 видов SQL-инъекций на уязвимых запросах
и показывает, как параметризованные запросы нейтрализуют каждую из них.

База данных: SQLite (в памяти), создаётся при запуске.
"""

import sqlite3
import time

# ---------------------------------------------------------------------------
# Создание и заполнение базы данных
# ---------------------------------------------------------------------------

def create_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.executescript("""
        CREATE TABLE users (
            id       INTEGER PRIMARY KEY,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            role     TEXT DEFAULT 'user',
            email    TEXT
        );

        CREATE TABLE products (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            price REAL,
            stock INTEGER
        );

        CREATE TABLE orders (
            id      INTEGER PRIMARY KEY,
            user_id INTEGER,
            product TEXT,
            amount  INTEGER
        );

        INSERT INTO users VALUES (1, 'admin',   'secret123', 'admin', 'admin@corp.com');
        INSERT INTO users VALUES (2, 'alice',   'pass456',   'user',  'alice@mail.com');
        INSERT INTO users VALUES (3, 'bob',     'qwerty',    'user',  'bob@mail.com');
        INSERT INTO users VALUES (4, 'charlie', 'abc',       'user',  'charlie@mail.com');

        INSERT INTO products VALUES (1, 'Laptop',  999.99, 10);
        INSERT INTO products VALUES (2, 'Phone',   499.99, 25);
        INSERT INTO products VALUES (3, 'Tablet',  299.99, 15);

        INSERT INTO orders VALUES (1, 2, 'Laptop', 1);
        INSERT INTO orders VALUES (2, 3, 'Phone',  2);
    """)
    conn.commit()
    return conn


# ---------------------------------------------------------------------------
# Уязвимые функции (конкатенация строк)
# ---------------------------------------------------------------------------

def vuln_login(conn, username: str, password: str):
    query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
    try:
        rows = conn.execute(query).fetchall()
        return query, rows
    except Exception as e:
        return query, f"[DB ERROR] {e}"


def vuln_search(conn, name: str):
    query = f"SELECT * FROM products WHERE name LIKE '%{name}%'"
    try:
        rows = conn.execute(query).fetchall()
        return query, rows
    except Exception as e:
        return query, f"[DB ERROR] {e}"


def vuln_get_user(conn, user_id: str):
    query = f"SELECT * FROM users WHERE id={user_id}"
    try:
        rows = conn.execute(query).fetchall()
        return query, rows
    except Exception as e:
        return query, f"[DB ERROR] {e}"


# ---------------------------------------------------------------------------
# Защищённые функции (параметризованные запросы)
# ---------------------------------------------------------------------------

def safe_login(conn, username: str, password: str):
    query = "SELECT * FROM users WHERE username=? AND password=?"
    rows = conn.execute(query, (username, password)).fetchall()
    return query, rows


def safe_search(conn, name: str):
    query = "SELECT * FROM products WHERE name LIKE ?"
    rows = conn.execute(query, (f"%{name}%",)).fetchall()
    return query, rows


def safe_get_user(conn, user_id: str):
    try:
        uid = int(user_id)
    except ValueError:
        return "SELECT * FROM users WHERE id=?", f"[REJECTED] Некорректный ID: {user_id!r}"
    query = "SELECT * FROM users WHERE id=?"
    rows = conn.execute(query, (uid,)).fetchall()
    return query, rows


# ---------------------------------------------------------------------------
# Форматирование вывода
# ---------------------------------------------------------------------------

SEP  = "=" * 62
SEP2 = "-" * 62

def fmt_rows(rows) -> str:
    if isinstance(rows, str):
        return f"  Результат: {rows}"
    if not rows:
        return "  Результат: (пусто — авторизация отклонена)"
    lines = []
    for r in rows:
        lines.append("  " + dict(r).__str__())
    return "\n".join(lines)


def show_attack(num: int, title: str, payload: str,
                vuln_result, safe_result):
    print(f"\n{SEP}")
    print(f"  АТАКА {num}: {title}")
    print(SEP)
    print(f"  Payload: {payload!r}")

    print(f"\n  [УЯЗВИМЫЙ запрос]")
    print(f"  SQL: {vuln_result[0]}")
    print(fmt_rows(vuln_result[1]))

    print(f"\n  [ЗАЩИЩЁННЫЙ запрос]")
    print(f"  SQL: {safe_result[0]}")
    print(fmt_rows(safe_result[1]))


# ---------------------------------------------------------------------------
# 10 демонстраций SQL-инъекций
# ---------------------------------------------------------------------------

def demo_1_auth_bypass(conn):
    payload = "' OR '1'='1"
    show_attack(1, "Auth bypass (всегда истина)",
                payload,
                vuln_login(conn, payload, "anything"),
                safe_login(conn, payload, "anything"))
    print("\n  Пояснение: уязвимый запрос становится:")
    print("  WHERE username='' OR '1'='1' AND password='anything'")
    print("  → условие истинно для ВСЕХ строк → возвращает всех пользователей!")


def demo_2_comment_bypass(conn):
    payload = "admin'--"
    show_attack(2, "Comment bypass (отсечение пароля через --)",
                payload,
                vuln_login(conn, payload, "wrong_password"),
                safe_login(conn, payload, "wrong_password"))
    print("\n  Пояснение: уязвимый запрос становится:")
    print("  WHERE username='admin'-- AND password='...'")
    print("  → всё после -- закомментировано → проверка пароля исчезает!")


def demo_3_union_extract(conn):
    payload = "' UNION SELECT id,username,password,role,email FROM users--"
    show_attack(3, "UNION-based: извлечение всех паролей",
                payload,
                vuln_search(conn, payload),
                safe_search(conn, payload))
    print("\n  Пояснение: UNION дописывает к результату весь список users,")
    print("  включая логины, пароли и роли — полный дамп таблицы.")


def demo_4_tautology(conn):
    payload = "1 OR 1=1"
    show_attack(4, "Tautology: обход фильтра по ID",
                payload,
                vuln_get_user(conn, payload),
                safe_get_user(conn, payload))
    print("\n  Пояснение: WHERE id=1 OR 1=1 → всегда истинно → дамп всех пользователей.")


def demo_5_boolean_blind(conn):
    """
    Boolean-blind: атакующий не видит данные напрямую,
    но по количеству результатов угадывает символы по одному.
    """
    print(f"\n{SEP}")
    print("  АТАКА 5: Boolean-blind injection (угадывание пароля посимвольно)")
    print(SEP)

    # Имитация: угадываем первый символ пароля пользователя admin
    found = ""
    for ch in "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$":
        payload = f"admin' AND SUBSTR(password,1,1)='{ch}'--"
        query   = f"SELECT * FROM users WHERE username='{payload}' AND password='x'"
        try:
            rows = conn.execute(query).fetchall()
        except Exception:
            rows = []
        if rows:
            found = ch
            break

    print(f"  Принцип: отправляем запросы вида:")
    print(f"  WHERE username='admin' AND SUBSTR(password,1,1)='a'--")
    print(f"  Если строка вернулась — символ угадан. Повторяем для каждого символа.")
    print(f"\n  Угаданный первый символ пароля admin: '{found}'")

    # Защита: параметризованный запрос
    safe_q  = "SELECT * FROM users WHERE username=? AND password=?"
    safe_r  = conn.execute(safe_q, ("admin' AND SUBSTR(password,1,1)='s'--", "x")).fetchall()
    print(f"\n  [ЗАЩИТА] Параметризованный запрос:")
    print(f"  SQL: {safe_q}")
    print(f"  Результат: {'(пусто)' if not safe_r else safe_r}")
    print("  Payload передаётся как литеральная строка — инъекция невозможна.")


def demo_6_time_blind(conn):
    """
    Time-based blind: атакующий измеряет задержку ответа.
    SQLite не поддерживает SLEEP, имитируем тяжёлым запросом.
    """
    print(f"\n{SEP}")
    print("  АТАКА 6: Time-based blind injection (задержка ответа)")
    print(SEP)

    # Имитация задержки через тяжёлый подзапрос
    payload_true  = "1 AND (SELECT COUNT(*) FROM users, products, orders)>0--"
    payload_false = "1 AND (SELECT COUNT(*) FROM users, products, orders)<0--"

    for payload, label in [(payload_true, "условие ИСТИННО"),
                           (payload_false, "условие ЛОЖНО")]:
        query = f"SELECT * FROM users WHERE id={payload}"
        t0 = time.perf_counter()
        try:
            conn.execute(query).fetchall()
        except Exception:
            pass
        elapsed = time.perf_counter() - t0
        print(f"  [{label}] время: {elapsed*1000:.1f} мс  | SQL: {query[:70]}")

    print("\n  Принцип: если условие истинно — запрос тяжёлее → задержка больше.")
    print("  Атакующий угадывает данные, измеряя время ответа.")

    print("\n  [ЗАЩИТА] safe_get_user отклоняет нечисловые ID:")
    _, result = safe_get_user(conn, payload_true)
    print(f"  Результат: {result}")


def demo_7_drop_table(conn):
    """
    Попытка уничтожить таблицу через stacked queries.
    SQLite не поддерживает ; в execute(), но демонстрируем концепцию.
    """
    print(f"\n{SEP}")
    print("  АТАКА 7: Stacked queries — попытка DROP TABLE")
    print(SEP)

    payload = "'; DROP TABLE users;--"
    query   = f"SELECT * FROM users WHERE username='{payload}' AND password='x'"
    print(f"  Payload: {payload!r}")
    print(f"  SQL: {query}")

    try:
        conn.execute(query)
        print("  Результат: [ОПАСНО — запрос выполнен!]")
    except Exception as e:
        print(f"  Результат: [DB ERROR — SQLite заблокировал]: {e}")

    # Проверяем, жива ли таблица
    count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    print(f"  Таблица users: {count} записей (в SQLite stacked queries отключены)")

    print("\n  [ЗАЩИТА] Параметризованный запрос:")
    query_safe = "SELECT * FROM users WHERE username=? AND password=?"
    rows = conn.execute(query_safe, (payload, "x")).fetchall()
    print(f"  Результат: {'(пусто)' if not rows else rows}")
    print("  Payload — просто строка, не SQL. DROP TABLE никогда не выполнится.")


def demo_8_second_order(conn):
    """
    Second-order injection: вредоносный payload сохраняется в БД безопасно,
    но опасно используется при следующем запросе.
    """
    print(f"\n{SEP}")
    print("  АТАКА 8: Second-order injection (отложенная инъекция)")
    print(SEP)

    evil_username = "admin'--"

    print(f"  Шаг 1: Регистрируем пользователя с именем {evil_username!r}")
    print("  (INSERT использует параметризованный запрос — безопасно)")
    conn.execute(
        "INSERT INTO users VALUES (99, ?, 'hacked', 'user', 'evil@mail.com')",
        (evil_username,)
    )
    conn.commit()

    print(f"\n  Шаг 2: Смена пароля — имя пользователя берётся из БД")
    print("  и ВСТАВЛЯЕТСЯ в следующий запрос НЕБЕЗОПАСНО:")

    # Симуляция: читаем имя из БД и вставляем в запрос без параметров
    stored_name = conn.execute(
        "SELECT username FROM users WHERE id=99"
    ).fetchone()[0]

    vuln_query = f"UPDATE users SET password='newpass' WHERE username='{stored_name}'"
    print(f"  SQL: {vuln_query}")
    try:
        conn.execute(vuln_query)
        # Проверяем — изменился ли пароль у admin?
        admin = conn.execute("SELECT password FROM users WHERE username='admin'").fetchone()
        print(f"  Пароль admin после UPDATE: {admin[0]!r}")
        if admin[0] == 'newpass':
            print("  [!!!] Пароль АДМИНИСТРАТОРА изменён через second-order injection!")
    except Exception as e:
        print(f"  [ERROR] {e}")

    # Откатываем
    conn.execute("UPDATE users SET password='secret123' WHERE username='admin'")
    conn.execute("DELETE FROM users WHERE id=99")
    conn.commit()

    print("\n  [ЗАЩИТА] Всегда использовать параметры даже для данных из БД:")
    print("  UPDATE users SET password=? WHERE username=?  →  ('newpass', stored_name)")


def demo_9_wildcard_abuse(conn):
    payload = "%"
    show_attack(9, "Wildcard abuse: дамп всех товаров через %",
                payload,
                vuln_search(conn, payload),
                safe_search(conn, payload))
    print("\n  Пояснение: LIKE '%%' истинно для всех строк — полный дамп таблицы.")
    print("  Защита: параметризация экранирует % как литерал — ищем товар с именем '%'.")


def demo_10_error_based(conn):
    """
    Error-based injection: сообщение об ошибке содержит данные из БД.
    """
    print(f"\n{SEP}")
    print("  АТАКА 10: Error-based injection (утечка данных через ошибку)")
    print(SEP)

    payloads = [
        ("' AND 1=CAST((SELECT password FROM users WHERE username='admin') AS INTEGER)--",
         "пытаемся привести пароль к INTEGER — ошибка раскроет значение"),
        ("' AND 1=(SELECT 1/0)--",
         "деление на ноль — ошибка подтверждает выполнение подзапроса"),
    ]

    for payload, desc in payloads:
        query = f"SELECT * FROM users WHERE username='{payload}' AND password='x'"
        print(f"\n  Payload: {payload!r}")
        print(f"  ({desc})")
        print(f"  SQL: {query[:90]}")
        try:
            rows = conn.execute(query).fetchall()
            print(f"  Результат: {[dict(r) for r in rows]}")
        except Exception as e:
            print(f"  Ошибка (содержит данные!): {e}")

    print("\n  [ЗАЩИТА] Параметризованный запрос:")
    query_s = "SELECT * FROM users WHERE username=? AND password=?"
    rows = conn.execute(query_s, (payloads[0][0], "x")).fetchall()
    print(f"  Результат: {'(пусто — payload как строка, не выполняется)' if not rows else rows}")


# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------

DEMOS = {
    "1":  ("Auth bypass (OR '1'='1')",          demo_1_auth_bypass),
    "2":  ("Comment bypass (admin'--)",          demo_2_comment_bypass),
    "3":  ("UNION: дамп всех паролей",           demo_3_union_extract),
    "4":  ("Tautology (1 OR 1=1)",               demo_4_tautology),
    "5":  ("Boolean-blind (угадывание пароля)",  demo_5_boolean_blind),
    "6":  ("Time-based blind (задержка)",        demo_6_time_blind),
    "7":  ("Stacked queries (DROP TABLE)",       demo_7_drop_table),
    "8":  ("Second-order injection",             demo_8_second_order),
    "9":  ("Wildcard abuse (%)",                 demo_9_wildcard_abuse),
    "10": ("Error-based (утечка через ошибку)",  demo_10_error_based),
}


def main():
    conn = create_db()
    print(SEP)
    print("  Лабораторная работа 6 — SQL Injection")
    print(SEP)
    print("Выберите демонстрацию:")
    for k, (name, _) in DEMOS.items():
        print(f"  {k:>2} — {name}")
    print("  11 — Все демонстрации")

    choice = input("\nВаш выбор: ").strip()

    if choice == "11":
        for _, fn in DEMOS.values():
            fn(conn)
    elif choice in DEMOS:
        DEMOS[choice][1](conn)
    else:
        print("Неверный выбор.")

    conn.close()


if __name__ == "__main__":
    main()
