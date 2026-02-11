LATIN_LOWER = "abcdefghijklmnopqrstuvwxyz"
LATIN_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CYRILLIC_LOWER = "абвгдежзийклмнопрстуфхцчшщъыьэюя"
CYRILLIC_UPPER = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
ALPHABETS = [LATIN_LOWER, LATIN_UPPER, CYRILLIC_LOWER, CYRILLIC_UPPER]


def _alphabet_for(ch: str):
    for a in ALPHABETS:
        if ch in a:
            return a
    return None

def _shift_for_key_char(k: str) -> int:
    for a in ALPHABETS:
        if k in a:
            return a.index(k) % len(a)
    return 0


def encrypt(text: str, key: str) -> str:
    if not key:
        raise ValueError("Key must not be empty")
    out = []
    ki = 0
    for c in text:
        a = _alphabet_for(c)
        if a is None:
            out.append(c)
        else:
            shift = _shift_for_key_char(key[ki % len(key)])
            out.append(a[(a.index(c) + shift) % len(a)])
            ki += 1
    return "".join(out)


def decrypt(text: str, key: str) -> str:
    if not key:
        raise ValueError("Key must not be empty")
    out = []
    ki = 0
    for c in text:
        a = _alphabet_for(c)
        if a is None:
            out.append(c)
        else:
            shift = _shift_for_key_char(key[ki % len(key)])
            out.append(a[(a.index(c) - shift) % len(a)])
            ki += 1
    return "".join(out)
