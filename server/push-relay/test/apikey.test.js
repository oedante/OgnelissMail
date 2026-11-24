'use strict';
// Ключ приложения обязателен (безопасность, этап 2, 24.11.2026): node --test

const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

function start(extraEnv) {
  const port = 20000 + Math.floor(Math.random() * 20000);
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: {
      PATH: process.env.PATH,
      PORT: String(port),
      HOST: '127.0.0.1',
      DATA_FILE: path.join(os.tmpdir(), `push-relay-key-${process.pid}-${port}.json`),
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d; });
  child.stderr.on('data', (d) => { out += d; });
  return { child, port, out: () => out };
}

async function waitUp(port) {
  for (let i = 0; i < 50; i++) {
    try { return await fetch(`http://127.0.0.1:${port}/push/healthz`); } catch (_) { await new Promise((r) => setTimeout(r, 100)); }
  }
  throw new Error('служба не ответила');
}

test('без PUSH_API_KEY служба не запускается', async () => {
  const s = start({});
  const code = await new Promise((resolve) => s.child.on('exit', resolve));
  assert.strictEqual(code, 1);
  assert.match(s.out(), /PUSH_API_KEY не задан/);
});

test('короткий ключ — тоже отказ', async () => {
  const s = start({ PUSH_API_KEY: 'short' });
  assert.strictEqual(await new Promise((resolve) => s.child.on('exit', resolve)), 1);
});

test('с ключом: чужой ключ — 401; PUSH_ALLOW_NO_KEY=1 — запуск без ключа', async () => {
  const s = start({ PUSH_API_KEY: 'test-push-key-0123456789' });
  try {
    await waitUp(s.port);
    const r = await fetch(`http://127.0.0.1:${s.port}/push/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': 'wrong' },
      body: JSON.stringify({ token: 'AB'.repeat(32), env: 'production', interval: 30, mode: 'silent' }),
    });
    assert.strictEqual(r.status, 401);
  } finally {
    s.child.kill();
  }
  const open = start({ PUSH_ALLOW_NO_KEY: '1' });
  try {
    assert.strictEqual((await waitUp(open.port)).status, 200);
    assert.match(open.out(), /только внутренняя сеть/);
  } finally {
    open.child.kill();
  }
});
