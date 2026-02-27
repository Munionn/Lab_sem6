"""
Лабораторная работа 5.
Защита от атаки на переполнение буфера.

Демонстрация концепции переполнения буфера через симуляцию «стека»
на основе bytearray (аналог C-стека в памяти).

Симулируемая память (стек кадра):
┌──────────────────────┐  ← низкий адрес
│   БУФЕР (16 байт)    │  ← сюда копируем входные данные
├──────────────────────┤
│  STACK CANARY (4 б)  │  ← магическое значение для обнаружения overflow
├──────────────────────┤
│   ФЛАГ АДМИНА (1 б)  │  ← 0x00 = обычный, 0x01 = администратор
├──────────────────────┤
│ АДРЕС ВОЗВРАТА (8 б) │  ← «куда вернуться» после функции
└──────────────────────┘  ← высокий адрес

Части:
  1. vulnerable_copy  — копирование без проверки границ (УЯЗВИМО)
  2. safe_copy        — копирование с проверкой (ЗАЩИЩЕНО)
  3. Демонстрация stack canary
  4. Демонстрация format-string уязвимости и защиты
"""

import struct
import os

# ---------------------------------------------------------------------------
# Константы макета памяти
# ---------------------------------------------------------------------------

BUFFER_SIZE    = 16    # байт — размер «безопасного» буфера
CANARY_VALUE   = b"\xDE\xAD\xBE\xEF"   # магическое значение канарейки
CANARY_SIZE    = 4
ADMIN_FLAG_OFF = BUFFER_SIZE + CANARY_SIZE        # смещение флага админа
RET_ADDR_OFF   = ADMIN_FLAG_OFF + 1               # смещение адреса возврата
FRAME_SIZE     = RET_ADDR_OFF + 8                 # полный размер кадра стека

FAKE_RET_ADDR  = struct.pack("<Q", 0x00007FFF_DEAD0000)   # «нормальный» адрес возврата
EVIL_RET_ADDR  = struct.pack("<Q", 0x00007FFF_CAFEBABE)   # адрес evil-функции атакующего


# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

def make_stack_frame() -> bytearray:
    """Создать начальное состояние кадра стека."""
    frame = bytearray(FRAME_SIZE)
    # Заполнить буфер нулями
    frame[0:BUFFER_SIZE] = b"\x00" * BUFFER_SIZE
    # Поставить канарейку
    frame[BUFFER_SIZE: BUFFER_SIZE + CANARY_SIZE] = CANARY_VALUE
    # Флаг админа = 0
    frame[ADMIN_FLAG_OFF] = 0x00
    # Адрес возврата
    frame[RET_ADDR_OFF: RET_ADDR_OFF + 8] = FAKE_RET_ADDR
    return frame


def print_frame(frame: bytearray, label: str = ""):
    """Красивый дамп кадра стека."""
    if label:
        print(f"  [{label}]")
    buf      = frame[0:BUFFER_SIZE]
    canary   = frame[BUFFER_SIZE: BUFFER_SIZE + CANARY_SIZE]
    is_admin = frame[ADMIN_FLAG_OFF]
    ret_addr = frame[RET_ADDR_OFF: RET_ADDR_OFF + 8]

    print(f"    Буфер      : {buf.hex(' ')}  | ASCII: {_safe_ascii(buf)}")
    print(f"    Канарейка  : {canary.hex(' ')}  "
          f"| {'OK ✓' if canary == CANARY_VALUE else 'ИСПОРЧЕНА ✗'}")
    print(f"    Флаг админа: 0x{is_admin:02X}  "
          f"| {'АДМИНИСТРАТОР!' if is_admin else 'обычный пользователь'}")
    print(f"    Адрес возвр: {ret_addr.hex(' ')}")


def _safe_ascii(b: bytes) -> str:
    return "".join(chr(c) if 32 <= c < 127 else "." for c in b)


def check_canary(frame: bytearray) -> bool:
    return bytes(frame[BUFFER_SIZE: BUFFER_SIZE + CANARY_SIZE]) == CANARY_VALUE


# ---------------------------------------------------------------------------
# 1. УЯЗВИМАЯ функция копирования (нет проверки размера)
# ---------------------------------------------------------------------------

def vulnerable_copy(frame: bytearray, data: bytes) -> bytearray:
    """
    Аналог небезопасного memcpy в C — копирует data в буфер
    без проверки длины. Если data длиннее BUFFER_SIZE,
    данные затирают канарейку, флаг, адрес возврата.
    """
    for i, byte in enumerate(data):
        if i >= FRAME_SIZE:
            break                 # физический конец памяти кадра
        frame[i] = byte
    return frame


