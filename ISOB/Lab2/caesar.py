LATIN_LOWER = "abcdefghijklmnopqrstuvwxyz"
LATIN_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CYRILLIC_LOWER = "абвгдежзийклмнопрстуфхцчшщъыьэюя"
CYRILLIC_UPPER = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
ALPHABETS = [LATIN_LOWER, LATIN_UPPER, CYRILLIC_LOWER, CYRILLIC_UPPER]


def _shift_char(ch: str, shift: int) -> str:
    for alphabet in ALPHABETS:
        if ch in alphabet:
            idx = alphabet.index(ch)
            return alphabet[(idx + shift) % len(alphabet)]
    return ch


def encrypt(text: str, shift: int) -> str:
    return "".join(_shift_char(c, shift) for c in text)


def decrypt(text: str, shift: int) -> str:
    return encrypt(text, -shift)
