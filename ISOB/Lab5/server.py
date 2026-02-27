"""
Лабораторная работа 5.
Защищённый сервер с защитой от переполнения буфера.

Протокол:
    STORE <данные>   — записать данные в буфер (макс. 16 байт)
    READ             — прочитать содержимое буфера
    STATUS           — показать состояние стека (канарейка, флаг)
    QUIT             — завершить соединение

Защиты:
    1. Ограничение размера принимаемого пакета
    2. Ограничение размера данных для записи в буфер (bounds check)
    3. Stack canary — проверка целостности после каждой записи
    4. Изоляция буфера от служебных данных
    5. Валидация команд (белый список)
    6. Таймаут соединения
"""

import socket
import threading
import struct
import logging

HOST = "127.0.0.1"
PORT = 9998

BUFFER_SIZE   = 16
CANARY_VALUE  = b"\xDE\xAD\xBE\xEF"
MAX_RECV      = 256        # максимум байт в одном сетевом пакете
SOCKET_TIMEOUT = 30.0

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("server5")

ALLOWED_COMMANDS = {"STORE", "READ", "STATUS", "QUIT"}


# ---------------------------------------------------------------------------
# Симулированный защищённый буфер (изолирован от служебных данных)
# ---------------------------------------------------------------------------

class SecureBuffer:
    """
    Защищённый буфер с канарейкой.
    Буфер и служебные данные хранятся ОТДЕЛЬНО — никакой смежной памяти.
    """

    def __init__(self, size: int = BUFFER_SIZE):
        self.size   = size
        self._data  = bytearray(size)
        self._canary = bytearray(CANARY_VALUE)
        self._admin  = False

    def write(self, data: bytes) -> str:
        """Безопасная запись с проверкой границ и канарейки."""
        # Защита 1: проверка размера
        if len(data) > self.size:
            return f"ERROR: данные {len(data)} б превышают буфер {self.size} б"

        # Защита 2: запись только в выделенную область
        self._data[:len(data)] = data
        self._data[len(data):] = b"\x00" * (self.size - len(data))

        # Защита 3: проверка канарейки (не должна измениться)
        if bytes(self._canary) != CANARY_VALUE:
            log.critical("КАНАРЕЙКА ИСПОРЧЕНА — аварийная остановка!")
            return "CRITICAL: stack canary corrupted — connection terminated"

        return f"OK: записано {len(data)} байт"

    def read(self) -> bytes:
        return bytes(self._data)

    def canary_ok(self) -> bool:
        return bytes(self._canary) == CANARY_VALUE

    def status(self) -> str:
        canary_hex = self._canary.hex(" ")
        canary_ok  = self.canary_ok()
        data_hex   = self._data.hex(" ")
        return (
            f"Буфер ({self.size} б): {data_hex}\n"
            f"Канарейка: {canary_hex} | {'ЦЕЛА' if canary_ok else 'ИСПОРЧЕНА!'}\n"
            f"Флаг: {'ADMIN' if self._admin else 'USER'}"
        )


# ---------------------------------------------------------------------------
# Обработчик клиента
# ---------------------------------------------------------------------------

def handle_client(conn: socket.socket, addr):
    ip, port = addr
    log.info(f"[CONNECT] {ip}:{port}")
    conn.settimeout(SOCKET_TIMEOUT)
    buf = SecureBuffer()

    try:
        conn.sendall(b"220 SecureBuffer Server. Commands: STORE <data> | READ | STATUS | QUIT\r\n")

        while True:
            # Защита: ограничение размера пакета
            try:
                raw = conn.recv(MAX_RECV)
            except socket.timeout:
                conn.sendall(b"421 Timeout.\r\n")
                break

            if not raw:
                break

            if len(raw) > MAX_RECV:
                conn.sendall(b"400 Packet too large.\r\n")
                log.warning(f"[OVERFLOW ATTEMPT] {ip}:{port} — пакет {len(raw)} б")
                break

            line = raw.decode(errors="replace").strip()
            if not line:
                continue

            parts = line.split(None, 1)
            cmd   = parts[0].upper()
            arg   = parts[1] if len(parts) > 1 else ""

            # Белый список команд
            if cmd not in ALLOWED_COMMANDS:
                conn.sendall(f"501 Unknown command: {cmd}\r\n".encode())
                log.warning(f"[INVALID CMD] {ip}:{port} → '{cmd}'")
                continue

            if cmd == "STORE":
                if not arg:
                    conn.sendall(b"501 Syntax: STORE <data>\r\n")
                    continue
                data   = arg.encode()
                result = buf.write(data)
                status = "200" if result.startswith("OK") else "400"
                conn.sendall(f"{status} {result}\r\n".encode())
                log.info(f"[STORE] {ip}:{port} — {len(data)} б → {result}")

                # Проверка канарейки после записи
                if not buf.canary_ok():
                    conn.sendall(b"500 Stack canary corrupted. Terminating.\r\n")
                    log.critical(f"[CANARY] {ip}:{port} — канарейка испорчена!")
                    break

            elif cmd == "READ":
                data = buf.read()
                conn.sendall(f"200 {data.hex()}\r\n".encode())

            elif cmd == "STATUS":
                status_str = buf.status().replace("\n", " | ")
                conn.sendall(f"200 {status_str}\r\n".encode())

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
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(10)
    log.info(f"Сервер запущен на {HOST}:{PORT}")
    log.info(f"Буфер: {BUFFER_SIZE} б | Макс. пакет: {MAX_RECV} б | Канарейка: {CANARY_VALUE.hex()}")

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
        log.info("Сервер остановлен.")


if __name__ == "__main__":
    main()
