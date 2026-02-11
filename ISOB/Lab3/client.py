"""
Kerberos client: obtains TGT from AS, service ticket from TGS, then accesses service.
"""

import socket
import time

from common import (
    AS_REPLY,
    AS_REQUEST,
    AP_REPLY,
    AP_REQUEST,
    DEFAULT_REALM,
    TGS_REPLY,
    TGS_REQUEST,
    decode_msg,
    derive_key,
    encrypt,
    decrypt,
    encode_msg,
    recv_frame,
    send_frame,
)

KDC_HOST = "127.0.0.1"
KDC_PORT = 8765
SERVICE_HOST = "127.0.0.1"
SERVICE_PORT = 8766


def request_tgt(username: str, password: str) -> tuple[bytes, bytes]:
    user_key = derive_key(password)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((KDC_HOST, KDC_PORT))
    try:
        req = encode_msg({
            "type": AS_REQUEST,
            "user": username,
            "realm": DEFAULT_REALM,
        })
        send_frame(sock, req)
        raw = recv_frame(sock)
        rep = decode_msg(raw)
        if "error" in rep:
            raise RuntimeError(rep["error"])
        if rep.get("type") != AS_REPLY:
            raise RuntimeError("Unexpected AS reply")

        reply_payload = decode_msg(decrypt(user_key, bytes.fromhex(rep["encrypted_reply"])))
        session_key = bytes.fromhex(reply_payload["session_key"])
        tgt = bytes.fromhex(reply_payload["tgt"])
        return tgt, session_key
    finally:
        sock.close()


def request_service_ticket(tgt: bytes, session_key: bytes, user: str, service_name: str) -> tuple[bytes, bytes]:
    authenticator = encode_msg({
        "user": user,
        "timestamp": time.time(),
    })
    enc_authenticator = encrypt(session_key, authenticator)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((KDC_HOST, KDC_PORT))
    try:
        req = encode_msg({
            "type": TGS_REQUEST,
            "tgt": tgt.hex(),
            "authenticator": enc_authenticator.hex(),
            "service_name": service_name,
        })
        send_frame(sock, req)
        raw = recv_frame(sock)
        rep = decode_msg(raw)
        if "error" in rep:
            raise RuntimeError(rep["error"])
        if rep.get("type") != TGS_REPLY:
            raise RuntimeError("Unexpected TGS reply")

        reply_payload = decode_msg(decrypt(session_key, bytes.fromhex(rep["encrypted_reply"])))
        service_session_key = bytes.fromhex(reply_payload["service_session_key"])
        service_ticket = bytes.fromhex(reply_payload["service_ticket"])
        return service_ticket, service_session_key
    finally:
        sock.close()


def access_service(service_ticket: bytes, service_session_key: bytes, user: str) -> str:
    authenticator = encode_msg({
        "user": user,
        "timestamp": time.time(),
    })
    enc_authenticator = encrypt(service_session_key, authenticator)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((SERVICE_HOST, SERVICE_PORT))
    try:
        req = encode_msg({
            "type": AP_REQUEST,
            "ticket": service_ticket.hex(),
            "authenticator": enc_authenticator.hex(),
        })
        send_frame(sock, req)
        raw = recv_frame(sock)
        rep = decode_msg(raw)
        if "error" in rep:
            raise RuntimeError(rep["error"])
        return rep.get("message", rep.get("type", ""))
    finally:
        sock.close()


def authenticate_and_access(username: str, password: str, service_name: str = "host") -> str:
    """Full Kerberos flow: AS -> TGS -> Service. Returns service response."""
    tgt, session_key = request_tgt(username, password)
    ticket, service_session_key = request_service_ticket(tgt, session_key, username, service_name)
    return access_service(ticket, service_session_key, username)


if __name__ == "__main__":
    import sys
    user = sys.argv[1] if len(sys.argv) > 1 else "alice"
    password = sys.argv[2] if len(sys.argv) > 2 else "alice-secret"

    print(f"Authenticating as {user}...")
    try:
        msg = authenticate_and_access(user, password)
        print(f"Service response: {msg}")
    except Exception as e:
        print(f"Error: {e}")
