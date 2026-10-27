"""Loopback RFB extension fixture. No real desktop, credentials, or commands."""
import json
import socket
import struct
import sys
import zlib

server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen(1)
with open(sys.argv[1], 'w') as file:
    json.dump({'port': server.getsockname()[1]}, file)
connection, _ = server.accept()
connection.settimeout(10)

def read(count):
    data = b''
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise EOFError()
        data += chunk
    return data

def extended(flags, data=b''):
    payload = struct.pack('>I', flags) + data
    connection.sendall(b'\x03\x00\x00\x00' + struct.pack('>i', -len(payload)) + payload)

try:
    connection.sendall(b'RFB 003.008\n')
    read(12)
    connection.sendall(b'\x01\x01')
    assert read(1) == b'\x01'
    connection.sendall(struct.pack('>I', 0))
    read(1)
    pixel = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    connection.sendall(struct.pack('>HH', 16, 16) + pixel + struct.pack('>I', 4) + b'Test')
    while True:
        message = read(1)[0]
        if message == 0:
            read(19)
        elif message == 2:
            read(1)
            count = struct.unpack('>H', read(2))[0]
            encodings = struct.unpack('>' + 'I' * count, read(4 * count))
            assert 0xc0a1e5ce in encodings
            extended(0x1f000001, struct.pack('>I', 0))
        elif message == 3:
            read(9)
        elif message == 6:
            read(3)
            count = struct.unpack('>i', read(4))[0]
            assert count < 0
            payload = read(-count)
            flags = struct.unpack('>I', payload[:4])[0]
            action = flags & 0xff000000
            if action & 0x01000000:
                assert flags & 1
                assert struct.unpack('>I', payload[4:8])[0] == 0
                extended(0x08000001)
            elif action == 0x02000000:
                text = '遠隔\r\n🙂\0'.encode('utf-8')
                extended(0x10000001, zlib.compress(struct.pack('>I', len(text)) + text))
            elif action == 0x08000000:
                extended(0x02000001)
            elif action == 0x10000000:
                data = zlib.decompress(payload[4:])
                length = struct.unpack('>I', data[:4])[0]
                assert length == len(data) - 4
                text = data[4:].decode('utf-8')
                assert text.endswith('\0')
                with open(sys.argv[2], 'w') as file:
                    json.dump({'text': text[:-1]}, file)
            else:
                raise ValueError('Unexpected clipboard action')
        else:
            raise ValueError('Unexpected RFB message')
except (EOFError, ConnectionError):
    pass
finally:
    connection.close()
    server.close()
