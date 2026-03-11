
import socket
import threading
import time
import logging
from collections import defaultdict


HOST = "127.0.0.1"
PORT = 9999

MAX_TOTAL_CONNECTIONS  = 10    
MAX_CONN_PER_IP        = 3     
MAX_NEW_CONN_PER_SEC   = 5     
SOCKET_TIMEOUT         = 15.0  

# Прикладной уровень
MAX_REQUEST_SIZE       = 1024  
MAX_AUTH_ATTEMPTS      = 3     
MAX_REQUESTS_PER_MIN   = 20    

VALID_USERS = {
    "admin": "secret123",
    "user":  "qwerty",
}


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("server")


lock = threading.Lock()

active_connections: dict[str, int] = defaultdict(int)   
total_connections  = 0

new_conn_timestamps: dict[str, list] = defaultdict(list)

blacklist: dict[str, float] = {}

auth_failures: dict[str, int] = defaultdict(int)

request_timestamps: dict[str, list] = defaultdict(list)



def is_banned(ip: str) -> bool:
    with lock:
        if ip in blacklist:
            if time.time() < blacklist[ip]:
                return True
            else:
                del blacklist[ip]
                log.info(f"[UNBAN] {ip} разбанен")
    return False


def ban_ip(ip: str, duration: float = 60.0, reason: str = ""):
    with lock:
        blacklist[ip] = time.time() + duration
    log.warning(f"[BAN] {ip} заблокирован на {duration:.0f}с. Причина: {reason}")


def check_tcp_rate_limit(ip: str) -> bool:
    now = time.time()
    with lock:
        new_conn_timestamps[ip] = [
            t for t in new_conn_timestamps[ip] if now - t < 1.0
        ]
        if len(new_conn_timestamps[ip]) >= MAX_NEW_CONN_PER_SEC:
            return False
        new_conn_timestamps[ip].append(now)
    return True


def check_request_rate_limit(ip: str) -> bool:
    now = time.time()
    with lock:
        request_timestamps[ip] = [
            t for t in request_timestamps[ip] if now - t < 60.0
        ]
        if len(request_timestamps[ip]) >= MAX_REQUESTS_PER_MIN:
            return False
        request_timestamps[ip].append(now)
    return True


def register_connection(ip: str) -> bool:
    global total_connections
    with lock:
        if total_connections >= MAX_TOTAL_CONNECTIONS:
            return False
        if active_connections[ip] >= MAX_CONN_PER_IP:
            return False
        active_connections[ip] += 1
        total_connections += 1
    return True


def unregister_connection(ip: str):
    global total_connections
    with lock:
        if active_connections[ip] > 0:
            active_connections[ip] -= 1
        if total_connections > 0:
            total_connections -= 1



ALLOWED_COMMANDS = {"PING", "ECHO", "TIME", "QUIT", "LOGIN", "HELP"}


