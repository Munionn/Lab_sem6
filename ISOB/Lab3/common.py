"""
Kerberos protocol — shared constants, crypto, and message formats.
Uses stdlib only: SHA256 key stream + HMAC for authenticated encryption.
"""

import hashlib
import hmac
import json
import os
import struct


def _key_stream(key: bytes, nonce: bytes, length: int) -> bytes:
    out = []
    n = 0
    while len(b"".join(out)) < length:
        h = hashlib.sha256(key + nonce + n.to_bytes(4, "big")).digest()
        out.append(h)
        n += 1
    return (b"".join(out))[:length]


def _xor(a: bytes, b: bytes) -> bytes:
    return bytes(x ^ y for x, y in zip(a, b))


def derive_key(password: str, salt: bytes = b"kerberos-lab3") -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 100000)


def encrypt(key: bytes, plaintext: bytes) -> bytes:
    nonce = os.urandom(16)
    stream = _key_stream(key, nonce, len(plaintext))
    ciphertext = _xor(plaintext, stream)
    tag = hmac.new(key, nonce + ciphertext, "sha256").digest()
    return nonce + tag + ciphertext


def decrypt(key: bytes, blob: bytes) -> bytes:
    if len(blob) < 16 + 32:
        raise ValueError("Invalid ciphertext")
    nonce = blob[:16]
    tag = blob[16:48]
    ciphertext = blob[48:]
    stream = _key_stream(key, nonce, len(ciphertext))
    plaintext = _xor(ciphertext, stream)
    if not hmac.compare_digest(hmac.new(key, nonce + ciphertext, "sha256").digest(), tag):
        raise ValueError("Bad tag")
    return plaintext


AS_REQUEST = "AS_REQ"
AS_REPLY = "AS_REP"
TGS_REQUEST = "TGS_REQ"
TGS_REPLY = "TGS_REP"
AP_REQUEST = "AP_REQ"
AP_REPLY = "AP_REP"

DEFAULT_REALM = "LAB3.LOCAL"


def encode_msg(obj: dict) -> bytes:
    return json.dumps(obj, separators=(",", ":")).encode("utf-8")


def decode_msg(data: bytes) -> dict:
    return json.loads(data.decode("utf-8"))


def send_frame(sock, data: bytes) -> None:
    sock.sendall(struct.pack(">I", len(data)) + data)


def recv_frame(sock) -> bytes:
    size = struct.unpack(">I", _read_exact(sock, 4))[0]
    if size > 1024 * 1024:
        raise ValueError("Frame too large")
    return _read_exact(sock, size)


def _read_exact(sock, n: int) -> bytes:
    buf = []
    while n > 0:
        chunk = sock.recv(n)
        if not chunk:
            raise ConnectionError("Connection closed")
        buf.append(chunk)
        n -= len(chunk)
    return b"".join(buf)
