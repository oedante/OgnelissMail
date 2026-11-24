'use strict';
// Сервер входа целиком (безопасность, этап 2, 24.11.2026): node --test
// Запускает server.js на свободном порту без сети к провайдерам. Нужен
// express: npm ci в server/oauth-proxy (без него проверка пропускается).

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const path = require('path');
const { spawn } = require('child_process');

let hasExpress = true;
try { require.resolve('express', { paths: [path.join(__dirname, '..')] }); } catch (_) { hasExpress = false; }

const KEY = 'test-api-key-0123456789';
let proc;
let base;

test.before(async () => {
  if (!hasExpress) return;
  proc = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: {
      PATH: process.env.PATH,
      PORT: '0',
      HOST: '127.0.0.1',
      BASE_URL: 'https://oauth.example.test',
      STATE_SECRET: 'state-secret-0123456789',
      ENC_SECRET: 'enc-secret-0123456789',
      PROXY_API_KEY: KEY,
      GOOGLE_CLIENT_ID: 'gid',
      GOOGLE_CLIENT_SECRET: 'gsecret',
      BIMI: '0',
      DATA_DIR: path.join(require('os').tmpdir(), `oauth-proxy-test-${process.pid}`),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  base = await new Promise((resolve, reject) => {
    let out = '';
    const t = setTimeout(() => reject(new Error(`сервер не запустился: ${out}`)), 10000);
    const onData = (d) => {
      out += d;
      const m = /listening on 127\.0\.0\.1:(\d+)/.exec(out);
      if (m) { clearTimeout(t); resolve(`http://127.0.0.1:${m[1]}`); }
    };
    proc.stdout.on('data', onData);
    proc.stderr.on('data', (d) => { out += d; });
    proc.on('exit', (c) => reject(new Error(`сервер завершился (${c}): ${out}`)));
  });
});

test.after(() => { if (proc) proc.kill(); });

const opts = { skip: !hasExpress && 'нет express (npm ci)' };
const APP = 'com.ogneliss.mail://oauth';
const cc = () => crypto.createHash('sha256').update(crypto.randomBytes(32).toString('base64url')).digest('base64url');

function get(p, headers = {}) {
  return fetch(base + p, { redirect: 'manual', headers });
}

test('вход без PKCE (старая сборка) — возврат в приложение с update_required', opts, async () => {
  const r = await get(`/oauth/google/login?redirect=${encodeURIComponent(APP)}`, { 'X-Forwarded-For': '198.51.100.1' });
  assert.strictEqual(r.status, 302);
  const loc = new URL(r.headers.get('location'));
  assert.strictEqual(loc.protocol, 'com.ogneliss.mail:');
  assert.strictEqual(loc.searchParams.get('error'), 'update_required');
  assert.strictEqual(loc.searchParams.get('at'), null);
});

test('вход с PKCE — к провайдеру', opts, async () => {
  const r = await get(`/oauth/google/login?redirect=${encodeURIComponent(APP)}&cc=${cc()}`, { 'X-Forwarded-For': '198.51.100.2' });
  assert.strictEqual(r.status, 302);
  const loc = new URL(r.headers.get('location'));
  assert.strictEqual(loc.host, 'accounts.google.com');
  assert.ok(loc.searchParams.get('state'));
});

test('хранение токенов на сервере убрано: GET /token?session и POST /refresh — 404', opts, async () => {
  const h = { 'x-api-key': KEY, 'Content-Type': 'application/json' };
  assert.strictEqual((await get('/token?session=abc', h)).status, 404);
  assert.strictEqual((await fetch(`${base}/refresh`, { method: 'POST', headers: h, body: '{"session":"abc"}' })).status, 404);
});

test('лимит входа на адрес; подменённый X-Forwarded-For не помогает', opts, async () => {
  // Запрос идёт с 127.0.0.1 (доверенный прокси): адрес клиента — последний
  // в X-Forwarded-For, вписанное клиентом левее не считается.
  const url = `/oauth/google/login?redirect=${encodeURIComponent(APP)}&cc=${cc()}`;
  let last;
  for (let i = 0; i < 21; i++) {
    last = await get(url, { 'X-Forwarded-For': `10.9.${i}.1, 203.0.113.50` });
    if (i < 20) assert.strictEqual(last.status, 302, `запрос ${i + 1}`);
  }
  assert.strictEqual(last.status, 429);
  assert.ok(Number(last.headers.get('retry-after')) > 0);
  // Другой адрес — свой счётчик.
  assert.strictEqual((await get(url, { 'X-Forwarded-For': '203.0.113.51' })).status, 302);
});

test('возврат с неверным state: после 10 неудач — пауза', opts, async () => {
  const h = { 'X-Forwarded-For': '203.0.113.60' };
  for (let i = 0; i < 10; i++) {
    const r = await get(`/callback?state=bad.${i}&code=x`, h);
    assert.strictEqual(r.status, 400, `попытка ${i + 1}`);
  }
  assert.strictEqual((await get('/callback?state=bad.x&code=x', h)).status, 429);
});

test('обмен: неверные коды — пауза; без ключа — 401', opts, async () => {
  const post = (body, ip, key = KEY) => fetch(`${base}/exchange`, {
    method: 'POST',
    headers: { 'x-api-key': key, 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
    body: JSON.stringify(body),
  });
  assert.strictEqual((await post({ oc: 'x', cv: 'y' }, '203.0.113.70', 'wrong')).status, 401);
  for (let i = 0; i < 10; i++) assert.strictEqual((await post({ oc: `x${i}`, cv: 'y' }, '203.0.113.71')).status, 400);
  const r = await post({ oc: 'x', cv: 'y' }, '203.0.113.71');
  assert.strictEqual(r.status, 429);
  assert.strictEqual((await r.json()).error, 'too_many_requests');
});

test('healthz: счётчики лимитов и id_token, без секретов', opts, async () => {
  const j = await (await get('/healthz')).json();
  assert.strictEqual(j.ok, true);
  assert.ok(j.limits.refused.login >= 1);
  assert.ok(j.limits.pauses.callback >= 1);
  assert.deepStrictEqual(j.idToken, { ok: 0, rejected: 0, noKeys: 0 });
  assert.ok(!JSON.stringify(j).includes('gsecret'));
});
