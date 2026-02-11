import socket
import time

from common import (
    AS_REPLY,
    AS_REQUEST,
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

USERS = {
    "name": "name-secret",
    "name2": "name2-secret",
    "name3": "name3-secret",
}

TGS_SECRET = "tgs-secret-key-lab3"

SERVICES = {"host": "service-host-secret"}


def get_user_key(username: str) -> bytes:
    if username not in USERS:
        raise ValueError(f"Unknown user: {username}")
    return derive_key(USERS[username])


def get_tgs_key() -> bytes:
    return derive_key(TGS_SECRET)


def get_service_key(service_name: str) -> bytes:
    if service_name not in SERVICES:
        raise ValueError(f"Unknown service: {service_name}")
    return derive_key(SERVICES[service_name])


def handle_as_req(body: dict) -> dict:
    user = body.get("user")
    realm = body.get("realm", DEFAULT_REALM)
    if not user:
        return {"error": "user required"}

    try:
        user_key = get_user_key(user)
    except ValueError as e:
        return {"error": str(e)}

    session_key = derive_key(f"{user}:{time.time()}:session")[:32]

    tgt_payload = encode_msg({
        "user": user,
        "realm": realm,
        "session_key": session_key.hex(),
        "expiry": time.time() + 3600,
    })
    tgt = encrypt(get_tgs_key(), tgt_payload)

    reply_payload = encode_msg({
        "session_key": session_key.hex(),
        "tgt": tgt.hex(),
        "realm": realm,
    })
    encrypted_reply = encrypt(user_key, reply_payload)

    return {
        "type": AS_REPLY,
        "encrypted_reply": encrypted_reply.hex(),
    }


def handle_tgs_req(body: dict) -> dict:
    tgt_hex = body.get("tgt")
    authenticator_hex = body.get("authenticator")
    service_name = body.get("service_name")
    if not tgt_hex or not authenticator_hex or not service_name:
        return {"error": "tgt, authenticator, service_name required"}

    try:
        tgs_key = get_tgs_key()
        tgt_payload = decode_msg(decrypt(tgs_key, bytes.fromhex(tgt_hex)))
    except Exception as e:
        return {"error": f"Invalid TGT: {e}"}

    if tgt_payload.get("expiry", 0) < time.time():
        return {"error": "TGT expired"}

    session_key = bytes.fromhex(tgt_payload["session_key"])
    user = tgt_payload["user"]

    try:
        auth_payload = decode_msg(decrypt(session_key, bytes.fromhex(authenticator_hex)))
    except Exception as e:
        return {"error": f"Invalid authenticator: {e}"}

    if auth_payload.get("user") != user:
        return {"error": "Authenticator user mismatch"}

    service_session_key = derive_key(f"{user}:{service_name}:{time.time()}")[:32]
    service_key = get_service_key(service_name)

    ticket_payload = encode_msg({
        "user": user,
        "service_session_key": service_session_key.hex(),
        "expiry": time.time() + 300,
    })
    service_ticket = encrypt(service_key, ticket_payload)

    reply_payload = encode_msg({
        "service_session_key": service_session_key.hex(),
        "service_ticket": service_ticket.hex(),
    })
    encrypted_reply = encrypt(session_key, reply_payload)

    return {
        "type": TGS_REPLY,
        "encrypted_reply": encrypted_reply.hex(),
    }


def handle_request(data: bytes) -> bytes:
    msg = decode_msg(data)
    msg_type = msg.get("type")

    if msg_type == AS_REQUEST:
        out = handle_as_req(msg)
    elif msg_type == TGS_REQUEST:
        out = handle_tgs_req(msg)
    else:
        out = {"error": f"Unknown request type: {msg_type}"}

    return encode_msg(out)


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((KDC_HOST, KDC_PORT))
    sock.listen(5)
    print(f"KDC listening on {KDC_HOST}:{KDC_PORT} (AS + TGS)")

    while True:
        conn, addr = sock.accept()
        try:
            frame = recv_frame(conn)
            response = handle_request(frame)
            send_frame(conn, response)
        except Exception as e:
            send_frame(conn, encode_msg({"error": str(e)}))
        finally:
            conn.close()


if __name__ == "__main__":
    main()