def handle_client(conn: socket.socket, addr):
    ip, port = addr
    log.info(f"[CONNECT] {ip}:{port}")
    conn.settimeout(SOCKET_TIMEOUT)

    authenticated = False
    username = None

    try:
        conn.sendall(b"220 SecureServer ready. Send LOGIN <user> <pass> to authenticate.\r\n")

        while True:
            try:
                data = conn.recv(MAX_REQUEST_SIZE + 1)
            except socket.timeout:
                conn.sendall(b"421 Timeout. Goodbye.\r\n")
                log.warning(f"[TIMEOUT] {ip}:{port}")
                break

            if not data:
                break

            if len(data) > MAX_REQUEST_SIZE:
                conn.sendall(b"400 Request too large.\r\n")
                log.warning(f"[OVERSIZED] {ip}:{port} прислал {len(data)} байт")
                ban_ip(ip, duration=30, reason="oversized request")
                break

            if not check_request_rate_limit(ip):
                conn.sendall(b"429 Too Many Requests. Slow down.\r\n")
                log.warning(f"[RATE] {ip}:{port} превысил лимит запросов")
                ban_ip(ip, duration=30, reason="request rate limit exceeded")
                break

            line = data.decode(errors="replace").strip()
            if not line:
                continue

            parts  = line.split()
            cmd    = parts[0].upper()
            args   = parts[1:]

            if cmd not in ALLOWED_COMMANDS:
                conn.sendall(f"501 Unknown command: {cmd}\r\n".encode())
                log.warning(f"[INVALID CMD] {ip}:{port} → '{cmd}'")
                continue

            if cmd == "LOGIN":
                if len(args) != 2:
                    conn.sendall(b"501 Syntax: LOGIN <user> <pass>\r\n")
                    continue

                user, pwd = args[0], args[1]

                with lock:
                    failures = auth_failures[ip]

                if failures >= MAX_AUTH_ATTEMPTS:
                    conn.sendall(b"403 Too many failed attempts. Banned.\r\n")
                    ban_ip(ip, duration=120, reason="brute force")
                    break

                if VALID_USERS.get(user) == pwd:
                    authenticated = True
                    username = user
                    with lock:
                        auth_failures[ip] = 0
                    conn.sendall(f"200 Welcome, {user}!\r\n".encode())
                    log.info(f"[AUTH OK] {ip}:{port} → user='{user}'")
                else:
                    with lock:
                        auth_failures[ip] += 1
                        remaining = MAX_AUTH_ATTEMPTS - auth_failures[ip]
                    conn.sendall(
                        f"401 Invalid credentials. Attempts left: {remaining}\r\n".encode()
                    )
                    log.warning(f"[AUTH FAIL] {ip}:{port} user='{user}' ({auth_failures[ip]}/{MAX_AUTH_ATTEMPTS})")
                continue

            if not authenticated:
                conn.sendall(b"530 Not authenticated. Use LOGIN first.\r\n")
                continue

            if cmd == "PING":
                conn.sendall(b"200 PONG\r\n")

            elif cmd == "ECHO":
                msg = " ".join(args)
                conn.sendall(f"200 {msg}\r\n".encode())

            elif cmd == "TIME":
                t = time.strftime("%Y-%m-%d %H:%M:%S")
                conn.sendall(f"200 {t}\r\n".encode())

            elif cmd == "HELP":
                conn.sendall(
                    b"200 Commands: LOGIN <user> <pass> | PING | ECHO <msg> | TIME | QUIT | HELP\r\n"
                )

            elif cmd == "QUIT":
                conn.sendall(b"221 Bye.\r\n")
                break

    except ConnectionResetError:
        log.info(f"[RESET] {ip}:{port} сбросил соединение")
    except Exception as e:
        log.error(f"[ERROR] {ip}:{port} → {e}")
    finally:
        conn.close()
        unregister_connection(ip)
        log.info(f"[DISCONNECT] {ip}:{port}")



def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(50)
    log.info(f"Сервер запущен на {HOST}:{PORT}")
    log.info(f"Защиты: макс.соед={MAX_TOTAL_CONNECTIONS}, per-IP={MAX_CONN_PER_IP}, "
             f"rate={MAX_NEW_CONN_PER_SEC}/сек, timeout={SOCKET_TIMEOUT}с, "
             f"max_req={MAX_REQUEST_SIZE}б, auth_attempts={MAX_AUTH_ATTEMPTS}, "
             f"req/min={MAX_REQUESTS_PER_MIN}")

    try:
        while True:
            try:
                conn, addr = server.accept()
            except KeyboardInterrupt:
                break

            ip = addr[0]

            if is_banned(ip):
                log.warning(f"[BANNED] Отклонено соединение от {ip}")
                conn.sendall(b"403 You are banned.\r\n")
                conn.close()
                continue

            if not check_tcp_rate_limit(ip):
                log.warning(f"[TCP RATE] Слишком много соединений от {ip}")
                conn.sendall(b"503 Connection rate limit exceeded.\r\n")
                conn.close()
                ban_ip(ip, duration=30, reason="TCP rate limit")
                continue

            if not register_connection(ip):
                log.warning(
                    f"[LIMIT] Отклонено от {ip} "
                    f"(всего={total_connections}, IP={active_connections[ip]})"
                )
                conn.sendall(b"503 Connection limit reached.\r\n")
                conn.close()
                continue

            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()

    finally:
        server.close()
        log.info("Сервер остановлен.")


if __name__ == "__main__":
    main()