# ---------------------------------------------------------------------------
# 2. ЗАЩИЩЁННАЯ функция копирования
# ---------------------------------------------------------------------------

def safe_copy(frame: bytearray, data: bytes) -> tuple[bytearray, str]:
    """
    Защищённое копирование:
      - проверяет размер входных данных
      - копирует не более BUFFER_SIZE байт
      - проверяет канарейку после копирования
    Возвращает (frame, статус).
    """
    # Защита 1: проверка размера
    if len(data) > BUFFER_SIZE:
        return frame, f"ОТКЛОНЕНО: входные данные {len(data)} б > буфер {BUFFER_SIZE} б"

    # Защита 2: безопасная запись только в зону буфера
    frame[0:len(data)] = data

    # Защита 3: проверка канарейки после записи
    if not check_canary(frame):
        return frame, "ТРЕВОГА: канарейка испорчена — атака обнаружена!"

    return frame, "OK"


# ---------------------------------------------------------------------------
# 3. Демонстрации
# ---------------------------------------------------------------------------

SEP = "=" * 58


def demo_overflow_no_protection():
    print(f"\n{SEP}")
    print("  ДЕМО 1: Переполнение буфера БЕЗ защиты")
    print(SEP)

    frame = make_stack_frame()
    print("\n  Начальное состояние стека:")
    print_frame(frame, "до атаки")

    # Нормальный ввод — всё хорошо
    normal_input = b"Hello"
    frame2 = make_stack_frame()
    vulnerable_copy(frame2, normal_input)
    print(f"\n  Нормальный ввод ({len(normal_input)} б): {normal_input!r}")
    print_frame(frame2, "после нормального ввода")

    # Атакующий payload: 16 байт мусора + затираем канарейку + флаг + адрес возврата
    payload = (
        b"A" * BUFFER_SIZE           # заполняем буфер
        + b"\x00" * CANARY_SIZE      # затираем канарейку нулями
        + b"\x01"                    # флаг админа = 1 (PRIVILEGE ESCALATION!)
        + EVIL_RET_ADDR              # подменяем адрес возврата
    )
    print(f"\n  Вредоносный payload ({len(payload)} б):")
    print(f"    {payload.hex(' ')}")

    vulnerable_copy(frame, payload)
    print("\n  Состояние стека ПОСЛЕ атаки:")
    print_frame(frame, "после overflow")

    if frame[ADMIN_FLAG_OFF] == 0x01:
        print("\n  [!!!] PRIVILEGE ESCALATION: атакующий получил права администратора!")
    ret = frame[RET_ADDR_OFF: RET_ADDR_OFF + 8]
    if ret == EVIL_RET_ADDR:
        print("  [!!!] HIJACK: адрес возврата подменён — исполнение перейдёт к коду атакующего!")


def demo_overflow_with_protection():
    print(f"\n{SEP}")
    print("  ДЕМО 2: Переполнение буфера С защитой (safe_copy + canary)")
    print(SEP)

    # Тот же вредоносный payload
    payload = (
        b"A" * BUFFER_SIZE
        + b"\x00" * CANARY_SIZE
        + b"\x01"
        + EVIL_RET_ADDR
    )

    # --- Попытка 1: превышение размера ---
    frame = make_stack_frame()
    _, status = safe_copy(frame, payload)
    print(f"\n  Payload ({len(payload)} б) → safe_copy → {status}")
    print_frame(frame, "стек после попытки (не изменён)")

    # --- Попытка 2: ровно по границе ---
    ok_data = b"B" * BUFFER_SIZE
    frame2 = make_stack_frame()
    _, status2 = safe_copy(frame2, ok_data)
    print(f"\n  Данные {len(ok_data)} б (ровно в буфер) → safe_copy → {status2}")
    print_frame(frame2, "стек (буфер заполнен безопасно)")


