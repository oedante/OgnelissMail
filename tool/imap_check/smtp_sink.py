#!/usr/bin/env python3
"""SMTP-приёмник для проверки отправки (tool/imap_check, 01.11.2026).

Принимает любой вход (AUTH PLAIN/LOGIN), объявляет DSN и сохраняет каждое
письмо в каталог: <n>.eml и <n>.env (команды MAIL FROM / RCPT TO — по ним
видно, запрошен ли отчёт о доставке). Только для локальной проверки,
никуда ничего не пересылает.

    python3 tool/imap_check/smtp_sink.py 1025 /tmp/smtp-sink
"""

import asyncio
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 1025
OUT = sys.argv[2] if len(sys.argv) > 2 else 'smtp-sink'
os.makedirs(OUT, exist_ok=True)
counter = [len([f for f in os.listdir(OUT) if f.endswith('.eml')])]


async def session(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    def send(line: str) -> None:
        writer.write((line + '\r\n').encode())

    send('220 sink ESMTP')
    await writer.drain()
    env: list[str] = []
    while True:
        raw = await reader.readline()
        if not raw:
            break
        line = raw.decode('utf-8', 'replace').rstrip('\r\n')
        cmd = line.upper()
        if cmd.startswith('EHLO'):
            for l in ('250-sink', '250-AUTH PLAIN LOGIN', '250-DSN', '250-8BITMIME', '250-SIZE 52428800'):
                send(l)
            send('250 SMTPUTF8')
        elif cmd.startswith('HELO'):
            send('250 sink')
        elif cmd.startswith('AUTH PLAIN'):
            if len(line.split()) == 2:
                send('334 ')
                await writer.drain()
                await reader.readline()
            send('235 2.7.0 ok')
        elif cmd.startswith('AUTH LOGIN'):
            send('334 VXNlcm5hbWU6')
            await writer.drain()
            await reader.readline()
            send('334 UGFzc3dvcmQ6')
            await writer.drain()
            await reader.readline()
            send('235 2.7.0 ok')
        elif cmd.startswith('MAIL FROM') or cmd.startswith('RCPT TO'):
            env.append(line)
            send('250 ok')
        elif cmd == 'DATA':
            send('354 go')
            await writer.drain()
            data = []
            while True:
                l = await reader.readline()
                if not l or l in (b'.\r\n', b'.\n'):
                    break
                data.append(l[1:] if l.startswith(b'..') else l)
            counter[0] += 1
            n = counter[0]
            with open(os.path.join(OUT, f'{n}.eml'), 'wb') as f:
                f.write(b''.join(data))
            with open(os.path.join(OUT, f'{n}.env'), 'w', encoding='utf-8') as f:
                f.write('\n'.join(env) + '\n')
            env = []
            send('250 2.0.0 queued')
        elif cmd in ('RSET', 'NOOP'):
            env = [] if cmd == 'RSET' else env
            send('250 ok')
        elif cmd == 'QUIT':
            send('221 bye')
            await writer.drain()
            break
        else:
            send('502 not implemented')
        await writer.drain()
    writer.close()


async def main() -> None:
    server = await asyncio.start_server(session, '127.0.0.1', PORT)
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    asyncio.run(main())
