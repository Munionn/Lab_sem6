"""
Легитимный клиент для демонстрации работы защищённого сервера.

Использование:
    python client.py
"""

import socket

HOST = "127.0.0.1"
PORT = 9999


def send(sock: socket.socket, msg: str) -> str:
    sock.sendall((msg + "\r\n").encode())
    return sock.recv(4096).decode().strip()


def main():
    print("=" * 50)
    print("  Легитимный клиент")
    print("=" * 50)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((HOST, PORT))
        banner = s.recv(4096).decode().strip()
        print(f"Сервер: {banner}")

        # Попытка выполнить команду без авторизации
        resp = send(s, "PING")
        print(f"PING (без авторизации): {resp}")

        # Авторизация
        resp = send(s, "LOGIN admin secret123")
        print(f"LOGIN admin: {resp}")

        # Команды после авторизации
        resp = send(s, "PING")
        print(f"PING: {resp}")

        resp = send(s, "TIME")
        print(f"TIME: {resp}")

        resp = send(s, "ECHO Hello, secure world!")
        print(f"ECHO: {resp}")

        resp = send(s, "HELP")
        print(f"HELP: {resp}")

        resp = send(s, "QUIT")
        print(f"QUIT: {resp}")

    print("\nСоединение закрыто.")


if __name__ == "__main__":
    main()
