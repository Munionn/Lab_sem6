"""
Лабораторная работа 6.
Симулятор SQL-инъекций против защищённого сервера.

Запускать ПОСЛЕ server.py.

Атаки:
     1 — Auth bypass (OR '1'='1')
     2 — Comment bypass (admin'--)
     3 — UNION: дамп таблицы пользователей
     4 — Tautology через GETUSER (1 OR 1=1)
     5 — Boolean-blind через SEARCH
     6 — Wildcard abuse через SEARCH (%)
     7 — Stacked queries (DROP TABLE)
     8 — Error-based через GETUSER
     9 — Second-order: регистрация с вредоносным именем
    10 — Mass register flood (спам регистрацией)
    11 — Все атаки по очереди
"""

import socket

HOST = "127.0.0.1"
PORT = 9997

SEP = "=" * 58


def connect() -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((HOST, PORT))
    banner = s.recv(2048).decode(errors="replace").strip()
    print(f"  Сервер: {banner}")
    return s


def cmd(s: socket.socket, line: str) -> str:
    try:
        s.sendall((line + "\r\n").encode())
        return s.recv(2048).decode(errors="replace").strip()
    except Exception as e:
        return f"[ERROR] {e}"


def show(label: str, payload: str, resp: str):
    blocked = resp.startswith(("400", "401", "403", "404", "501"))
    status  = "BLOCKED" if blocked else "PASSED"
    print(f"  [{status}] {label}")
    print(f"           payload → {payload!r}")
    print(f"           ответ   → {resp}")


# ---------------------------------------------------------------------------
# Атака 1: Auth bypass — OR '1'='1'
# ---------------------------------------------------------------------------

