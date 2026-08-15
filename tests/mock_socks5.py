#!/usr/bin/env python3
import socket
import struct
import sys
import threading


def recv_exact(conn, size):
    data = b""
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise ConnectionError("unexpected EOF")
        data += chunk
    return data


def handle(conn):
    try:
        first = recv_exact(conn, 1)
        if first != b"\x05":
            return

        nmethods = recv_exact(conn, 1)[0]
        recv_exact(conn, nmethods)
        conn.sendall(b"\x05\x00")

        version, command, _reserved, atyp = recv_exact(conn, 4)
        if version != 5 or command != 1:
            return

        if atyp == 1:
            recv_exact(conn, 4)
        elif atyp == 3:
            length = recv_exact(conn, 1)[0]
            recv_exact(conn, length)
        elif atyp == 4:
            recv_exact(conn, 16)
        else:
            return
        recv_exact(conn, 2)

        conn.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")

        request = b""
        while b"\r\n\r\n" not in request and len(request) < 65536:
            chunk = conn.recv(4096)
            if not chunk:
                break
            request += chunk

        conn.sendall(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    except (ConnectionError, OSError):
        pass
    finally:
        conn.close()


def main():
    if len(sys.argv) != 2:
        print("usage: mock_socks5.py <port-file>", file=sys.stderr)
        return 2

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    port = listener.getsockname()[1]

    with open(sys.argv[1], "w", encoding="utf-8") as handle_file:
        handle_file.write(str(port))

    try:
        while True:
            conn, _addr = listener.accept()
            threading.Thread(target=handle, args=(conn,), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        listener.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
