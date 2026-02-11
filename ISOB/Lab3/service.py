"""
Kerberos application service: validates ticket and authenticator, grants access.
"""

import socket
import time

from common import (
    AP_REPLY,
    AP_REQUEST,
    decode_msg,
    derive_key,
    decrypt,
    encode_msg,
    recv_frame,
    send_frame,
)

SERVICE_HOST = "127.0.0.1"
SERVICE_PORT = 8766

# Must match KDC SERVICES
SERVICE_SECRET = "service-host-secret"


def get_service_key() -> bytes:
    return derive_key(SERVICE_SECRET)


def handle_ap_req(body: dict) -> dict:
    """Verify ticket and authenticator, return AP_REP."""
    ticket_hex = body.get("ticket")
    authenticator_hex = body.get("authenticator")
    if not ticket_hex or not authenticator_hex:
        return {"error": "ticket and authenticator required"}

    try:
        service_key = get_service_key()
        ticket_payload = decode_msg(decrypt(service_key, bytes.fromhex(ticket_hex)))
    except Exception as e:
        return {"error": f"Invalid ticket: {e}"}

    if ticket_payload.get("expiry", 0) < time.time():
        return {"error": "Ticket expired"}

    service_session_key = bytes.fromhex(ticket_payload["service_session_key"])
    expected_user = ticket_payload["user"]

    try:
        auth_payload = decode_msg(decrypt(service_session_key, bytes.fromhex(authenticator_hex)))
    except Exception as e:
        return {"error": f"Invalid authenticator: {e}"}

    if auth_payload.get("user") != expected_user:
        return {"error": "User mismatch"}

    return {
        "type": AP_REPLY,
        "message": f"Hello, {expected_user}! Authentication successful.",
    }


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((SERVICE_HOST, SERVICE_PORT))
    sock.listen(5)
    print(f"Service listening on {SERVICE_HOST}:{SERVICE_PORT}")

    while True:
        conn, addr = sock.accept()
        try:
            frame = recv_frame(conn)
            msg = decode_msg(frame)
            if msg.get("type") == AP_REQUEST:
                response = handle_ap_req(msg)
            else:
                response = {"error": "Expected AP_REQ"}
            send_frame(conn, encode_msg(response))
        except Exception as e:
            send_frame(conn, encode_msg({"error": str(e)}))
        finally:
            conn.close()


if __name__ == "__main__":
    main()