def attack_1_auth_bypass():
    print(f"\n{SEP}")
    print("  АТАКА 1: Auth bypass (OR '1'='1')")
    print(SEP)
    s = connect()
    payloads = [
        ("' OR '1'='1", "anything"),
        ("' OR 1=1--",  "x"),
        ("admin'--",    "wrong"),
    ]
    for user, pwd in payloads:
        resp = cmd(s, f"LOGIN {user} {pwd}")
        show(f"LOGIN {user!r} {pwd!r}", f"{user} / {pwd}", resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 2: Comment bypass — admin'--
# ---------------------------------------------------------------------------

def attack_2_comment_bypass():
    print(f"\n{SEP}")
    print("  АТАКА 2: Comment bypass (admin'--)")
    print(SEP)
    s = connect()
    variants = [
        "admin'--",
        "admin'#",
        "admin'/*",
        "admin' --",
    ]
    for user in variants:
        resp = cmd(s, f"LOGIN {user} ANYTHING")
        show(f"LOGIN {user!r}", user, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 3: UNION-based — дамп пользователей через SEARCH
# ---------------------------------------------------------------------------

def attack_3_union():
    print(f"\n{SEP}")
    print("  АТАКА 3: UNION-based — дамп таблицы users через SEARCH")
    print(SEP)
    s = connect()
    payloads = [
        "' UNION SELECT id,username,password,role FROM users--",
        "x' UNION SELECT 1,username,password,role FROM users--",
        "' UNION SELECT 1,2,3,4--",
    ]
    for p in payloads:
        resp = cmd(s, f"SEARCH {p}")
        show("SEARCH UNION", p, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 4: Tautology через GETUSER
# ---------------------------------------------------------------------------

def attack_4_tautology():
    print(f"\n{SEP}")
    print("  АТАКА 4: Tautology через GETUSER (1 OR 1=1)")
    print(SEP)
    s = connect()

    # Сначала авторизуемся как admin, чтобы GETUSER был доступен
    resp = cmd(s, "LOGIN admin secret123")
    print(f"  LOGIN admin: {resp}")

    payloads = [
        "1 OR 1=1",
        "1; SELECT * FROM users",
        "0 UNION SELECT 1,username,password,role FROM users",
        "-1 OR id>0",
    ]
    for p in payloads:
        resp = cmd(s, f"GETUSER {p}")
        show(f"GETUSER {p!r}", p, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 5: Boolean-blind через SEARCH
# ---------------------------------------------------------------------------

def attack_5_boolean_blind():
    print(f"\n{SEP}")
    print("  АТАКА 5: Boolean-blind injection через SEARCH")
    print(SEP)
    s = connect()

    # Попытка угадать первый символ пароля admin через boolean-blind
    print("  Пробуем SEARCH с подзапросом вида:")
    print("  ' AND (SELECT SUBSTR(password,1,1) FROM users WHERE username='admin')='s'--")

    payloads = [
        f"' AND (SELECT SUBSTR(password,1,1) FROM users WHERE username='admin')='{ch}'--"
        for ch in "abcdefghijklmnopqrs"
    ]
    found = None
    for p in payloads[:5]:   # показываем первые 5 попыток
        resp = cmd(s, f"SEARCH {p}")
        is_true = resp.startswith("200")
        print(f"  char='{p[-3]}': {'ИСТИНА (нашли символ!)' if is_true else 'ложь'} → {resp[:50]}")
        if is_true:
            found = p[-3]

    print(f"\n  Результат: {'угадан символ ' + found if found else 'сервер заблокировал все попытки'}")
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 6: Wildcard abuse через SEARCH
# ---------------------------------------------------------------------------

def attack_6_wildcard():
    print(f"\n{SEP}")
    print("  АТАКА 6: Wildcard abuse через SEARCH (%)")
    print(SEP)
    s = connect()
    payloads = [
        "%",
        "%%",
        "%a%",
        "_",
        "% OR 1=1",
    ]
    for p in payloads:
        resp = cmd(s, f"SEARCH {p}")
        show(f"SEARCH {p!r}", p, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 7: Stacked queries (DROP TABLE)
# ---------------------------------------------------------------------------

def attack_7_stacked():
    print(f"\n{SEP}")
    print("  АТАКА 7: Stacked queries (DROP TABLE через LOGIN)")
    print(SEP)
    s = connect()
    payloads = [
        ("'; DROP TABLE users;--",          "x"),
        ("'; DELETE FROM users;--",         "x"),
        ("'; UPDATE users SET role='admin'--", "x"),
        ("'; INSERT INTO users VALUES(99,'hacker','hack','admin');--", "x"),
    ]
    for user, pwd in payloads:
        resp = cmd(s, f"LOGIN {user} {pwd}")
        show("LOGIN stacked", user, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 8: Error-based через GETUSER
# ---------------------------------------------------------------------------

def attack_8_error_based():
    print(f"\n{SEP}")
    print("  АТАКА 8: Error-based injection через GETUSER")
    print(SEP)
    s = connect()
    resp = cmd(s, "LOGIN admin secret123")
    print(f"  LOGIN admin: {resp}")

    payloads = [
        "1 AND 1=CAST((SELECT password FROM users WHERE username='admin') AS INTEGER)",
        "1 AND 1=(SELECT 1/0)",
        "(SELECT COUNT(*) FROM users)",
        "1 AND (SELECT username FROM users LIMIT 1)>0",
    ]
    for p in payloads:
        resp = cmd(s, f"GETUSER {p}")
        show("GETUSER error-based", p, resp)
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 9: Second-order injection через REGISTER
# ---------------------------------------------------------------------------

def attack_9_second_order():
    print(f"\n{SEP}")
    print("  АТАКА 9: Second-order injection через REGISTER")
    print(SEP)
    s = connect()

    # Регистрируем пользователя с вредоносным именем
    evil_names = [
        "admin'--",
        "' OR '1'='1",
        "hacker'; DROP TABLE users;--",
        "'; UPDATE users SET role='admin' WHERE username='alice';--",
    ]

    for name in evil_names:
        resp = cmd(s, f"REGISTER {name} password123")
        show("REGISTER evil name", name, resp)

    # Пробуем залогиниться под сохранённым именем
    resp = cmd(s, "LOGIN admin'-- password123")
    show("LOGIN с сохранённым именем", "admin'--", resp)

    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Атака 10: Mass register flood
# ---------------------------------------------------------------------------

def attack_10_flood():
    print(f"\n{SEP}")
    print("  АТАКА 10: Mass register flood (спам регистрацией)")
    print(SEP)
    s = connect()
    print("  Регистрируем 15 пользователей подряд...")
    for i in range(15):
        resp = cmd(s, f"REGISTER user{i} pass{i}")
        label = "OK" if resp.startswith("200") else "BLOCKED/ERROR"
        print(f"  [{label}] REGISTER user{i} → {resp[:50]}")
    cmd(s, "QUIT")
    s.close()


# ---------------------------------------------------------------------------
# Меню
# ---------------------------------------------------------------------------

ATTACKS = {
    "1":  ("Auth bypass (OR '1'='1')",             attack_1_auth_bypass),
    "2":  ("Comment bypass (admin'--)",            attack_2_comment_bypass),
    "3":  ("UNION: дамп users",                    attack_3_union),
    "4":  ("Tautology (GETUSER 1 OR 1=1)",         attack_4_tautology),
    "5":  ("Boolean-blind (SEARCH)",               attack_5_boolean_blind),
    "6":  ("Wildcard abuse (%)",                   attack_6_wildcard),
    "7":  ("Stacked queries (DROP TABLE)",         attack_7_stacked),
    "8":  ("Error-based (GETUSER)",                attack_8_error_based),
    "9":  ("Second-order (REGISTER evil name)",    attack_9_second_order),
    "10": ("Mass register flood",                  attack_10_flood),
}


def main():
    print(SEP)
    print("  Симулятор SQL-атак — Лабораторная работа 6")
    print(SEP)
    print("Выберите атаку:")
    for k, (name, _) in ATTACKS.items():
        print(f"  {k:>2} — {name}")
    print("  11 — Все атаки по очереди")

    choice = input("\nВаш выбор: ").strip()

    if choice == "11":
        for _, fn in ATTACKS.values():
            fn()
    elif choice in ATTACKS:
        ATTACKS[choice][1]()
    else:
        print("Неверный выбор.")


if __name__ == "__main__":
    main()