def demo_stack_canary():
    print(f"\n{SEP}")
    print("  ДЕМО 3: Stack Canary — обнаружение переполнения")
    print(SEP)
    print(f"\n  Канарейка = {CANARY_VALUE.hex(' ')}  (магическое значение между буфером и служебными данными)")

    frame = make_stack_frame()
    print(f"\n  Начальная канарейка: {bytes(frame[BUFFER_SIZE:BUFFER_SIZE+CANARY_SIZE]).hex(' ')} → {'ЦЕЛА' if check_canary(frame) else 'ИСПОРЧЕНА'}")

    # Атакующий пишет 20 байт — задевает канарейку
    overflow = b"X" * (BUFFER_SIZE + 2)   # на 2 байта заходит в зону канарейки
    vulnerable_copy(frame, overflow)
    canary_now = bytes(frame[BUFFER_SIZE:BUFFER_SIZE + CANARY_SIZE])
    print(f"  После overflow {len(overflow)} б: {canary_now.hex(' ')} → {'ЦЕЛА' if check_canary(frame) else 'ИСПОРЧЕНА!'}")

    if not check_canary(frame):
        print("  [ЗАЩИТА] Канарейка испорчена — аварийное завершение программы (аналог abort()).")
        print("           Атака обнаружена до исполнения кода атакующего.")


def demo_format_string():
    print(f"\n{SEP}")
    print("  ДЕМО 4: Format-string уязвимость и защита")
    print(SEP)

    secret_data = {"password": "s3cr3t!", "admin_key": "KEY-0xDEAD"}

    def vulnerable_log(user_input: str):
        """Уязвимо: передаём пользовательскую строку напрямую в format."""
        # В C это было бы: printf(user_input) — без %s
        # В Python имитируем: eval/format с данными из окружения
        try:
            msg = user_input.format(**secret_data)   # атакующий читает secret_data!
            print(f"    Лог: {msg}")
        except KeyError:
            print(f"    Лог: {user_input}")

    def safe_log(user_input: str):
        """Защищено: пользовательский ввод не интерпретируется как шаблон."""
        print(f"    Лог: {user_input}")   # передаём как литеральную строку

    normal  = "Пользователь вошёл в систему"
    exploit = "Привет! Пароль={password}, ключ={admin_key}"

    print("\n  --- Уязвимая функция ---")
    print(f"  Нормальный ввод: '{normal}'")
    vulnerable_log(normal)
    print(f"\n  Вредоносный ввод: '{exploit}'")
    print("  Результат:", end=" ")
    vulnerable_log(exploit)
    print("  [!!!] Атакующий прочитал секретные данные через format-string!")

    print("\n  --- Защищённая функция ---")
    print(f"  Тот же вредоносный ввод: '{exploit}'")
    print("  Результат:", end=" ")
    safe_log(exploit)
    print("  [OK] Строка выведена как есть, секреты не раскрыты.")


def demo_bounds_check():
    print(f"\n{SEP}")
    print("  ДЕМО 5: Проверка границ массива (off-by-one)")
    print(SEP)

    arr = [0] * 8
    print(f"\n  Массив размером {len(arr)}: {arr}")

    def vulnerable_fill(array: list, index: int, value: int):
        array[index] = value    # нет проверки индекса

    def safe_fill(array: list, index: int, value: int) -> str:
        if index < 0 or index >= len(array):
            return f"ОТКЛОНЕНО: индекс {index} вне границ [0, {len(array)-1}]"
        array[index] = value
        return "OK"

    print("\n  Уязвимая функция:")
    for idx in [0, 7, 8, -1, 100]:
        try:
            arr_copy = arr[:]
            vulnerable_fill(arr_copy, idx, 0xFF)
            print(f"    fill[{idx:4}] = 0xFF → OK  (массив: {arr_copy})")
        except IndexError as e:
            print(f"    fill[{idx:4}] = 0xFF → IndexError: {e}")

    print("\n  Защищённая функция:")
    for idx in [0, 7, 8, -1, 100]:
        arr_copy = arr[:]
        status = safe_fill(arr_copy, idx, 0xFF)
        print(f"    fill[{idx:4}] = 0xFF → {status}")


# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------

def main():
    print("=" * 58)
    print("  Лабораторная работа 5")
    print("  Защита от атаки на переполнение буфера")
    print("=" * 58)
    print("\nВыберите демонстрацию:")
    print("  1 — Переполнение БЕЗ защиты (privilege escalation + hijack)")
    print("  2 — Переполнение С защитой (safe_copy)")
    print("  3 — Stack Canary")
    print("  4 — Format-string уязвимость и защита")
    print("  5 — Проверка границ массива (off-by-one)")
    print("  6 — Все демонстрации")

    choice = input("\nВаш выбор: ").strip()

    demos = {
        "1": demo_overflow_no_protection,
        "2": demo_overflow_with_protection,
        "3": demo_stack_canary,
        "4": demo_format_string,
        "5": demo_bounds_check,
    }

    if choice == "6":
        for fn in demos.values():
            fn()
    elif choice in demos:
        demos[choice]()
    else:
        print("Неверный выбор.")


if __name__ == "__main__":
    main()
